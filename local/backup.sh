#!/bin/bash

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "${SCRIPT_DIR}/../utils/common.sh" ]]; then
    source "${SCRIPT_DIR}/../utils/common.sh"
else
    # Minimal logging functions if common.sh is not available
    log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
    error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"; }
    warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"; }
fi

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_ROOT="${BASE_DIR}"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Load environment variables if available
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    source "${SCRIPT_DIR}/.env"
fi

# Check for sufficient disk space
check_disk_space() {
    local required_mb=$1
    local available_mb=$(df -m "$BACKUP_ROOT" | awk 'NR==2 {print $4}')
    
    if [[ $available_mb -lt $required_mb ]]; then
        error "Insufficient disk space for backup. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    
    log "Sufficient disk space available: ${available_mb}MB"
    return 0
}

# Estimate backup size
estimate_size() {
    local n8n_size=$(du -sm "$BACKUP_ROOT/n8n" 2>/dev/null | awk '{print $1}')
    local postgres_size=$(du -sm "$BACKUP_ROOT/postgres" 2>/dev/null | awk '{print $1}')
    local qdrant_size=$(du -sm "$BACKUP_ROOT/qdrant" 2>/dev/null | awk '{print $1}')
    
    # Default to minimum sizes if directories don't exist yet
    n8n_size=${n8n_size:-100}
    postgres_size=${postgres_size:-100}
    qdrant_size=${qdrant_size:-100}
    
    # Add 20% overhead for compression and temporary files
    local total_size=$(( (n8n_size + postgres_size + qdrant_size) * 120 / 100 ))
    echo $total_size
}

# Verify backup file integrity
verify_backup() {
    local file=$1
    local type=$2
    
    case $type in
        tar)
            tar -tzf "$file" &>/dev/null
            return $?
            ;;
        sql)
            # Simple check if file is not empty and contains SQL
            [[ -s "$file" ]] && grep -q "CREATE TABLE\|INSERT INTO\|BEGIN\|COMMIT" "$file"
            return $?
            ;;
        *)
            # Default check if file exists and is not empty
            [[ -s "$file" ]]
            return $?
            ;;
    esac
}

# Check required disk space
required_space=$(estimate_size)
check_disk_space $required_space || exit 1

log "Starting backup process (ID: $BACKUP_DATE)"

# Backup PostgreSQL
log "Backing up PostgreSQL database..."
if docker exec n8n-postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > "$BACKUP_ROOT/postgres-backup/db_$BACKUP_DATE.sql"; then
    log "PostgreSQL backup completed"
    
    # Verify backup
    if verify_backup "$BACKUP_ROOT/postgres-backup/db_$BACKUP_DATE.sql" sql; then
        log "PostgreSQL backup verified"
    else
        error "PostgreSQL backup verification failed"
    fi
else
    error "PostgreSQL backup failed"
fi

# Backup n8n workflows and data
log "Backing up n8n data..."
if tar -czf "$BACKUP_ROOT/n8n-backup/n8n_$BACKUP_DATE.tar.gz" -C "$BACKUP_ROOT/n8n" .; then
    log "n8n backup completed"
    
    # Verify backup
    if verify_backup "$BACKUP_ROOT/n8n-backup/n8n_$BACKUP_DATE.tar.gz" tar; then
        log "n8n backup verified"
    else
        error "n8n backup verification failed"
    fi
else
    error "n8n backup failed"
fi

# Backup Qdrant data
log "Backing up Qdrant data..."
if tar -czf "$BACKUP_ROOT/qdrant-backup/qdrant_$BACKUP_DATE.tar.gz" -C "$BACKUP_ROOT/qdrant" .; then
    log "Qdrant backup completed"
    
    # Verify backup
    if verify_backup "$BACKUP_ROOT/qdrant-backup/qdrant_$BACKUP_DATE.tar.gz" tar; then
        log "Qdrant backup verified"
    else
        error "Qdrant backup verification failed"
    fi
else
    error "Qdrant backup failed"
fi

# Keep only backups within retention period
log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_ROOT/postgres-backup" -name "db_*.sql" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_ROOT/n8n-backup" -name "n8n_*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_ROOT/qdrant-backup" -name "qdrant_*.tar.gz" -mtime +$RETENTION_DAYS -delete

log "Backup process completed successfully"
