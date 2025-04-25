#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/common.sh"

# Configuration
TRAEFIK_DIR="${BASE_DIR}/traefik"

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Set up Traefik reverse proxy with HTTPS for n8n deployment"
    echo ""
    echo "Options:"
    echo "  -h, --help             Display this help message"
    echo "  -d, --domain DOMAIN    Domain name for n8n (required)"
    echo "  -e, --email EMAIL      Email for Let's Encrypt notifications (required)"
    echo "  -u, --user USERNAME    Username for Traefik dashboard (default: admin)"
    echo "  -p, --password PASS    Password for Traefik dashboard"
    echo "  --staging              Use Let's Encrypt staging server (for testing)"
    echo ""
    echo "Examples:"
    echo "  $0 --domain n8n.example.com --email admin@example.com"
    echo "  $0 --domain n8n.example.com --email admin@example.com --user admin --password secure_password"
}

# Default values
DOMAIN_NAME=""
ACME_EMAIL=""
TRAEFIK_USER="admin"
TRAEFIK_PASSWORD=""
USE_STAGING=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        -e|--email)
            ACME_EMAIL="$2"
            shift 2
            ;;
        -u|--user)
            TRAEFIK_USER="$2"
            shift 2
            ;;
        -p|--password)
            TRAEFIK_PASSWORD="$2"
            shift 2
            ;;
        --staging)
            USE_STAGING=true
            shift
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

# Validate required parameters
if [[ -z "$DOMAIN_NAME" ]]; then
    error "Domain name is required. Use --domain to specify."
    show_help
    exit 1
fi

if [[ -z "$ACME_EMAIL" ]]; then
    error "Email is required for Let's Encrypt. Use --email to specify."
    show_help
    exit 1
fi

# Generate password if not provided
if [[ -z "$TRAEFIK_PASSWORD" ]]; then
    log "No password provided. Generating a secure password..."
    TRAEFIK_PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' < /dev/urandom | head -c 16)
    log "Generated password: $TRAEFIK_PASSWORD"
    log "Please save this password for future access to the Traefik dashboard."
fi

# Create Traefik directory
log "Creating Traefik directory..."
mkdir -p "$TRAEFIK_DIR"
chmod 750 "$TRAEFIK_DIR"

# Generate htpasswd entry
log "Generating htpasswd entry..."
if command_exists htpasswd; then
    HTPASSWD_ENTRY=$(htpasswd -nb "$TRAEFIK_USER" "$TRAEFIK_PASSWORD")
elif command_exists docker; then
    HTPASSWD_ENTRY=$(docker run --rm httpd:alpine htpasswd -nb "$TRAEFIK_USER" "$TRAEFIK_PASSWORD")
else
    error "Neither htpasswd nor podman is available. Cannot generate password hash."
    exit 1
fi

# Create .env file
log "Creating Traefik environment file..."
cat > ".env" << EOL
# Traefik Configuration for n8n Deployment

# Domain Configuration
DOMAIN_NAME=$DOMAIN_NAME

# Email for Let's Encrypt notifications
ACME_EMAIL=$ACME_EMAIL

# Traefik Dashboard Authentication
TRAEFIK_DASHBOARD_AUTH=$HTPASSWD_ENTRY
EOL

# Add staging server if requested
if [[ "$USE_STAGING" == "true" ]]; then
    log "Using Let's Encrypt staging server for testing..."
    echo "" >> ".env"
    echo "# Using staging server for testing" >> ".env"
    echo "TRAEFIK_ACME_CASERVER=https://acme-staging-v02.api.letsencrypt.org/directory" >> ".env"
fi

log "Traefik environment file created."

# Update n8n compose files to work with Traefik
update_compose_file() {
    local compose_file=$1
    local temp_file="${compose_file}.tmp"
    
    log "Updating $compose_file for Traefik integration..."
    
    # Check if file exists
    if [[ ! -f "$compose_file" ]]; then
        error "Compose file not found: $compose_file"
        return 1
    fi
    
    # Create backup
    cp "$compose_file" "${compose_file}.bak"
    
    # Add Traefik labels to n8n service
    awk '
    /^  n8n:/ {
        print $0
        in_n8n = 1
        next
    }
    in_n8n && /^    labels:/ {
        has_labels = 1
        print $0
        next
    }
    in_n8n && !has_labels && /^    [a-z]/ {
        print "    labels:"
        print "      - \"traefik.enable=true\""
        print "      - \"traefik.http.routers.n8n.rule=Host(`${DOMAIN_NAME}`)\""
        print "      - \"traefik.http.routers.n8n.entrypoints=websecure\""
        print "      - \"traefik.http.routers.n8n.tls.certresolver=letsencrypt\""
        print "      - \"traefik.http.services.n8n.loadbalancer.server.port=5678\""
        has_labels = 1
        print $0
        next
    }
    in_n8n && has_labels && /^      -/ {
        print $0
        next
    }
    in_n8n && has_labels && /^    [a-z]/ {
        has_labels = 0
        in_n8n = 0
        print $0
        next
    }
    /^  [a-z]/ {
        in_n8n = 0
        has_labels = 0
        print $0
        next
    }
    {
        print $0
    }
    ' "$compose_file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$compose_file"
    
    log "Updated $compose_file with Traefik integration"
}

# Update compose files
update_compose_file "../local/docker-compose.yml"
update_compose_file "../s3/docker-compose.yml"

log "Setup complete! You can now start Traefik with:"
log "  docker compose up -d"
log ""
log "Traefik dashboard will be available at: https://traefik.${DOMAIN_NAME}"
log "n8n will be available at: https://${DOMAIN_NAME}"
log ""
log "Username for Traefik dashboard: $TRAEFIK_USER"
log "Password for Traefik dashboard: $TRAEFIK_PASSWORD"
