#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
PRODUCTION_DIR="/opt/n8n-data/production"
MONITORING_DIR="${PRODUCTION_DIR}/monitoring"
CONFIG_DIR="${PRODUCTION_DIR}/config"
DOMAIN_NAME=${DOMAIN_NAME:-"localhost"}

# Function to set up advanced health checks
setup_advanced_health_checks() {
    log "Setting up advanced health checks..."
    
    # Create health check script
    local health_check_file="${PRODUCTION_DIR}/advanced-health-check.sh"
    
    cat > "$health_check_file" << 'EOL'
#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/common.sh"

# Check container health with resource usage
check_container_health_advanced() {
    local container="$1"
    local status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
    
    if [[ "$status" != "running" ]]; then
        error "Container $container is not running (status: $status)"
        return 1
    fi
    
    # Check CPU usage
    local cpu_usage=$(docker stats --no-stream --format "{{.CPUPerc}}" "$container" | sed 's/%//')
    if (( $(echo "$cpu_usage > 90" | bc -l) )); then
        warn "Container $container CPU usage is high: ${cpu_usage}%"
    fi
    
    # Check memory usage
    local mem_usage=$(docker stats --no-stream --format "{{.MemPerc}}" "$container" | sed 's/%//')
    if (( $(echo "$mem_usage > 90" | bc -l) )); then
        warn "Container $container memory usage is high: ${mem_usage}%"
    fi
    
    return 0
}

# Check database connection
check_database_connection() {
    log "Checking database connection..."
    if ! docker exec n8n-postgres pg_isready -U postgres; then
        error "Database connection failed"
        return 1
    fi
    log "Database connection successful"
    return 0
}

# Check n8n API health
check_n8n_api() {
    local domain="${DOMAIN_NAME:-localhost}"
    local protocol="https"
    
    if [[ "$domain" == "localhost" ]]; then
        protocol="http"
    fi
    
    log "Checking n8n API health at ${protocol}://${domain}/healthz..."
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "${protocol}://${domain}/healthz")
    if [[ "$response" != "200" ]]; then
        error "n8n API health check failed with status code: $response"
        return 1
    fi
    
    log "n8n API health check successful"
    return 0
}

# Check disk space with more detailed thresholds
check_disk_space_advanced() {
    local path=${1:-"/opt/n8n-data"}
    local warning_threshold=${2:-80}  # Warning at 80% usage
    local critical_threshold=${3:-90} # Critical at 90% usage
    
    local usage=$(df -h "$path" | awk 'NR==2 {print $5}' | sed 's/%//')
    local available=$(df -h "$path" | awk 'NR==2 {print $4}')
    
    log "Disk usage for $path: ${usage}% (${available} available)"
    
    if [[ $usage -ge $critical_threshold ]]; then
        error "Critical disk space usage at ${usage}% (threshold: ${critical_threshold}%)"
        return 2
    elif [[ $usage -ge $warning_threshold ]]; then
        warn "Warning: disk space usage at ${usage}% (threshold: ${warning_threshold}%)"
        return 1
    fi
    
    return 0
}

# Check recent backups with verification
check_recent_backup_advanced() {
    log "Checking recent backups..."
    
    # Check for local backups
    local recent_local=$(find "/opt/n8n-data" -name "backup_*.log" -mtime -1 | wc -l)
    
    # Check for S3 backups if configured
    local recent_s3=0
    if [[ -f "/opt/n8n-data/s3.env" ]]; then
        source "/opt/n8n-data/s3.env"
        if [[ -n "$S3_BUCKET_NAME" ]]; then
            recent_s3=$(aws s3 ls "s3://${S3_BUCKET_NAME}/backups/" --recursive | grep -c "$(date +%Y%m%d)")
        fi
    fi
    
    if [[ $recent_local -eq 0 && $recent_s3 -eq 0 ]]; then
        error "No recent backups found in the last 24 hours"
        return 1
    fi
    
    log "Found recent backups: $recent_local local, $recent_s3 in S3"
    return 0
}

# Run all advanced health checks
run_advanced_health_checks() {
    log "Running advanced health checks..."
    
    local exit_code=0
    local failed_checks=()
    
    # Check all containers
    for service in n8n postgres qdrant; do
        if ! check_container_health_advanced "n8n-$service"; then
            exit_code=1
            failed_checks+=("container_health:$service")
        fi
    done
    
    # Check database connection
    if ! check_database_connection; then
        exit_code=1
        failed_checks+=("database_connection")
    fi
    
    # Check n8n API
    if ! check_n8n_api; then
        exit_code=1
        failed_checks+=("n8n_api")
    fi
    
    # Check disk space
    if ! check_disk_space_advanced "/opt/n8n-data" 80 90; then
        exit_code=1
        failed_checks+=("disk_space")
    fi
    
    # Check recent backups
    if ! check_recent_backup_advanced; then
        exit_code=1
        failed_checks+=("recent_backup")
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log "All advanced health checks passed"
    else
        error "Some health checks failed: ${failed_checks[*]}"
    fi
    
    return $exit_code
}

# Main execution
run_advanced_health_checks
exit $?
EOL
    
    chmod +x "$health_check_file"
    log "Advanced health check script created at $health_check_file"
    
    # Create cron job for regular health checks
    local cron_file="/etc/cron.d/n8n-health-checks"
    
    cat > "$cron_file" << EOL
# Run advanced health checks every 15 minutes
*/15 * * * * root ${health_check_file} >> /var/log/n8n-health-checks.log 2>&1
EOL
    
    log "Cron job for health checks created at $cron_file"
    return 0
}

# Function to set up rate limiting
setup_rate_limiting() {
    log "Setting up rate limiting..."
    
    # Create rate limiting configuration for Traefik
    local rate_limit_file="${CONFIG_DIR}/rate-limit.yml"
    
    cat > "$rate_limit_file" << EOL
http:
  middlewares:
    rateLimit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
EOL
    
    log "Rate limiting configuration created at $rate_limit_file"
    
    # Update docker-compose.yml to include rate limiting middleware
    update_compose_file_rate_limit "../docker-compose.yml"
    
    log "Rate limiting configured successfully"
    return 0
}

# Function to update docker-compose.yml for rate limiting
update_compose_file_rate_limit() {
    local compose_file=$1
    local temp_file="${compose_file}.tmp"
    
    log "Updating $compose_file to include rate limiting middleware..."
    
    # Check if file exists
    if [[ ! -f "$compose_file" ]]; then
        error "Compose file not found: $compose_file"
        return 1
    fi
    
    # Create backup
    cp "$compose_file" "${compose_file}.bak.ratelimit"
    
    # Add rate limiting middleware to n8n service
    awk '
    /^  n8n:/ {
        print $0
        in_n8n = 1
        next
    }
    in_n8n && /traefik\.http\.routers\.n8n\.middlewares=/ {
        gsub(/middlewares=([^,"]*)/, "middlewares=\\1,rateLimit@file", $0)
        print $0
        middleware_added = 1
        next
    }
    in_n8n && /traefik\.http\.routers\.n8n\.tls\.certresolver=/ && !middleware_added {
        print $0
        print "      - \"traefik.http.routers.n8n.middlewares=rateLimit@file\""
        middleware_added = 1
        next
    }
    {
        print $0
    }
    ' "$compose_file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$compose_file"
    
    log "Updated $compose_file with rate limiting middleware"
}

# Function to set up IP whitelisting
setup_ip_whitelisting() {
    log "Setting up IP whitelisting..."
    
    # Prompt for allowed IPs
    read -p "Enter comma-separated list of allowed IPs (e.g., 192.168.1.1,10.0.0.0/24): " allowed_ips
    
    if [[ -z "$allowed_ips" ]]; then
        log "No IPs provided, using default (allow all)"
        allowed_ips="0.0.0.0/0,::/0"
    fi
    
    # Create IP whitelist configuration for Traefik
    local ip_whitelist_file="${CONFIG_DIR}/ip-whitelist.yml"
    
    cat > "$ip_whitelist_file" << EOL
http:
  middlewares:
    ipWhitelist:
      ipWhiteList:
        sourceRange:
EOL
    
    # Add each IP to the configuration
    IFS=',' read -ra IPS <<< "$allowed_ips"
    for ip in "${IPS[@]}"; do
        echo "          - \"$ip\"" >> "$ip_whitelist_file"
    done
    
    log "IP whitelist configuration created at $ip_whitelist_file"
    
    # Update docker-compose.yml to include IP whitelist middleware
    update_compose_file_ip_whitelist "../docker-compose.yml"
    
    log "IP whitelisting configured successfully"
    return 0
}

# Function to update docker-compose.yml for IP whitelisting
update_compose_file_ip_whitelist() {
    local compose_file=$1
    local temp_file="${compose_file}.tmp"
    
    log "Updating $compose_file to include IP whitelist middleware..."
    
    # Check if file exists
    if [[ ! -f "$compose_file" ]]; then
        error "Compose file not found: $compose_file"
        return 1
    fi
    
    # Create backup
    cp "$compose_file" "${compose_file}.bak.ipwhitelist"
    
    # Add IP whitelist middleware to n8n service
    awk '
    /^  n8n:/ {
        print $0
        in_n8n = 1
        next
    }
    in_n8n && /traefik\.http\.routers\.n8n\.middlewares=/ {
        gsub(/middlewares=([^,"]*)/, "middlewares=\\1,ipWhitelist@file", $0)
        print $0
        middleware_added = 1
        next
    }
    in_n8n && /traefik\.http\.routers\.n8n\.tls\.certresolver=/ && !middleware_added {
        print $0
        print "      - \"traefik.http.routers.n8n.middlewares=ipWhitelist@file\""
        middleware_added = 1
        next
    }
    {
        print $0
    }
    ' "$compose_file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$compose_file"
    
    log "Updated $compose_file with IP whitelist middleware"
}

# Function to set up monitoring stack (Prometheus + Grafana)
setup_monitoring_stack() {
    log "Setting up monitoring stack (Prometheus + Grafana)..."
    
    # Create monitoring directory
    mkdir -p "${MONITORING_DIR}/prometheus"
    mkdir -p "${MONITORING_DIR}/grafana/provisioning/dashboards"
    mkdir -p "${MONITORING_DIR}/grafana/provisioning/datasources"
    
    # Create Prometheus configuration
    local prometheus_config="${MONITORING_DIR}/prometheus/prometheus.yml"
    
    cat > "$prometheus_config" << EOL
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'docker'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOL
    
    log "Prometheus configuration created at $prometheus_config"
    
    # Create Grafana datasource configuration
    local grafana_datasource="${MONITORING_DIR}/grafana/provisioning/datasources/prometheus.yml"
    
    cat > "$grafana_datasource" << EOL
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOL
    
    log "Grafana datasource configuration created at $grafana_datasource"
    
    # Create monitoring stack docker-compose file
    create_monitoring_compose_file
    
    log "Monitoring stack setup completed"
    return 0
}

# Function to create monitoring stack docker-compose file
create_monitoring_compose_file() {
    local compose_file="../monitoring-stack.yml"
    
    cat > "$compose_file" << EOL
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: n8n-prometheus
    restart: unless-stopped
    volumes:
      - ${MONITORING_DIR}/prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"
    networks:
      - n8n-network

  grafana:
    image: grafana/grafana:latest
    container_name: n8n-grafana
    restart: unless-stopped
    volumes:
      - ${MONITORING_DIR}/grafana:/etc/grafana
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "3000:3000"
    networks:
      - n8n-network
    depends_on:
      - prometheus

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: n8n-cadvisor
    restart: unless-stopped
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"
    networks:
      - n8n-network

  node-exporter:
    image: prom/node-exporter:latest
    container_name: n8n-node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    networks:
      - n8n-network

volumes:
  prometheus_data:
  grafana_data:

networks:
  n8n-network:
    external: true
EOL
    
    log "Monitoring stack docker-compose file created at $compose_file"
}

# Function to implement all production improvements
implement_production_improvements() {
    log "Implementing production-specific improvements..."
    
    # Create necessary directories
    mkdir -p "$PRODUCTION_DIR"
    mkdir -p "$CONFIG_DIR"
    
    # Set up advanced health checks
    setup_advanced_health_checks
    
    # Set up rate limiting
    setup_rate_limiting
    
    # Set up IP whitelisting
    setup_ip_whitelisting
    
    # Set up monitoring stack
    setup_monitoring_stack
    
    log "Production improvements implemented successfully"
}

# Main execution
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Implement production-specific improvements for n8n deployment"
    echo ""
    echo "Options:"
    echo "  --health-checks-only    Only set up advanced health checks"
    echo "  --rate-limit-only       Only set up rate limiting"
    echo "  --ip-whitelist-only     Only set up IP whitelisting"
    echo "  --monitoring-only       Only set up monitoring stack"
    echo "  --all                   Implement all improvements (default)"
    exit 0
fi

case "$1" in
    --health-checks-only)
        setup_advanced_health_checks
        ;;
    --rate-limit-only)
        setup_rate_limiting
        ;;
    --ip-whitelist-only)
        setup_ip_whitelisting
        ;;
    --monitoring-only)
        setup_monitoring_stack
        ;;
    *)
        implement_production_improvements
        ;;
esac

exit 0