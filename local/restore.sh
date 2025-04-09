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

# Configuration
BACKUP_ROOT="/opt/n8n-data"
COMPOSE_FILE="docker-compose.yml"

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --backup-id YYYYMMDD_HHMMSS  Specific backup to restore"
    echo "  --latest                     Restore latest backup"
    echo "  --component TYPE             Restore specific component (database|n8n|qdrant)"
    echo "  --force                      Force restore without confirmation"
    echo "  --dry-run                    Show what would be restored without actually restoring"
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
        --help|-h)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Load environment variables if available
if [[ -f ".env" ]]; then
    source ".env"
fi

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

# If latest is requested, find the most recent backup
if [[ "$RESTORE_LATEST" == "true" ]]; then
    log "Looking for latest backup..."
    
    if [[ -z "$COMPONENT" || "$COMPONENT" == "database" ]]; then
        BACKUP_ID=$(ls -t "$BACKUP_ROOT/postgres-backup/db_"*.sql 2>/dev/null | head -n1 | sed 's/.*db_\([0-9_]*\)\.sql/\1/')
        if [[ -z "$BACKUP_ID" && -z "$COMPONENT" ]]; then
            error "No database backups found"
        elif [[ -z "$BACKUP_ID" && "$COMPONENT" == "database" ]]; then
            error "No database backups found"
        fi
    fi
    
    if [[ -z "$COMPONENT" || "$COMPONENT" == "n8n" ]]; then
        N8N_BACKUP_ID=$(ls -t "$BACKUP_ROOT/n8n-backup/n8n_"*.tar.gz 2>/dev/null | head -n1 | sed 's/.*n8n_\([0-9_]*\)\.tar\.gz/\1/')
        if [[ -z "$BACKUP_ID" ]]; then
            BACKUP_ID="$N8N_BACKUP_ID"
        elif [[ "$COMPONENT" == "n8n" ]]; then
            BACKUP_ID="$N8N_BACKUP_ID"
        fi
        
        if [[ -z "$N8N_BACKUP_ID" && -z "$COMPONENT" ]]; then
            warn "No n8n backups found"
        elif [[ -z "$N8N_BACKUP_ID" && "$COMPONENT" == "n8n" ]]; then
            error "No n8n backups found"
        fi
    fi
    
    if [[ -z "$COMPONENT" || "$COMPONENT" == "qdrant" ]]; then
        QDRANT_BACKUP_ID=$(ls -t "$BACKUP_ROOT/qdrant-backup/qdrant_"*.tar.gz 2>/dev/null | head -n1 | sed 's/.*qdrant_\([0-9_]*\)\.tar\.gz/\1/')
        if [[ -z "$BACKUP_ID" ]]; then
            BACKUP_ID="$QDRANT_BACKUP_ID"
        elif [[ "$COMPONENT" == "qdrant" ]]; then
            BACKUP_ID="$QDRANT_BACKUP_ID"
        fi
        
        if [[ -z "$QDRANT_BACKUP_ID" && -z "$COMPONENT" ]]; then
            warn "No Qdrant backups found"
        elif [[ -z "$QDRANT_BACKUP_ID" && "$COMPONENT" == "qdrant" ]]; then
            error "No Qdrant backups found"
        fi
    fi
    
    if [[ -z "$BACKUP_ID" ]]; then
        error "No backups found"
    fi
    
    log "Latest backup ID: $BACKUP_ID"
fi

# Verify backup files exist
verify_backup_exists() {
    local component=$1
    local backup_id=$2
    local file=""
    
    case $component in
        database)
            file="$BACKUP_ROOT/postgres-backup/db_${backup_id}.sql"
            ;;
        n8n)
            file="$BACKUP_ROOT/n8n-backup/n8n_${backup_id}.tar.gz"
            ;;
        qdrant)
            file="$BACKUP_ROOT/qdrant-backup/qdrant_${backup_id}.tar.gz"
            ;;
    esac
    
    if [[ ! -f "$file" ]]; then
        error "$component backup file not found: $file"
    fi
    
    log "Verified $component backup exists: $file"
    return 0
}

# Function to restore database
restore_database() {
    log "Restoring PostgreSQL database..."
    local backup_file="$BACKUP_ROOT/postgres-backup/db_${BACKUP_ID}.sql"
    
    # Verify backup exists
    if [[ ! -f "$backup_file" ]]; then
        error "Database backup file not found: $backup_file"
    fi
    
    # Check if file is valid SQL
    if ! grep -q "CREATE TABLE\|INSERT INTO\|BEGIN\|COMMIT" "$backup_file"; then
        error "Database backup file appears to be invalid or empty: $backup_file"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would restore database from: $backup_file"
        return 0
    fi
    
    # Restore database
    if docker exec -i n8n-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < "$backup_file"; then
        log "Database restore completed successfully"
    else
        error "Failed to restore database"
    fi
}

# Function to restore n8n
restore_n8n() {
    log "Restoring n8n data..."
    local backup_file="$BACKUP_ROOT/n8n-backup/n8n_${BACKUP_ID}.tar.gz"
    local temp_dir="/tmp/n8n_restore_${BACKUP_ID}"
    
    # Verify backup exists
    if [[ ! -f "$backup_file" ]]; then
        error "n8n backup file not found: $backup_file"
    fi
    
    # Verify backup integrity
    if ! tar -tzf "$backup_file" &>/dev/null; then
        error "n8n backup file is corrupted or invalid: $backup_file"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would restore n8n from: $backup_file"
        return 0
    fi
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    if [[ $? -ne 0 ]]; then
        error "Failed to create temporary directory: $temp_dir"
    fi
    
    # Extract backup to temporary directory
    if ! tar -xzf "$backup_file" -C "$temp_dir"; then
        rm -rf "$temp_dir"
        error "Failed to extract n8n backup"
    fi
    
    # Clear destination directory safely
    log "Clearing n8n directory..."
    find "$BACKUP_ROOT/n8n" -mindepth 1 -delete
    if [[ $? -ne 0 ]]; then
        rm -rf "$temp_dir"
        error "Failed to clear n8n directory"
    fi
    
    # Copy files from temp directory to destination
    log "Copying restored files..."
    cp -a "$temp_dir/." "$BACKUP_ROOT/n8n/"
    if [[ $? -ne 0 ]]; then
        rm -rf "$temp_dir"
        error "Failed to copy n8n backup files"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "n8n restore completed successfully"
}

# Function to restore Qdrant
restore_qdrant() {
    log "Restoring Qdrant data..."
    local backup_file="$BACKUP_ROOT/qdrant-backup/qdrant_${BACKUP_ID}.tar.gz"
    local temp_dir="/tmp/qdrant_restore_${BACKUP_ID}"
    
    # Verify backup exists
    if [[ ! -f "$backup_file" ]]; then
        error "Qdrant backup file not found: $backup_file"
    fi
    
    # Verify backup integrity
    if ! tar -tzf "$backup_file" &>/dev/null; then
        error "Qdrant backup file is corrupted or invalid: $backup_file"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would restore Qdrant from: $backup_file"
        return 0
    fi
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    if [[ $? -ne 0 ]]; then
        error "Failed to create temporary directory: $temp_dir"
    fi
    
    # Extract backup to temporary directory
    if ! tar -xzf "$backup_file" -C "$temp_dir"; then
        rm -rf "$temp_dir"
        error "Failed to extract Qdrant backup"
    fi
    
    # Clear destination directory safely
    log "Clearing Qdrant directory..."
    find "$BACKUP_ROOT/qdrant" -mindepth 1 -delete
    if [[ $? -ne 0 ]]; then
        rm -rf "$temp_dir"
        error "Failed to clear Qdrant directory"
    fi
    
    # Copy files from temp directory to destination
    log "Copying restored files..."
    cp -a "$temp_dir/." "$BACKUP_ROOT/qdrant/"
    if [[ $? -ne 0 ]]; then
        rm -rf "$temp_dir"
        error "Failed to copy Qdrant backup files"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "Qdrant restore completed successfully"
}

# Show restore plan
log "Restore plan:"
log "  Backup ID: $BACKUP_ID"
if [[ -z "$COMPONENT" ]]; then
    log "  Components: All (database, n8n, qdrant)"
    
    # Verify all backup files exist
    verify_backup_exists "database" "$BACKUP_ID"
    verify_backup_exists "n8n" "$BACKUP_ID"
    verify_backup_exists "qdrant" "$BACKUP_ID"
else
    log "  Component: $COMPONENT"
    
    # Verify specific backup file exists
    verify_backup_exists "$COMPONENT" "$BACKUP_ID"
fi

# Confirm restore unless --force is specified
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    read -p "Are you sure you want to proceed with the restore? This will stop all services and replace existing data. [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled by user"
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