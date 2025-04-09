#!/bin/bash
source "$(dirname "$0")/common.sh"

# Default values
CI_MODE=false
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-local}
INTERACTIVE=true
ACTUAL_DEPLOYMENT_TYPE=""

# Detect actual deployment type from .env file
detect_deployment_type() {
    if [[ ! -f ".env" ]]; then
        ACTUAL_DEPLOYMENT_TYPE="unknown"
        return
    fi
    
    # Check for S3 variables
    if grep -q "^AWS_ACCESS_KEY_ID=" .env && grep -q "^S3_BUCKET_NAME=" .env; then
        # Check for Traefik variables
        if grep -q "^DOMAIN_NAME=" .env && grep -q "^ACME_EMAIL=" .env; then
            ACTUAL_DEPLOYMENT_TYPE="production"
        else
            ACTUAL_DEPLOYMENT_TYPE="s3"
        fi
    # Check for Traefik variables only
    elif grep -q "^DOMAIN_NAME=" .env && grep -q "^ACME_EMAIL=" .env; then
        ACTUAL_DEPLOYMENT_TYPE="traefik"
    else
        ACTUAL_DEPLOYMENT_TYPE="local"
    fi
}

# Display menu for deployment type selection
display_menu() {
    # Detect actual deployment type
    detect_deployment_type
    
    echo -e "\n${GREEN}=== N8N Deployment Verification ===${NC}"
    echo -e "\n${BLUE}Detected deployment type: ${ACTUAL_DEPLOYMENT_TYPE}${NC}"
    echo -e "\nSelect deployment type to verify:"
    echo "1) Local deployment"
    echo "2) S3 deployment"
    echo "3) Traefik deployment"
    echo "4) Production deployment"
    echo "5) Use detected deployment type (${ACTUAL_DEPLOYMENT_TYPE})"
    echo -e "\nOther options:"
    echo "c) Run in CI mode (skip container, volume, network, and directory checks)"
    echo "q) Quit"
    echo -ne "\nEnter your choice [1-5, c, q]: "
    read -r choice
    
    local selected_type=""
    
    case "$choice" in
        1)
            selected_type="local"
            ;;
        2)
            selected_type="s3"
            ;;
        3)
            selected_type="traefik"
            ;;
        4)
            selected_type="production"
            ;;
        5)
            selected_type="${ACTUAL_DEPLOYMENT_TYPE}"
            ;;
        c|C)
            CI_MODE=true
            return
            ;;
        q|Q)
            echo -e "\n${GREEN}Exiting verification script.${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${YELLOW}Invalid choice. Using detected deployment type: ${ACTUAL_DEPLOYMENT_TYPE}${NC}"
            selected_type="${ACTUAL_DEPLOYMENT_TYPE}"
            sleep 2
            ;;
    esac
    
    # Warn if selected type doesn't match detected type
    if [[ "$selected_type" != "$ACTUAL_DEPLOYMENT_TYPE" && "$ACTUAL_DEPLOYMENT_TYPE" != "unknown" ]]; then
        echo -e "\n${YELLOW}WARNING: Selected deployment type (${selected_type}) doesn't match detected type (${ACTUAL_DEPLOYMENT_TYPE})${NC}"
        echo -e "This may result in verification errors if you're checking for components that aren't part of your actual deployment."
        echo -ne "\nContinue with selected type? [y/N]: "
        read -r confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Returning to menu..."
            sleep 1
            display_menu
            return
        fi
    fi
    
    DEPLOYMENT_TYPE="$selected_type"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ci)
                CI_MODE=true
                shift
                ;;
            --deployment-type)
                DEPLOYMENT_TYPE="$2"
                INTERACTIVE=false
                shift 2
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Verify Docker containers
verify_containers() {
    log "Verifying Docker containers..."
    local failed=0
    
    # Check if Docker is running
    if ! command_exists docker || ! docker info &>/dev/null; then
        error "Docker is not running or not installed"
        return 1
    fi
    
    # Define expected containers based on deployment type
    local expected_containers=(
        "n8n-postgres:postgres:16-alpine"
        "n8n:n8nio/n8n:latest"
        "n8n-qdrant:qdrant/qdrant"
    )
    
    # Add backup-scheduler for s3 and production deployments
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        expected_containers+=("n8n-backup-scheduler:amazon/aws-cli:latest")
    fi
    
    # Add traefik for traefik and production deployments
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        expected_containers+=("n8n-traefik:traefik:v2.9")
    fi
    
    # Check each expected container
    for container_info in "${expected_containers[@]}"; do
        IFS=':' read -r container_name image_name image_tag <<< "$container_info"
        
        # Check if container exists and is running
        if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            error "Container ${container_name} is not running"
            failed=1
            continue
        fi
        
        # Check container image
        local actual_image=$(docker inspect --format '{{.Config.Image}}' "${container_name}")
        if [[ "$actual_image" != "${image_name}:${image_tag}" && "$actual_image" != "${image_name}" ]]; then
            error "Container ${container_name} is using incorrect image: ${actual_image}, expected: ${image_name}:${image_tag}"
            failed=1
        else
            log "✓ Container ${container_name} is running with correct image"
        fi
        
        # Check container health if available
        if docker inspect --format '{{.State.Health.Status}}' "${container_name}" 2>/dev/null | grep -q "healthy"; then
            log "✓ Container ${container_name} is healthy"
        elif docker inspect --format '{{.State.Status}}' "${container_name}" | grep -q "running"; then
            log "✓ Container ${container_name} is running (no health check available)"
        else
            error "Container ${container_name} is not in a healthy state"
            failed=1
        fi
    done
    
    return $failed
}

# Verify Docker volumes
verify_volumes() {
    log "Verifying Docker volumes..."
    local failed=0
    
    # Check if containers have mounted volumes
    log "Checking container volume mounts..."
    
    # Check n8n container volumes
    if docker inspect n8n --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -q "/opt/n8n-data/n8n"; then
        log "✓ n8n container has /opt/n8n-data/n8n mounted"
    else
        error "n8n container does not have /opt/n8n-data/n8n mounted"
        failed=1
    fi
    
    # Check postgres container volumes
    if docker inspect n8n-postgres --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -q "/opt/n8n-data/postgres"; then
        log "✓ postgres container has /opt/n8n-data/postgres mounted"
    else
        error "postgres container does not have /opt/n8n-data/postgres mounted"
        failed=1
    fi
    
    # Check qdrant container volumes
    if docker inspect n8n-qdrant --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -q "/opt/n8n-data/qdrant"; then
        log "✓ qdrant container has /opt/n8n-data/qdrant mounted"
    else
        error "qdrant container does not have /opt/n8n-data/qdrant mounted"
        failed=1
    fi
    
    # Check traefik container volumes if applicable
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if docker inspect n8n-traefik --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -q "/opt/n8n-data/traefik"; then
            log "✓ traefik container has /opt/n8n-data/traefik mounted"
        else
            error "traefik container does not have /opt/n8n-data/traefik mounted"
            failed=1
        fi
    fi
    
    return $failed
}

# Verify Docker networks
verify_networks() {
    log "Verifying Docker networks..."
    local failed=0
    
    # Check if containers are connected to networks
    log "Checking container network connectivity..."
    
    # Check if n8n container is connected to any network
    if docker inspect n8n --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' 2>/dev/null | grep -q .; then
        log "✓ n8n container is connected to a network"
    else
        error "n8n container is not connected to any network"
        failed=1
    fi
    
    # Check if postgres container is connected to any network
    if docker inspect n8n-postgres --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' 2>/dev/null | grep -q .; then
        log "✓ postgres container is connected to a network"
    else
        error "postgres container is not connected to any network"
        failed=1
    fi
    
    # Check if qdrant container is connected to any network
    if docker inspect n8n-qdrant --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' 2>/dev/null | grep -q .; then
        log "✓ qdrant container is connected to a network"
    else
        error "qdrant container is not connected to any network"
        failed=1
    fi
    
    # Check if traefik container is connected to any network if applicable
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if docker inspect n8n-traefik --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' 2>/dev/null | grep -q .; then
            log "✓ traefik container is connected to a network"
        else
            error "traefik container is not connected to any network"
            failed=1
        fi
    fi
    
    return $failed
}

# Verify directories and permissions
verify_directories() {
    log "Verifying directories and permissions..."
    local failed=0
    
    # Define expected directories - with more flexible permissions
    local expected_dirs=(
        "/opt/n8n-data/n8n:::"
        "/opt/n8n-data/postgres:::"
        "/opt/n8n-data/qdrant:::"
        "/opt/n8n-data/shared:::"
        "/opt/n8n-data/postgres-backup:::"
        "/opt/n8n-data/n8n-backup:::"
    )
    
    # Add traefik directory for traefik and production deployments
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        expected_dirs+=("/opt/n8n-data/traefik:::")
    fi
    
    # Check each expected directory
    for dir_info in "${expected_dirs[@]}"; do
        IFS=':' read -r dir_path expected_uid expected_gid expected_perms <<< "$dir_info"
        
        if [[ ! -d "$dir_path" ]]; then
            error "Directory ${dir_path} does not exist"
            failed=1
            continue
        else
            log "✓ Directory ${dir_path} exists"
        fi
        
        # Log directory ownership and permissions for informational purposes
        if [[ "$CI_MODE" == "false" ]]; then
            local actual_uid=$(stat -c '%u' "$dir_path")
            local actual_gid=$(stat -c '%g' "$dir_path")
            local actual_perms=$(stat -c '%a' "$dir_path")
            
            log "Directory ${dir_path} has ownership ${actual_uid}:${actual_gid} and permissions ${actual_perms}"
            
            # Only check specific values if they were provided
            if [[ -n "$expected_uid" && -n "$expected_gid" ]]; then
                if [[ "$actual_uid" != "$expected_uid" || "$actual_gid" != "$expected_gid" ]]; then
                    warn "Directory ${dir_path} has ownership ${actual_uid}:${actual_gid}, different from expected ${expected_uid}:${expected_gid}"
                else
                    log "✓ Directory ${dir_path} has correct ownership"
                fi
            fi
            
            if [[ -n "$expected_perms" ]]; then
                if [[ "$actual_perms" != "$expected_perms" ]]; then
                    warn "Directory ${dir_path} has permissions ${actual_perms}, different from expected ${expected_perms}"
                else
                    log "✓ Directory ${dir_path} has correct permissions"
                fi
            fi
        fi
    done
    
    return $failed
}

# Verify environment variables
verify_environment() {
    log "Verifying environment variables..."
    local failed=0
    
    # Check if .env file exists
    if [[ ! -f ".env" ]]; then
        error ".env file does not exist"
        return 1
    fi
    
    # Define required environment variables based on deployment type
    local required_vars=(
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "POSTGRES_DB"
        "N8N_ENCRYPTION_KEY"
        "N8N_USER_MANAGEMENT_JWT_SECRET"
    )
    
    # Add S3 variables for s3 and production deployments
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        required_vars+=(
            "AWS_ACCESS_KEY_ID"
            "AWS_SECRET_ACCESS_KEY"
            "AWS_DEFAULT_REGION"
            "S3_BUCKET_NAME"
        )
    fi
    
    # Add Traefik variables for traefik and production deployments
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        required_vars+=(
            "DOMAIN_NAME"
            "ACME_EMAIL"
            "TRAEFIK_DASHBOARD_AUTH"
        )
    fi
    
    # Read .env file without sourcing it to avoid issues with special characters
    for var in "${required_vars[@]}"; do
        # Use grep to check if variable exists in .env file
        if ! grep -q "^${var}=" .env; then
            error "Environment variable ${var} is not set in .env file"
            failed=1
        else
            log "✓ Environment variable ${var} is set"
        fi
    done
    
    return $failed
}

# Run all verification checks
run_verification() {
    local failed=0
    local env_failed=0
    local containers_failed=0
    local volumes_failed=0
    local networks_failed=0
    local dirs_failed=0
    
    log "Starting comprehensive deployment verification for ${DEPLOYMENT_TYPE} deployment..."
    
    # Always verify environment variables
    verify_environment
    env_failed=$?
    [[ $env_failed -ne 0 ]] && failed=1
    
    # Skip container, volume, network, and directory checks in CI mode
    if [[ "$CI_MODE" == "false" ]]; then
        verify_containers
        containers_failed=$?
        [[ $containers_failed -ne 0 ]] && failed=1
        
        verify_volumes
        volumes_failed=$?
        [[ $volumes_failed -ne 0 ]] && failed=1
        
        verify_networks
        networks_failed=$?
        [[ $networks_failed -ne 0 ]] && failed=1
        
        verify_directories
        dirs_failed=$?
        [[ $dirs_failed -ne 0 ]] && failed=1
    else
        log "Running in CI mode, skipping container, volume, network, and directory checks"
    fi
    
    # Display summary
    echo -e "\n${GREEN}=== Verification Summary ===${NC}"
    if [[ $env_failed -eq 0 ]]; then
        echo -e "${GREEN}✓ Environment variables: PASSED${NC}"
    else
        echo -e "${RED}✗ Environment variables: FAILED${NC}"
    fi
    
    if [[ "$CI_MODE" == "false" ]]; then
        if [[ $containers_failed -eq 0 ]]; then
            echo -e "${GREEN}✓ Docker containers: PASSED${NC}"
        else
            echo -e "${RED}✗ Docker containers: FAILED${NC}"
        fi
        
        if [[ $volumes_failed -eq 0 ]]; then
            echo -e "${GREEN}✓ Docker volumes: PASSED${NC}"
        else
            echo -e "${RED}✗ Docker volumes: FAILED${NC}"
        fi
        
        if [[ $networks_failed -eq 0 ]]; then
            echo -e "${GREEN}✓ Docker networks: PASSED${NC}"
        else
            echo -e "${RED}✗ Docker networks: FAILED${NC}"
        fi
        
        if [[ $dirs_failed -eq 0 ]]; then
            echo -e "${GREEN}✓ Directories and permissions: PASSED${NC}"
        else
            echo -e "${RED}✗ Directories and permissions: FAILED${NC}"
        fi
    fi
    
    return $failed
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    
    # Detect actual deployment type
    detect_deployment_type
    
    # Show interactive menu if not in non-interactive mode
    if [[ "$INTERACTIVE" == "true" ]]; then
        display_menu
    elif [[ -z "$DEPLOYMENT_TYPE" || "$DEPLOYMENT_TYPE" == "local" ]]; then
        # If no deployment type specified via args, use the detected one
        DEPLOYMENT_TYPE="$ACTUAL_DEPLOYMENT_TYPE"
    fi
    
    echo -e "\n${GREEN}Starting verification for ${DEPLOYMENT_TYPE} deployment...${NC}"
    if [[ "$DEPLOYMENT_TYPE" != "$ACTUAL_DEPLOYMENT_TYPE" && "$ACTUAL_DEPLOYMENT_TYPE" != "unknown" ]]; then
        echo -e "${YELLOW}Note: Verifying as ${DEPLOYMENT_TYPE} but detected deployment type is ${ACTUAL_DEPLOYMENT_TYPE}${NC}"
    fi
    
    if [[ "$CI_MODE" == "true" ]]; then
        echo -e "${YELLOW}Running in CI mode (skipping container, volume, network, and directory checks)${NC}"
    fi
    sleep 1
    
    run_verification
    if [ $? -eq 0 ]; then
        log "All verification checks passed successfully!"
        exit 0
    else
        error "Some verification checks failed. Please check the logs."
        exit 1
    fi
fi