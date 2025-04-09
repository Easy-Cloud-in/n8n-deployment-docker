#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Configure firewall rules for n8n deployment"
    echo ""
    echo "Options:"
    echo "  -h, --help             Display this help message"
    echo "  --allow-ssh            Allow SSH access (default: enabled)"
    echo "  --no-ssh               Disable SSH access"
    echo "  --ssh-port PORT        Specify custom SSH port (default: 22)"
    echo "  --allow-http           Allow HTTP access (default: enabled)"
    echo "  --no-http              Disable HTTP access"
    echo "  --allow-https          Allow HTTPS access (default: enabled)"
    echo "  --no-https             Disable HTTPS access"
    echo "  --allow-n8n-direct     Allow direct access to n8n port (default: disabled)"
    echo "  --allow-qdrant-direct  Allow direct access to Qdrant port (default: disabled)"
    echo "  --custom-allow PORT    Allow additional custom port"
    echo ""
    echo "Examples:"
    echo "  $0                     Configure with default settings"
    echo "  $0 --no-ssh --no-http  Configure without SSH and HTTP access"
}

# Default settings
ALLOW_SSH=true
SSH_PORT=22
ALLOW_HTTP=true
ALLOW_HTTPS=true
ALLOW_N8N_DIRECT=false
ALLOW_QDRANT_DIRECT=false
CUSTOM_PORTS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --allow-ssh)
            ALLOW_SSH=true
            shift
            ;;
        --no-ssh)
            ALLOW_SSH=false
            shift
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --allow-http)
            ALLOW_HTTP=true
            shift
            ;;
        --no-http)
            ALLOW_HTTP=false
            shift
            ;;
        --allow-https)
            ALLOW_HTTPS=true
            shift
            ;;
        --no-https)
            ALLOW_HTTPS=false
            shift
            ;;
        --allow-n8n-direct)
            ALLOW_N8N_DIRECT=true
            shift
            ;;
        --allow-qdrant-direct)
            ALLOW_QDRANT_DIRECT=true
            shift
            ;;
        --custom-allow)
            CUSTOM_PORTS+=("$2")
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root"
    exit 1
fi

# Configure UFW firewall
configure_ufw() {
    log "Configuring UFW firewall..."
    
    # Reset UFW to default
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH if enabled
    if [[ "$ALLOW_SSH" == "true" ]]; then
        if [[ "$SSH_PORT" == "22" ]]; then
            log "Allowing SSH on default port 22"
            ufw allow ssh
        else
            log "Allowing SSH on custom port $SSH_PORT"
            ufw allow "$SSH_PORT/tcp"
        fi
    fi
    
    # Allow HTTP if enabled
    if [[ "$ALLOW_HTTP" == "true" ]]; then
        log "Allowing HTTP (port 80)"
        ufw allow 80/tcp
    fi
    
    # Allow HTTPS if enabled
    if [[ "$ALLOW_HTTPS" == "true" ]]; then
        log "Allowing HTTPS (port 443)"
        ufw allow 443/tcp
    fi
    
    # Allow direct n8n access if enabled
    if [[ "$ALLOW_N8N_DIRECT" == "true" ]]; then
        log "Allowing direct access to n8n (port 5678)"
        ufw allow 5678/tcp
    fi
    
    # Allow direct Qdrant access if enabled
    if [[ "$ALLOW_QDRANT_DIRECT" == "true" ]]; then
        log "Allowing direct access to Qdrant (port 6333)"
        ufw allow 6333/tcp
    fi
    
    # Allow custom ports if specified
    for port in "${CUSTOM_PORTS[@]}"; do
        log "Allowing custom port: $port"
        ufw allow "$port/tcp"
    done
    
    # Enable UFW
    log "Enabling UFW firewall..."
    ufw --force enable
    
    # Show status
    ufw status verbose
    
    log "UFW firewall configured successfully"
}

# Configure firewalld
configure_firewalld() {
    log "Configuring firewalld..."
    
    # Ensure firewalld is running
    if ! systemctl is-active firewalld &>/dev/null; then
        log "Starting firewalld service..."
        systemctl start firewalld
    fi
    
    # Allow SSH if enabled
    if [[ "$ALLOW_SSH" == "true" ]]; then
        if [[ "$SSH_PORT" == "22" ]]; then
            log "Allowing SSH on default port 22"
            firewall-cmd --permanent --add-service=ssh
        else
            log "Allowing SSH on custom port $SSH_PORT"
            firewall-cmd --permanent --add-port="$SSH_PORT/tcp"
        fi
    fi
    
    # Allow HTTP if enabled
    if [[ "$ALLOW_HTTP" == "true" ]]; then
        log "Allowing HTTP (port 80)"
        firewall-cmd --permanent --add-service=http
    fi
    
    # Allow HTTPS if enabled
    if [[ "$ALLOW_HTTPS" == "true" ]]; then
        log "Allowing HTTPS (port 443)"
        firewall-cmd --permanent --add-service=https
    fi
    
    # Allow direct n8n access if enabled
    if [[ "$ALLOW_N8N_DIRECT" == "true" ]]; then
        log "Allowing direct access to n8n (port 5678)"
        firewall-cmd --permanent --add-port=5678/tcp
    fi
    
    # Allow direct Qdrant access if enabled
    if [[ "$ALLOW_QDRANT_DIRECT" == "true" ]]; then
        log "Allowing direct access to Qdrant (port 6333)"
        firewall-cmd --permanent --add-port=6333/tcp
    fi
    
    # Allow custom ports if specified
    for port in "${CUSTOM_PORTS[@]}"; do
        log "Allowing custom port: $port"
        firewall-cmd --permanent --add-port="$port/tcp"
    done
    
    # Apply changes
    firewall-cmd --reload
    
    # Show status
    firewall-cmd --list-all
    
    log "firewalld configured successfully"
}

# Detect and configure firewall
if command_exists ufw; then
    log "UFW detected, configuring..."
    configure_ufw
elif command_exists firewall-cmd; then
    log "firewalld detected, configuring..."
    configure_firewalld
else
    error "No supported firewall (ufw or firewalld) found"
    log "Please install either ufw or firewalld and try again"
    exit 1
fi

log "Firewall configuration completed"