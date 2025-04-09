#!/bin/bash

# n8n Docker Deployment - Unified Setup Script
# This script provides a simple, interactive way to deploy n8n with various options

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

# Configuration
BASE_DIR="/opt/n8n-data"
COMMON_ENV_FILE="${SCRIPT_DIR}/.env"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
CONFIG_FILE="${SCRIPT_DIR}/.env"
CONFIG_EXAMPLE="${SCRIPT_DIR}/.env.example"

# Function to load configuration from .env file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from $CONFIG_FILE"
        # Source the .env file to load variables
        source "$CONFIG_FILE"
        return 0
    else
        log "No configuration file found. Using default values."
        return 1
    fi
}

# Function to save configuration to .env file
save_config() {
    log "Saving configuration to $CONFIG_FILE"
    
    # Create or overwrite the config file
    cat > "$CONFIG_FILE" << EOL
# n8n Docker Deployment - Configuration File
# Generated on $(date)

# Deployment Type
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE}

# Base Directory
BASE_DIR=${BASE_DIR}

# Database Configuration
POSTGRES_USER=${POSTGRES_USER:-n8n}
POSTGRES_DB=${POSTGRES_DB:-n8n}
EOL

    # Add password only if it exists
    if [[ -n "$POSTGRES_PASSWORD" ]]; then
        echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> "$CONFIG_FILE"
    fi
    
    # Add encryption keys only if they exist
    if [[ -n "$N8N_ENCRYPTION_KEY" ]]; then
        echo "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}" >> "$CONFIG_FILE"
    fi
    
    if [[ -n "$N8N_USER_MANAGEMENT_JWT_SECRET" ]]; then
        echo "N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}" >> "$CONFIG_FILE"
    fi
    
    # Add backup retention
    echo "BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}" >> "$CONFIG_FILE"
    
    # Add S3 configuration if needed
    if [[ "$DEPLOYMENT_TYPE" == "s3" ]]; then
        cat >> "$CONFIG_FILE" << EOL

# AWS S3 Configuration
S3_BUCKET_NAME=${S3_BUCKET_NAME}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION}
EOL
    fi
    
    # Add Traefik configuration if needed
    if [[ "$DEPLOYMENT_TYPE" == "traefik" ]]; then
        cat >> "$CONFIG_FILE" << EOL

# Traefik Configuration
DOMAIN_NAME=${DOMAIN_NAME}
ACME_EMAIL=${ACME_EMAIL}
EOL

        # Add Traefik user if it exists
        if [[ -n "$TRAEFIK_USER" ]]; then
            echo "TRAEFIK_USER=${TRAEFIK_USER}" >> "$CONFIG_FILE"
        fi
        
        # Add Traefik password if it exists
        if [[ -n "$TRAEFIK_PASSWORD" ]]; then
            echo "TRAEFIK_PASSWORD=${TRAEFIK_PASSWORD}" >> "$CONFIG_FILE"
        fi
    fi
    
    log "Configuration saved successfully."
}

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Set up n8n deployment with various options"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Display this help message"
    echo "  -t, --type TYPE            Deployment type: local, s3, traefik, or production (default: local)"
    echo "  -d, --domain DOMAIN        Domain name for Traefik HTTPS setup"
    echo "  -e, --email EMAIL          Email for Let's Encrypt notifications"
    echo "  --s3-bucket BUCKET         S3 bucket name for backups"
    echo "  --aws-region REGION        AWS region (default: us-east-1)"
    echo "  --aws-key KEY              AWS access key ID"
    echo "  --aws-secret SECRET        AWS secret access key"
    echo "  --no-interactive           Run in non-interactive mode"
    echo "  --force                    Skip validation checks"
    echo ""
    echo "Examples:"
    echo "  $0                         # Interactive setup with prompts"
    echo "  $0 --type local            # Basic local setup"
    echo "  $0 --type s3 --s3-bucket my-bucket --aws-key KEY --aws-secret SECRET"
    echo "  $0 --type traefik --domain n8n.example.com --email admin@example.com"
    echo "  $0 --type production --domain n8n.example.com --email admin@example.com --s3-bucket my-bucket --aws-key KEY --aws-secret SECRET"
}

# Default values
DEPLOYMENT_TYPE="local"
DOMAIN_NAME=""
ACME_EMAIL=""
S3_BUCKET_NAME=""
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
INTERACTIVE=true
FORCE=false

# Parse command line arguments
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
        -d|--domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        -e|--email)
            ACME_EMAIL="$2"
            shift 2
            ;;
        --s3-bucket)
            S3_BUCKET_NAME="$2"
            shift 2
            ;;
        --aws-region)
            AWS_REGION="$2"
            shift 2
            ;;
        --aws-key)
            AWS_ACCESS_KEY_ID="$2"
            shift 2
            ;;
        --aws-secret)
            AWS_SECRET_ACCESS_KEY="$2"
            shift 2
            ;;
        --no-interactive)
            INTERACTIVE=false
            shift
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root"
    exit 1
fi

# Validate deployment type if provided via command line
if [[ -n "$DEPLOYMENT_TYPE" && ! "$DEPLOYMENT_TYPE" =~ ^(local|s3|traefik|production)$ ]]; then
    error "Invalid deployment type: $DEPLOYMENT_TYPE. Must be one of: local, s3, traefik, production"
    exit 1
fi

# Try to load configuration from .env file at startup
load_config

# Function to display the main menu
display_main_menu() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║       n8n Docker Deployment Setup          ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "Please select an option:"
    echo ""
    echo "1) Configure Deployment Type"
    echo "2) Configure Storage Settings"
    echo "3) Configure Network Settings"
    echo "4) Review Configuration"
    echo "5) Start Deployment"
    echo "6) Help"
    echo "7) Save Configuration"
    echo "8) Load Configuration"
    echo "0) Exit"
    echo ""
    read -p "Enter your choice [0-8]: " main_choice
    
    case $main_choice in
        1) configure_deployment_type ;;
        2) configure_storage_settings ;;
        3) configure_network_settings ;;
        4) review_configuration ;;
        5) confirm_and_deploy ;;
        6) show_help_menu ;;
        7) save_configuration_menu ;;
        8) load_configuration_menu ;;
        0)
            echo "Exiting setup..."
            exit 0
            ;;
        *)
            echo "Invalid option. Press Enter to continue..."
            read
            display_main_menu
            ;;
    esac
}

# Function to handle saving configuration
save_configuration_menu() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Save Configuration               ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "This will save your current configuration to:"
    echo "$CONFIG_FILE"
    echo ""
    echo "Any existing configuration file will be overwritten."
    echo ""
    read -p "Continue with saving configuration? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Nn] ]]; then
        save_config
        echo ""
        echo "Configuration saved successfully."
    else
        echo ""
        echo "Save operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

# Function to handle loading configuration
load_configuration_menu() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Load Configuration               ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No configuration file found at:"
        echo "$CONFIG_FILE"
        echo ""
        echo "You can create a configuration file by:"
        echo "1. Copying .env.example to .env and editing it"
        echo "2. Using the 'Save Configuration' option from the main menu"
        echo ""
        echo "Press Enter to return to the main menu..."
        read
        display_main_menu
        return
    fi
    
    echo "This will load configuration from:"
    echo "$CONFIG_FILE"
    echo ""
    echo "Your current settings will be overwritten."
    echo ""
    read -p "Continue with loading configuration? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Nn] ]]; then
        load_config
        echo ""
        echo "Configuration loaded successfully."
    else
        echo ""
        echo "Load operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

# Function to configure deployment type
configure_deployment_type() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║         Configure Deployment Type          ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "Select deployment type:"
    echo ""
    echo "1) Local (simplest, data stored locally)"
    echo "   - All data stored on the local server"
    echo "   - Suitable for testing and small deployments"
    echo ""
    echo "2) S3 (backups stored in Amazon S3)"
    echo "   - Data stored locally with backups to S3"
    echo "   - Better data protection with cloud backups"
    echo ""
    echo "3) Traefik (HTTPS with Let's Encrypt)"
    echo "   - Automatic HTTPS certificate management"
    echo "   - Suitable for production deployments"
    echo ""
    echo "4) Production (HTTPS with S3 backups)"
    echo "   - Complete production-ready solution"
    echo "   - Combines HTTPS security with S3 backups"
    echo "   - Recommended for public-facing deployments"
    echo ""
    echo "0) Back to main menu"
    echo ""
    read -p "Enter your choice [0-4]: " type_choice
    
    case $type_choice in
        1)
            DEPLOYMENT_TYPE="local"
            echo "Deployment type set to: Local"
            ;;
        2)
            DEPLOYMENT_TYPE="s3"
            echo "Deployment type set to: S3"
            ;;
        3)
            DEPLOYMENT_TYPE="traefik"
            echo "Deployment type set to: Traefik"
            ;;
        4)
            DEPLOYMENT_TYPE="production"
            echo "Deployment type set to: Production (HTTPS with S3 backups)"
            ;;
        0)
            display_main_menu
            return
            ;;
        *)
            echo "Invalid option. Press Enter to continue..."
            read
            configure_deployment_type
            return
            ;;
    esac
    
    echo ""
    echo "Press Enter to continue..."
    read
    display_main_menu
}

# Function to configure storage settings
configure_storage_settings() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║         Configure Storage Settings         ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "S3 Backup Configuration:"
        echo ""
        read -p "Enter S3 bucket name for backups: " S3_BUCKET_NAME
        read -p "Enter AWS access key ID: " AWS_ACCESS_KEY_ID
        read -p "Enter AWS secret access key: " AWS_SECRET_ACCESS_KEY
        read -p "Enter AWS region (default: us-east-1): " input_region
        AWS_REGION=${input_region:-us-east-1}
        
        echo ""
        echo "S3 configuration saved."
    else
        echo "Storage settings are only applicable for S3 or Production deployment types."
        echo "Current deployment type: $DEPLOYMENT_TYPE"
        echo ""
        echo "To configure S3 storage, first select S3 or Production as your deployment type."
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
    display_main_menu
}

# Function to configure network settings
configure_network_settings() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║         Configure Network Settings         ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "Traefik HTTPS Configuration:"
        echo ""
        read -p "Enter domain name for n8n (e.g., n8n.example.com): " DOMAIN_NAME
        read -p "Enter email for Let's Encrypt notifications: " ACME_EMAIL
        
        echo ""
        echo "Traefik configuration saved."
    else
        echo "Network settings are only applicable for Traefik or Production deployment types."
        echo "Current deployment type: $DEPLOYMENT_TYPE"
        echo ""
        echo "To configure HTTPS with Traefik, first select Traefik or Production as your deployment type."
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
    display_main_menu
}

# Function to review configuration
review_configuration() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Configuration Summary            ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Configuration source: $CONFIG_FILE"
    else
        echo "Configuration source: Current session (not saved)"
    fi
    echo ""
    
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo ""
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "S3 Backup Configuration:"
        echo "- S3 Bucket: $S3_BUCKET_NAME"
        echo "- AWS Region: $AWS_REGION"
        if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
            echo "- AWS Access Key: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
        else
            echo "- AWS Access Key: Not configured"
        fi
        if [[ -n "$AWS_SECRET_ACCESS_KEY" ]]; then
            echo "- AWS Secret Key: ${AWS_SECRET_ACCESS_KEY:0:4}...${AWS_SECRET_ACCESS_KEY: -4}"
        else
            echo "- AWS Secret Key: Not configured"
        fi
        echo ""
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "Traefik HTTPS Configuration:"
        echo "- Domain Name: $DOMAIN_NAME"
        echo "- Email: $ACME_EMAIL"
        echo ""
    fi
    
    # Check for missing required configuration
    local missing_config=false
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$S3_BUCKET_NAME" || -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
            echo "⚠️  WARNING: Missing required S3 configuration"
            missing_config=true
        fi
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$DOMAIN_NAME" || -z "$ACME_EMAIL" ]]; then
            echo "⚠️  WARNING: Missing required Traefik configuration"
            missing_config=true
        fi
    fi
    
    if [[ "$missing_config" == "true" ]]; then
        echo "Please complete the configuration before deployment."
    else
        echo "✅ Configuration is complete and ready for deployment."
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
    display_main_menu
}

# Function to show help menu
show_help_menu() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║                 Help Menu                  ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "n8n Docker Deployment Setup Help"
    echo ""
    echo "This script helps you set up n8n with Docker using different deployment options:"
    echo ""
    echo "1. Local Deployment"
    echo "   - Simplest setup with data stored locally"
    echo "   - No additional configuration required"
    echo "   - Access n8n at http://localhost:5678"
    echo ""
    echo "2. S3 Deployment"
    echo "   - Includes automatic backups to Amazon S3"
    echo "   - Requires AWS credentials and S3 bucket"
    echo "   - Daily backups of n8n and database data"
    echo ""
    echo "3. Traefik Deployment"
    echo "   - Adds HTTPS support with automatic SSL certificates"
    echo "   - Requires a domain name pointing to your server"
    echo "   - Includes a Traefik dashboard for monitoring"
    echo ""
    echo "4. Production Deployment"
    echo "   - Complete production-ready solution"
    echo "   - Combines HTTPS security with S3 backups"
    echo "   - Recommended for public-facing deployments"
    echo ""
    echo "Configuration Management:"
    echo "- Save Configuration: Saves your current settings to .env file"
    echo "- Load Configuration: Loads settings from an existing .env file"
    echo "- You can also manually edit the .env file (see .env.example for reference)"
    echo ""
    echo "Documentation:"
    echo "- deployment-diagrams.md: Visual explanation of deployment options"
    echo "- quick-reference.md: Quick reference for common commands and settings"
    echo "- layman-guide.md: Simple explanation for non-technical users"
    echo "- troubleshooting-guide.md: Help with common issues"
    echo ""
    echo "Navigation Tips:"
    echo "- Use the main menu to navigate between configuration sections"
    echo "- Review your configuration before deployment"
    echo "- You can exit at any time by selecting '0' from the main menu"
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

# Define the execute_deployment function
execute_deployment() {
    # Validate required parameters
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$S3_BUCKET_NAME" || -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
            error "S3 backup requires bucket name, AWS access key, and AWS secret key"
            exit 1
        fi
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$DOMAIN_NAME" || -z "$ACME_EMAIL" ]]; then
            error "HTTPS setup requires domain name and email"
            exit 1
        fi
    fi
    
    # Create necessary directories
    log "Creating necessary directories..."
    DIRECTORIES=(
        "n8n"
        "postgres"
        "qdrant"
        "n8n-backup"
        "postgres-backup"
        "qdrant-backup"
        "shared"
    )
    
    # Add traefik directory if needed
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        DIRECTORIES+=("traefik")
    fi
    
    for dir in "${DIRECTORIES[@]}"; do
        create_directory_safe "$BASE_DIR/$dir" "1000:1000" "755"
    done
    
    # Generate secure credentials
    log "Generating secure credentials..."
    POSTGRES_USER="n8n"
    POSTGRES_DB="n8n"
    POSTGRES_PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' < /dev/urandom | head -c 32)
    N8N_ENCRYPTION_KEY=$(tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' < /dev/urandom | head -c 64)
    N8N_USER_MANAGEMENT_JWT_SECRET=$(tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' < /dev/urandom | head -c 64)
    
    # Create .env file
    log "Creating environment file..."
    cat > "$COMMON_ENV_FILE" << EOL
# n8n Docker Deployment - Common Environment File
# Generated on $(date)

# Deployment Type
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE}

# Database Configuration
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}

# n8n Security Configuration
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}

# Backup Configuration
BACKUP_RETENTION_DAYS=7
EOL
    
    # Add S3 configuration if needed
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        cat >> "$COMMON_ENV_FILE" << EOL

# AWS S3 Configuration
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_DEFAULT_REGION=${AWS_REGION}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
EOL
    fi
    
    # Add Traefik configuration if needed
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        # Generate Traefik dashboard credentials
        TRAEFIK_USER="admin"
        TRAEFIK_PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' < /dev/urandom | head -c 16)
        
        # Generate htpasswd entry
        if command_exists htpasswd; then
            HTPASSWD_ENTRY=$(htpasswd -nb "$TRAEFIK_USER" "$TRAEFIK_PASSWORD")
        elif command_exists docker; then
            HTPASSWD_ENTRY=$(docker run --rm httpd:alpine htpasswd -nb "$TRAEFIK_USER" "$TRAEFIK_PASSWORD")
        else
            error "Neither htpasswd nor docker is available. Cannot generate password hash."
            exit 1
        fi
        
        cat >> "$COMMON_ENV_FILE" << EOL

# Traefik Configuration
DOMAIN_NAME=${DOMAIN_NAME}
ACME_EMAIL=${ACME_EMAIL}
TRAEFIK_DASHBOARD_AUTH=${HTPASSWD_ENTRY}
EOL
        
        log "Traefik dashboard credentials:"
        log "Username: $TRAEFIK_USER"
        log "Password: $TRAEFIK_PASSWORD"
        log "Please save these credentials for accessing the Traefik dashboard."
    fi
    
    # Create backup script
    if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
        log "Creating local backup script..."
        cp "${SCRIPT_DIR}/local/backup.sh" "$BASE_DIR/backup.sh"
        chmod +x "$BASE_DIR/backup.sh"
    elif [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        log "Creating S3 backup script..."
        cp "${SCRIPT_DIR}/s3/backup-s3.sh" "$BASE_DIR/backup-s3.sh"
        chmod +x "$BASE_DIR/backup-s3.sh"
        
        # Setup cron job for S3 backup
        log "Setting up backup cron job..."
        CRON_JOB="0 0 * * * $BASE_DIR/backup-s3.sh"
        (crontab -l 2>/dev/null | grep -v "backup-s3.sh"; echo "$CRON_JOB") | crontab -
    fi
    
    # Copy environment file to data directory
    log "Copying environment file to data directory..."
    cp "$COMMON_ENV_FILE" "$BASE_DIR/.env"
    
    # Start services
    log "Starting n8n services..."
    
    # Determine which profiles to use based on deployment type
    PROFILES=""
    if [[ "$DEPLOYMENT_TYPE" == "s3" ]]; then
        PROFILES="--profile s3"
    elif [[ "$DEPLOYMENT_TYPE" == "traefik" ]]; then
        PROFILES="--profile traefik"
    elif [[ "$DEPLOYMENT_TYPE" == "production" ]]; then
        PROFILES="--profile s3 --profile traefik"
    fi
    
    # Create a temporary env file with only the variables needed for the selected deployment type
    TEMP_ENV_FILE=$(mktemp)
    grep -v "^#" "$COMMON_ENV_FILE" > "$TEMP_ENV_FILE"
    
    # Remove variables that are not needed for the current deployment type
    if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
        # Remove S3 and Traefik variables for local deployment
        sed -i '/AWS_/d' "$TEMP_ENV_FILE"
        sed -i '/S3_/d' "$TEMP_ENV_FILE"
        sed -i '/DOMAIN_/d' "$TEMP_ENV_FILE"
        sed -i '/ACME_/d' "$TEMP_ENV_FILE"
        sed -i '/TRAEFIK_/d' "$TEMP_ENV_FILE"
    elif [[ "$DEPLOYMENT_TYPE" == "s3" ]]; then
        # Remove Traefik variables for S3 deployment
        sed -i '/DOMAIN_/d' "$TEMP_ENV_FILE"
        sed -i '/ACME_/d' "$TEMP_ENV_FILE"
        sed -i '/TRAEFIK_/d' "$TEMP_ENV_FILE"
    elif [[ "$DEPLOYMENT_TYPE" == "traefik" ]]; then
        # Remove S3 variables for Traefik deployment
        sed -i '/AWS_/d' "$TEMP_ENV_FILE"
        sed -i '/S3_/d' "$TEMP_ENV_FILE"
    fi
    
    # Use the temporary env file for docker compose
    docker compose -f "$COMPOSE_FILE" --env-file "$TEMP_ENV_FILE" $PROFILES up -d
    
    # Clean up the temporary file
    rm -f "$TEMP_ENV_FILE"
    
    # Check services health
    log "Checking service health..."
    sleep 10  # Give services time to start
    
    check_service() {
        local service=$1
        local container_name=$2
        
        # If container_name is not provided, use default naming convention
        if [[ -z "$container_name" ]]; then
            container_name="n8n-$service"
        fi
        
        if docker ps | grep -q "$container_name"; then
            log "$service is running"
            return 0
        else
            error "$service failed to start"
            return 1
        fi
    }
    
    check_service "postgres" "n8n-postgres"
    check_service "n8n" "n8n"
    check_service "qdrant" "n8n-qdrant"
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        check_service "backup-scheduler"
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        check_service "traefik"
    fi
    
    # Implement production improvements if production deployment type is selected
    if [[ "$DEPLOYMENT_TYPE" == "production" ]]; then
        log "Implementing production improvements..."
        
        # Make the improvement scripts executable
        chmod +x "${SCRIPT_DIR}/utils/implement-improvements.sh"
        chmod +x "${SCRIPT_DIR}/utils/production-improvements.sh"
        
        # Run the improvements script
        log "Running production improvements script..."
        "${SCRIPT_DIR}/utils/implement-improvements.sh" --type production
        
        if [[ $? -eq 0 ]]; then
            log "Production improvements implemented successfully"
        else
            warn "Some production improvements could not be implemented"
            log "You can manually run: ${SCRIPT_DIR}/utils/implement-improvements.sh --type production --force"
        fi
    fi
    
    # Display access information
    log "Setup complete!"
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        log "n8n is available at: https://${DOMAIN_NAME}"
        log "Traefik dashboard is available at: https://traefik.${DOMAIN_NAME}"
        log "Username: $TRAEFIK_USER"
        log "Password: $TRAEFIK_PASSWORD"
    else
        log "n8n is available at: http://localhost:5678"
    fi
    
    log "Your credentials are stored in: $COMMON_ENV_FILE"
    log "IMPORTANT: Keep this file secure and never commit it to version control"
    
    # Display a friendly completion message
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║       n8n Deployment Setup Complete        ║"
    echo "║                                            ║"
    echo "║  Thank you for using the n8n setup script  ║"
    echo "╚════════════════════════════════════════════╝"
}

# Function to confirm and start deployment
confirm_and_deploy() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Confirm Deployment               ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "Configuration Summary:"
    echo "- Deployment Type: $DEPLOYMENT_TYPE"
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "- S3 Bucket: $S3_BUCKET_NAME"
        echo "- AWS Region: $AWS_REGION"
        echo "- AWS Access Key: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
        echo "- AWS Secret Key: ${AWS_SECRET_ACCESS_KEY:0:4}...${AWS_SECRET_ACCESS_KEY: -4}"
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "- Domain Name: $DOMAIN_NAME"
        echo "- Email: $ACME_EMAIL"
    fi
    
    # Validate required parameters
    local validation_error=false
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$S3_BUCKET_NAME" || -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
            error "S3 backup requires bucket name, AWS access key, and AWS secret key"
            validation_error=true
        fi
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$DOMAIN_NAME" || -z "$ACME_EMAIL" ]]; then
            error "HTTPS setup requires domain name and email"
            validation_error=true
        fi
    fi
    
    if [[ "$validation_error" == "true" ]]; then
        echo ""
        echo "Please fix the configuration errors before proceeding."
        echo "Press Enter to return to the main menu..."
        read
        display_main_menu
        return
    fi
    
    echo ""
    read -p "Start deployment with this configuration? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Deployment cancelled. Press Enter to return to the main menu..."
        read
        display_main_menu
        return
    fi
    
    # Proceed with deployment
    echo ""
    echo "Starting deployment..."
    echo ""
    
    # Execute the deployment process
    execute_deployment
    
    # Exit the menu system after deployment
    exit 0
}

# Start interactive menu if no command line arguments were provided or interactive mode is enabled
if [[ "$INTERACTIVE" == "true" && $# -eq 0 ]]; then
    display_main_menu
    # After exiting the menu system, we'll continue with the deployment process
elif [[ "$INTERACTIVE" == "true" ]]; then
    # Command line args were provided but interactive mode is still enabled
    # Show a summary and confirm
    echo "Welcome to the n8n Docker Deployment Setup!"
    echo "This script will guide you through setting up n8n with Docker."
    echo ""
    echo "Configuration Summary:"
    echo "- Deployment Type: $DEPLOYMENT_TYPE"
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "- S3 Bucket: $S3_BUCKET_NAME"
        echo "- AWS Region: $AWS_REGION"
        if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
            echo "- AWS Access Key: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
        fi
        if [[ -n "$AWS_SECRET_ACCESS_KEY" ]]; then
            echo "- AWS Secret Key: ${AWS_SECRET_ACCESS_KEY:0:4}...${AWS_SECRET_ACCESS_KEY: -4}"
        fi
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "- Domain Name: $DOMAIN_NAME"
        echo "- Email: $ACME_EMAIL"
    fi
    
    echo ""
    read -p "Continue with this configuration or enter the menu system? [C]ontinue/[M]enu: " menu_choice
    if [[ "$menu_choice" =~ ^[Mm] ]]; then
        display_main_menu
    fi
    
    # Ask for any missing required parameters
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$S3_BUCKET_NAME" ]]; then
            read -p "Enter S3 bucket name for backups: " S3_BUCKET_NAME
        fi
        
        if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
            read -p "Enter AWS access key ID: " AWS_ACCESS_KEY_ID
        fi
        
        if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
            read -p "Enter AWS secret access key: " AWS_SECRET_ACCESS_KEY
        fi
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        if [[ -z "$DOMAIN_NAME" ]]; then
            read -p "Enter domain name for n8n (e.g., n8n.example.com): " DOMAIN_NAME
        fi
        
        if [[ -z "$ACME_EMAIL" ]]; then
            read -p "Enter email for Let's Encrypt notifications: " ACME_EMAIL
        fi
    fi
    
    echo ""
    echo "Final Configuration:"
    echo "- Deployment Type: $DEPLOYMENT_TYPE"
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "- S3 Bucket: $S3_BUCKET_NAME"
        echo "- AWS Region: $AWS_REGION"
        echo "- AWS Access Key: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
        echo "- AWS Secret Key: ${AWS_SECRET_ACCESS_KEY:0:4}...${AWS_SECRET_ACCESS_KEY: -4}"
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "traefik" || "$DEPLOYMENT_TYPE" == "production" ]]; then
        echo "- Domain Name: $DOMAIN_NAME"
        echo "- Email: $ACME_EMAIL"
    fi
    
    echo ""
    read -p "Continue with this configuration? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        log "Setup cancelled by user"
        exit 0
    fi
fi

# Complete the execute_deployment function
# Execute the deployment process
if [[ "$INTERACTIVE" == "true" ]]; then
    # If we came from the menu system, the confirm_and_deploy function would have returned 0
    # If we came from the command line args path, we've already confirmed
    execute_deployment
else
    # Non-interactive mode, just execute the deployment
    execute_deployment
fi