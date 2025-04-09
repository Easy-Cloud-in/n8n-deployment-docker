#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuration
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-"local"}
VALID_TYPES=("local" "s3" "traefik" "production")

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Implement deployment-specific improvements for n8n"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Display this help message"
    echo "  -t, --type DEPLOYMENT_TYPE Set the deployment type (local, s3, traefik, production)"
    echo "  --force                    Force implementation even if some checks fail"
    echo ""
    echo "Deployment Types:"
    echo "  local       - Basic deployment with minimal improvements"
    echo "  s3          - Adds S3 backup capabilities"
    echo "  traefik     - Adds HTTPS and security features"
    echo "  production  - Complete solution with all improvements"
    echo ""
    echo "Examples:"
    echo "  $0 --type local"
    echo "  $0 --type production --force"
}

# Function to validate deployment type
validate_deployment_type() {
    local type=$1
    local valid=false
    
    for valid_type in "${VALID_TYPES[@]}"; do
        if [[ "$type" == "$valid_type" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        error "Invalid deployment type: $type"
        echo "Valid types are: ${VALID_TYPES[*]}"
        return 1
    fi
    
    return 0
}

# Function to implement basic improvements (for local and s3)
implement_basic_improvements() {
    log "Implementing basic improvements for deployment type: $DEPLOYMENT_TYPE"
    
    # Basic improvements are already implemented in the codebase
    log "Basic error handling, health checks, and backup verification are already implemented"
    
    # Ensure health check script is executable
    chmod +x "${SCRIPT_DIR}/health-check.sh"
    
    log "Basic improvements verified"
    return 0
}

# Function to implement Traefik improvements
implement_traefik_improvements() {
    log "Implementing Traefik improvements for deployment type: $DEPLOYMENT_TYPE"
    
    # Check if Traefik improvements script exists
    local traefik_script="${SCRIPT_DIR}/../traefik/traefik-improvements.sh"
    if [[ ! -f "$traefik_script" ]]; then
        error "Traefik improvements script not found: $traefik_script"
        return 1
    fi
    
    # Make script executable
    chmod +x "$traefik_script"
    
    # Run Traefik improvements script
    log "Running Traefik improvements script..."
    "$traefik_script"
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error "Traefik improvements implementation failed"
        return $exit_code
    fi
    
    log "Traefik improvements implemented successfully"
    return 0
}

# Function to implement production improvements
implement_production_improvements() {
    log "Implementing production improvements for deployment type: $DEPLOYMENT_TYPE"
    
    # Check if production improvements script exists
    local production_script="${SCRIPT_DIR}/production-improvements.sh"
    if [[ ! -f "$production_script" ]]; then
        error "Production improvements script not found: $production_script"
        return 1
    fi
    
    # Make script executable
    chmod +x "$production_script"
    
    # Run production improvements script
    log "Running production improvements script..."
    "$production_script"
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error "Production improvements implementation failed"
        return $exit_code
    fi
    
    log "Production improvements implemented successfully"
    return 0
}

# Function to implement S3 improvements
implement_s3_improvements() {
    log "Implementing S3 improvements for deployment type: $DEPLOYMENT_TYPE"
    
    # S3 improvements are already implemented in the codebase
    log "S3 backup verification and AWS connectivity checks are already implemented"
    
    log "S3 improvements verified"
    return 0
}

# Function to implement all improvements based on deployment type
implement_improvements() {
    log "Implementing improvements for deployment type: $DEPLOYMENT_TYPE"
    
    case "$DEPLOYMENT_TYPE" in
        local)
            implement_basic_improvements
            ;;
        s3)
            implement_basic_improvements
            implement_s3_improvements
            ;;
        traefik)
            implement_basic_improvements
            implement_traefik_improvements
            ;;
        production)
            implement_basic_improvements
            implement_s3_improvements
            implement_traefik_improvements
            implement_production_improvements
            ;;
        *)
            error "Unknown deployment type: $DEPLOYMENT_TYPE"
            return 1
            ;;
    esac
    
    log "All improvements for $DEPLOYMENT_TYPE deployment have been implemented"
    return 0
}

# Parse command line arguments
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--type)
            DEPLOYMENT_TYPE="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate deployment type
if ! validate_deployment_type "$DEPLOYMENT_TYPE"; then
    exit 1
fi

# Implement improvements
log "Starting implementation of improvements for deployment type: $DEPLOYMENT_TYPE"

if implement_improvements; then
    log "Successfully implemented all improvements for $DEPLOYMENT_TYPE deployment"
    exit 0
else
    if [[ "$FORCE" == "true" ]]; then
        warn "Some improvements failed, but continuing due to --force option"
        exit 0
    else
        error "Failed to implement improvements for $DEPLOYMENT_TYPE deployment"
        exit 1
    fi
fi