#!/bin/bash

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "${SCRIPT_DIR}/../utils/common.sh" ]]; then
    source "${SCRIPT_DIR}/../utils/common.sh"
else
    # Minimal logging functions if common.sh is not available
    log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
    error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"; exit 1; }
    warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"; }
fi

# Load environment variables
if [[ -f "${SCRIPT_DIR}/s3.env" ]]; then
    source "${SCRIPT_DIR}/s3.env"
elif [[ -f "/opt/n8n-data/s3.env" ]]; then
    source "/opt/n8n-data/s3.env"
else
    error "s3.env file not found"
fi

# Configuration
BACKUP_ROOT="/opt/n8n-data"
COMPOSE_FILE="docker-compose.yml"
TEMP_DIR="/tmp/n8n-restore-$(date +%Y%m%d_%H%M%S)"

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --backup-id YYYYMMDD_HHMMSS  Specific backup to restore"
    echo "  --latest                     Restore latest backup"
    echo "  --component TYPE             Restore specific component (database|n8n|qdrant)"
    echo "  --force                      Force restore without confirmation"
    echo "  --dry-run                    Show what would be restored without actually restoring"
    echo "  --use-full-backup            Use the full backup archive instead of individual component backups"
    echo "Example:"
    echo "  $0 --backup-id 20240101_120000 --component database"
    echo "  $0 --latest --component n8n"
    echo "  $0 --latest                  (restores everything)"
    exit 1
}

# Parse command line arguments
BACKUP_ID=""
COMPONENT=""
RESTORE_LATEST=false
FORCE=false
DRY_RUN=false
USE_FULL_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-id)
            BACKUP_ID="$2"
            shift 2
            ;;
        --latest)
            RESTORE_LATEST=true
            shift
            ;;
        --component)
            COMPONENT="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --use-full-backup)
            USE_FULL_BACKUP=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate inputs
if [[ "$RESTORE_LATEST" == "false" && -z "$BACKUP_ID" ]]; then
    error "Either --backup-id or --latest must be specified"
fi

if [[ -n "$COMPONENT" && ! "$COMPONENT" =~ ^(database|n8n|qdrant)$ ]]; then
    error "Invalid component specified. Must be database, n8n, or qdrant"
fi

# Validate backup ID format if provided
if [[ -n "$BACKUP_ID" ]]; then
    if ! [[ $BACKUP_ID =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        error "Invalid backup ID format: $BACKUP_ID. Expected format: YYYYMMDD_HHMMSS"
    fi
fi

# Validate AWS credentials
log "Validating AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    error "Invalid AWS credentials. Please check your AWS configuration in s3.env"
fi

# Create temporary directory
mkdir -p "$TEMP_DIR"
if [[ $? -ne 0 ]]; then
    error "Failed to create temporary directory: $TEMP_DIR"
fi

# Get backup manifest
if [[ "$RESTORE_LATEST" == "true" ]]; then
    log "Fetching latest backup manifest..."
    if ! aws s3 cp "s3://${S3_BUCKET_NAME}/backups/latest_backup_manifest.json" "${TEMP_DIR}/manifest.json"; then
        rm -rf "$TEMP_DIR"
        error "Failed to fetch latest backup manifest"
    fi
    BACKUP_ID=$(jq -r '.backup_id' "${TEMP_DIR}/manifest.json" 2>/dev/null)
    if [[ -z "$BACKUP_ID" || "$BACKUP_ID" == "null" ]]; then
        rm -rf "$TEMP_DIR"
        error "Invalid or missing backup ID in manifest"
    fi
    log "Latest backup ID: $BACKUP_ID"
else
    log "Fetching backup manifest for ID: $BACKUP_ID..."
    if ! aws s3 cp "s3://${S3_BUCKET_NAME}/backups/${BACKUP_ID}/manifest.json" "${TEMP_DIR}/manifest.json"; then
        # Try alternative path
        if ! aws s3 ls "s3://${S3_BUCKET_NAME}/backups/full_backup_${BACKUP_ID}.tar.gz" &>/dev/null; then
            rm -rf "$TEMP_DIR"
            error "Backup ID $BACKUP_ID not found in S3 bucket"
        else
            # Create a minimal manifest
            cat > "${TEMP_DIR}/manifest.json" << EOF
{
    "backup_id": "${BACKUP_ID}",
    "full_backup": "full_backup_${BACKUP_ID}.tar.gz"
}
EOF
            USE_FULL_BACKUP=true
            log "No manifest found, but full backup archive exists. Using full backup."
        fi
    fi
fi

S3_BACKUP_PATH="s3://${S3_BUCKET_NAME}/backups/${BACKUP_ID}"

# Verify backup files exist in S3
verify_s3_backup_exists() {
    local component=$1
    local backup_id=$2
    local s3_path=""
    
    if [[ "$USE_FULL_BACKUP" == "true" ]]; then
        s3_path="s3://${S3_BUCKET_NAME}/backups/full_backup_${backup_id}.tar.gz"
    else
        case $component in
            database)
                s3_path="${S3_BACKUP_PATH}/database/db_${backup_id}.sql"
                ;;
            n8n)
                s3_path="${S3_BACKUP_PATH}/n8n/n8n_${backup_id}.tar.gz"
                ;;
            qdrant)
                s3_path="${S3_BACKUP_PATH}/qdrant/qdrant_${backup_id}.tar.gz"
                ;;
        esac
    fi
    
    if ! aws s3 ls "$s3_path" &>/dev/null; then
        if [[ "$USE_FULL_BACKUP" == "false" ]]; then
            # Try full backup as fallback
            if aws s3 ls "s3://${S3_BUCKET_NAME}/backups/full_backup_${backup_id}.tar.gz" &>/dev/null; then
                warn "$component backup file not found at $s3_path"
                warn "Falling back to full backup archive"
                USE_FULL_BACKUP=true
                return 0
            fi
        fi
        error "$component backup file not found: $s3_path"
        return 1
    fi
    
    log "Verified $component backup exists: $s3_path"
    return 0
}

# Function to extract component from full backup
extract_from_full_backup() {
    local component=$1
    local backup_id=$2
    local extract_path="${TEMP_DIR}/${component}"
    local full_backup_path="${TEMP_DIR}/full_backup.tar.gz"
    
    # Download full backup if not already downloaded
    if [[ ! -f "$full_backup_path" ]]; then
        log "Downloading full backup archive..."
        if ! aws s3 cp "s3://${S3_BUCKET_NAME}/backups/full_backup_${backup_id}.tar.gz" "$full_backup_path"; then
            error "Failed to download full backup archive"
            return 1
        fi
    fi
    
    # Create extraction directory
    mkdir -p "$extract_path"
    
    # Extract specific component file from full backup
    log "Extracting $component from full backup..."
    case $component in
        database)
            if ! tar -xzf "$full_backup_path" -C "$extract_path" "db_${backup_id}.sql" 2>/dev/null; then
                error "Failed to extract database backup from full archive"
                return 1
            fi
            mv "${extract_path}/db_${backup_id}.sql" "${TEMP_DIR}/db_restore.sql"
            ;;
        n8n)
            if ! tar -xzf "$full_backup_path" -C "$extract_path" "n8n_${backup_id}.tar.gz" 2>/dev/null; then
                error "Failed to extract n8n backup from full archive"
                return 1
            fi
            mv "${extract_path}/n8n_${backup_id}.tar.gz" "${TEMP_DIR}/n8n_restore.tar.gz"
            ;;
        qdrant)
            if ! tar -xzf "$full_backup_path" -C "$extract_path" "qdrant_${backup_id}.tar.gz" 2>/dev/null; then
                error "Failed to extract Qdrant backup from full archive"
                return 1
            fi
            mv "${extract_path}/qdrant_${backup_id}.tar.gz" "${TEMP_DIR}/qdrant_restore.tar.gz"
            ;;
    esac
    
    return 0
}

# Function to restore database
restore_database() {
    log "Restoring PostgreSQL database..."
    local restore_file="${TEMP_DIR}/db_restore.sql"
    
    if [[ "$USE_FULL_BACKUP" == "true" ]]; then
        extract_from_full_backup "database" "$BACKUP_ID" || return 1
    else
        # Download database backup
        log "Downloading database backup..."
        if ! aws s3 cp "${S3_BACKUP_PATH}/database/db_${BACKUP_ID}.sql" "$restore_file"; then
            error "Failed to download database backup"
            return 1
        fi
    fi
    
    # Verify backup integrity
    if ! grep -q "CREATE TABLE\|INSERT INTO\|BEGIN\|COMMIT" "$restore_file"; then
        error "Database backup file appears to be invalid or empty"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would restore database from: $restore_file"
        return 0
    fi
    
    # Restore database
    log "Applying database restore..."
    if docker exec -i n8n-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < "$restore_file"; then
        log "Database restore completed successfully"
    else
        error "Failed to restore database"
        return 1
    fi
    
    return 0
}

# Function to restore n8n
restore_n8n() {
    log "Restoring n8n data..."
    local restore_file="${TEMP_DIR}/n8n_restore.tar.gz"
    local extract_dir="${TEMP_DIR}/n8n_extract"
    
    if [[ "$USE_FULL_BACKUP" == "true" ]]; then
        extract_from_full_backup "n8n" "$BACKUP_ID" || return 1
    else
        # Download n8n backup
        log "Downloading n8n backup..."
        if ! aws s3 cp "${S3_BACKUP_PATH}/n8n/n8n_${BACKUP_ID}.tar.gz" "$restore_file"; then
            error "Failed to download n8n backup"
            return 1
        fi
    fi
    
    # Verify backup integrity
    if ! tar -tzf "$restore_file" &>/dev/null; then
        error "n8n backup file is corrupted or invalid"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would restore n8n from: $restore_file"
        return 0
    fi
    
    # Create extraction directory
    mkdir -p "$extract_dir"
    
    # Extract backup
    log "Extracting n8n backup..."
    if ! tar -xzf "$restore_file" -C "$extract_dir"; then
        error "Failed to extract n8n backup"
        return 1
    fi
    
    # Clear destination directory safely
    log "Clearing n8n directory..."
    find "$BACKUP_ROOT/n8n" -mindepth 1 -delete
    if [[ $? -ne 0 ]]; then
        error "Failed to clear n8n directory"
        return 1
    fi
    
    # Copy files from extraction directory to destination
    log "Copying restored files..."
    cp -a "$extract_dir/." "$BACKUP_ROOT/n8n/"
    if [[ $? -ne 0 ]]; then
        error "Failed to copy n8n backup files"
        return 1
    fi
    
    log "n8n restore completed successfully"
    return 0
}

# Function to restore Qdrant
restore_qdrant() {
    log "Restoring Qdrant data..."
    local restore_file="${TEMP_DIR}/qdrant_restore.tar.gz"
    local extract_dir="${TEMP_DIR}/qdrant_extract"
    
    if [[ "$USE_FULL_BACKUP" == "true" ]]; then
        extract_from_full_backup "qdrant" "$BACKUP_ID" || return 1
    else
        # Download Qdrant backup
        log "Downloading Qdrant backup..."
        if ! aws s3 cp "${S3_BACKUP_PATH}/qdrant/qdrant_${BACKUP_ID}.tar.gz" "$restore_file"; then
            error "Failed to download Qdrant backup"
            return 1
        fi
    fi
    
    # Verify backup integrity
    if ! tar -tzf "$restore_file" &>/dev/null; then
        error "Qdrant backup file is corrupted or invalid"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would restore Qdrant from: $restore_file"
        return 0
    fi
    
    # Create extraction directory
    mkdir -p "$extract_dir"
    
    # Extract backup
    log "Extracting Qdrant backup..."
    if ! tar -xzf "$restore_file" -C "$extract_dir"; then
        error "Failed to extract Qdrant backup"
        return 1
    fi
    
    # Clear destination directory safely
    log "Clearing Qdrant directory..."
    find "$BACKUP_ROOT/qdrant" -mindepth 1 -delete
    if [[ $? -ne 0 ]]; then
        error "Failed to clear Qdrant directory"
        return 1
    fi
    
    # Copy files from extraction directory to destination
    log "Copying restored files..."
    cp -a "$extract_dir/." "$BACKUP_ROOT/qdrant/"
    if [[ $? -ne 0 ]]; then
        error "Failed to copy Qdrant backup files"
        return 1
    fi
    
    log "Qdrant restore completed successfully"
    return 0
}

# Show restore plan
log "Restore plan:"
log "  Backup ID: $BACKUP_ID"
if [[ "$USE_FULL_BACKUP" == "true" ]]; then
    log "  Using full backup archive"
fi

if [[ -z "$COMPONENT" ]]; then
    log "  Components: All (database, n8n, qdrant)"
    
    # Verify all backup files exist
    verify_s3_backup_exists "database" "$BACKUP_ID"
    verify_s3_backup_exists "n8n" "$BACKUP_ID"
    verify_s3_backup_exists "qdrant" "$BACKUP_ID"
else
    log "  Component: $COMPONENT"
    
    # Verify specific backup file exists
    verify_s3_backup_exists "$COMPONENT" "$BACKUP_ID"
fi

# Confirm restore unless --force is specified
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    read -p "Are you sure you want to proceed with the restore? This will stop all services and replace existing data. [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled by user"
        rm -rf "$TEMP_DIR"
        exit 0
    fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log "Performing dry run - no changes will be made"
else
    # Stop services before restore
    log "Stopping services..."
    docker compose down
    if [[ $? -ne 0 ]]; then
        warn "Failed to stop services cleanly. Proceeding with restore anyway..."
    fi
fi

# Perform restore based on component selection
if [[ -z "$COMPONENT" ]]; then
    restore_database
    restore_n8n
    restore_qdrant
else
    case $COMPONENT in
        database)
            restore_database
            ;;
        n8n)
            restore_n8n
            ;;
        qdrant)
            restore_qdrant
            ;;
    esac
fi

if [[ "$DRY_RUN" != "true" ]]; then
    # Start services
    log "Starting services..."
    docker compose up -d
    if [[ $? -ne 0 ]]; then
        error "Failed to start services after restore"
    fi
    
    # Check services health
    log "Checking service health..."
    sleep 10  # Give services time to start
    
    check_service() {
        local service=$1
        if docker ps | grep -q "n8n-$service"; then
            log "$service is running"
            return 0
        else
            warn "$service failed to start"
            return 1
        fi
    }
    
    if [[ -z "$COMPONENT" || "$COMPONENT" == "database" ]]; then
        check_service "postgres"
    fi
    
    if [[ -z "$COMPONENT" || "$COMPONENT" == "n8n" ]]; then
        check_service "n8n"
    fi
    
    if [[ -z "$COMPONENT" || "$COMPONENT" == "qdrant" ]]; then
        check_service "qdrant"
    fi
    
    log "Restore completed successfully"
else
    log "Dry run completed. No changes were made."
fi

# Cleanup
log "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"