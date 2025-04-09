#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/common.sh"

# Configuration
TRAEFIK_DIR="/opt/n8n-data/traefik"
DOMAIN_NAME=${DOMAIN_NAME:-"localhost"}

# Function to check SSL certificate expiration
check_ssl_cert() {
    local domain="$DOMAIN_NAME"
    log "Checking SSL certificate expiration for $domain..."
    
    # Get certificate expiration date
    local expiry=$(curl -vI "https://${domain}" 2>&1 | grep "expire date" | cut -d: -f2-)
    
    if [[ -z "$expiry" ]]; then
        error "Failed to retrieve SSL certificate expiration date for $domain"
        return 1
    fi
    
    log "Certificate expires on: $expiry"
    
    # Alert if less than 30 days until expiry
    if [[ $(date -d "$expiry" +%s) -lt $(date -d "+30 days" +%s) ]]; then
        warn "SSL certificate for $domain will expire in less than 30 days!"
        return 1
    fi
    
    log "SSL certificate is valid for more than 30 days"
    return 0
}

# Function to configure security headers for Traefik
configure_security_headers() {
    log "Configuring security headers for Traefik..."
    
    # Create middleware configuration file
    local middleware_file="${TRAEFIK_DIR}/security-headers.yml"
    
    cat > "$middleware_file" << EOL
http:
  middlewares:
    securityHeaders:
      headers:
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        customFrameOptionsValue: "SAMEORIGIN"
        customResponseHeaders:
          X-Content-Type-Options: "nosniff"
          X-Frame-Options: "SAMEORIGIN"
          X-XSS-Protection: "1; mode=block"
          Referrer-Policy: "strict-origin-when-cross-origin"
          Permissions-Policy: "camera=(), microphone=(), geolocation=(), interest-cohort=()"
EOL

    log "Security headers configuration created at $middleware_file"
    
    # Update Traefik labels in docker-compose.yml to use the middleware
    update_compose_file "../docker-compose.yml"
    
    log "Security headers configured successfully"
    return 0
}

# Function to update docker-compose.yml to include security headers middleware
update_compose_file() {
    local compose_file=$1
    local temp_file="${compose_file}.tmp"
    
    log "Updating $compose_file to include security headers middleware..."
    
    # Check if file exists
    if [[ ! -f "$compose_file" ]]; then
        error "Compose file not found: $compose_file"
        return 1
    fi
    
    # Create backup
    cp "$compose_file" "${compose_file}.bak"
    
    # Add security headers middleware to n8n service
    awk '
    /^  n8n:/ {
        print $0
        in_n8n = 1
        next
    }
    in_n8n && /traefik\.http\.routers\.n8n\.tls\.certresolver=letsencrypt/ {
        print $0
        print "      - \"traefik.http.routers.n8n.middlewares=securityHeaders@file\""
        next
    }
    {
        print $0
    }
    ' "$compose_file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$compose_file"
    
    log "Updated $compose_file with security headers middleware"
}

# Function to implement all Traefik improvements
implement_traefik_improvements() {
    log "Implementing Traefik-specific improvements..."
    
    # Create Traefik directory if it doesn't exist
    if [[ ! -d "$TRAEFIK_DIR" ]]; then
        mkdir -p "$TRAEFIK_DIR"
        chmod 750 "$TRAEFIK_DIR"
    fi
    
    # Configure security headers
    configure_security_headers
    
    # Check SSL certificate (if domain is configured)
    if [[ "$DOMAIN_NAME" != "localhost" ]]; then
        check_ssl_cert
    else
        log "Skipping SSL certificate check for localhost"
    fi
    
    log "Traefik improvements implemented successfully"
}

# Main execution
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [--check-ssl-only]"
    echo "  --check-ssl-only: Only check SSL certificate expiration"
    exit 0
fi

if [[ "$1" == "--check-ssl-only" ]]; then
    check_ssl_cert
else
    implement_traefik_improvements
fi

exit 0