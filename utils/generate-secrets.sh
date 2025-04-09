#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Function to generate a secure random string
generate_secure_string() {
    local length=$1
    local charset="A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?"
    
    # Generate random string using /dev/urandom
    tr -dc "$charset" < /dev/urandom | head -c "$length"
    echo
}

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Generate secure credentials for n8n deployment"
    echo ""
    echo "Options:"
    echo "  -h, --help             Display this help message"
    echo "  -o, --output FILE      Write output to FILE instead of stdout"
    echo "  -l, --local            Generate credentials for local deployment"
    echo "  -s, --s3               Generate credentials for S3 deployment"
    echo "  --postgres-user USER   Set PostgreSQL username (default: n8n)"
    echo "  --postgres-db DB       Set PostgreSQL database name (default: n8n)"
    echo ""
    echo "Examples:"
    echo "  $0 --local             Generate credentials for local deployment"
    echo "  $0 --s3 --output s3.env Generate credentials for S3 deployment and save to s3.env"
}

# Default values
OUTPUT_FILE=""
DEPLOYMENT_TYPE="local"
POSTGRES_USER="n8n"
POSTGRES_DB="n8n"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -l|--local)
            DEPLOYMENT_TYPE="local"
            shift
            ;;
        -s|--s3)
            DEPLOYMENT_TYPE="s3"
            shift
            ;;
        --postgres-user)
            POSTGRES_USER="$2"
            shift 2
            ;;
        --postgres-db)
            POSTGRES_DB="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Generate credentials
POSTGRES_PASSWORD=$(generate_secure_string 32)
N8N_ENCRYPTION_KEY=$(generate_secure_string 64)
N8N_USER_MANAGEMENT_JWT_SECRET=$(generate_secure_string 64)

# Create output content
generate_output() {
    echo "# n8n Database Configuration"
    echo "POSTGRES_USER=$POSTGRES_USER"
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
    echo "POSTGRES_DB=$POSTGRES_DB"
    echo ""
    echo "# n8n Security Configuration"
    echo "# These are randomly generated secure keys (64 characters)"
    echo "N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY"
    echo "N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET"
    echo ""
    
    # Add S3-specific configuration if needed
    if [[ "$DEPLOYMENT_TYPE" == "s3" ]]; then
        echo "# AWS Configuration"
        echo "# Replace these with your actual AWS credentials"
        echo "AWS_ACCESS_KEY_ID=your_access_key"
        echo "AWS_SECRET_ACCESS_KEY=your_secret_key"
        echo "AWS_DEFAULT_REGION=us-east-1"
        echo "S3_BUCKET_NAME=your-n8n-backup-bucket"
        echo ""
        echo "# Backup Configuration"
        echo "BACKUP_RETENTION_DAYS=7"
        echo ""
    fi
    
    echo "# Optional: n8n Additional Settings"
    echo "# N8N_HOST=localhost"
    echo "# N8N_PORT=5678"
    echo "# N8N_PROTOCOL=http"
    echo "# N8N_WEB_HOOK_URL=http://localhost:5678/"
    echo "# N8N_EDITOR_BASE_URL=http://localhost:5678/"
    echo ""
    echo "# Optional: PostgreSQL Performance Tuning"
    echo "# POSTGRES_MAX_CONNECTIONS=100"
    echo "# POSTGRES_SHARED_BUFFERS=2GB"
    echo "# POSTGRES_EFFECTIVE_CACHE_SIZE=6GB"
    
    if [[ "$DEPLOYMENT_TYPE" == "s3" ]]; then
        echo ""
        echo "# Optional: AWS Additional Settings"
        echo "# AWS_ENDPOINT=https://s3.amazonaws.com"
        echo "# AWS_S3_FORCE_PATH_STYLE=false"
        echo "# AWS_S3_SSE=AES256"
    fi
}

# Output the generated credentials
if [[ -n "$OUTPUT_FILE" ]]; then
    # Write to file
    generate_output > "$OUTPUT_FILE"
    if [[ $? -eq 0 ]]; then
        log "Credentials written to $OUTPUT_FILE"
        log "IMPORTANT: Keep this file secure and never commit it to version control"
    else
        error "Failed to write credentials to $OUTPUT_FILE"
        exit 1
    fi
else
    # Write to stdout
    log "Generating secure credentials for n8n $DEPLOYMENT_TYPE deployment..."
    echo ""
    generate_output
    echo ""
    log "IMPORTANT: Copy these credentials to your .env or s3.env file"
    log "Keep your environment files secure and never commit them to version control"
fi