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
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_ROOT="/opt/n8n-data"
TEMP_DIR="/tmp/n8n-backup-${BACKUP_DATE}"
S3_BACKUP_PATH="s3://${S3_BUCKET_NAME}/backups/${BACKUP_DATE}"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

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

# Validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        error "Invalid AWS credentials. Please check your AWS configuration in s3.env"
        return 1
    fi
    log "AWS credentials validated successfully"
    return 0
}

# Validate S3 bucket
validate_s3_bucket() {
    log "Validating S3 bucket..."
    if ! aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
        log "S3 bucket ${S3_BUCKET_NAME} does not exist. Creating..."
        if ! aws s3 mb "s3://${S3_BUCKET_NAME}"; then
            error "Failed to create S3 bucket: ${S3_BUCKET_NAME}"
            return 1
        fi
        log "S3 bucket created successfully"
    else
        log "S3 bucket ${S3_BUCKET_NAME} exists"
    fi
    return 0
}

# Clean up old backups from S3
cleanup_old_backups() {
    log "Cleaning up old backups from S3 (retention: $RETENTION_DAYS days)..."
    local cutoff_date=$(date -d "-${RETENTION_DAYS} days" +%Y%m%d)
    
    # List all backups
    local backups=$(aws s3 ls "s3://${S3_BUCKET_NAME}/backups/" --recursive | grep "full_backup_" | awk '{print $4}')
    
    # Delete old backups
    for backup in $backups; do
        local backup_date=$(echo "$backup" | grep -o '[0-9]\{8\}_[0-9]\{6\}' | cut -d'_' -f1)
        if [[ "$backup_date" < "$cutoff_date" ]]; then
            log "Deleting old backup: $backup"
            aws s3 rm "s3://${S3_BUCKET_NAME}/$backup"
        fi
    done
}

# Check required disk space
required_space=$(estimate_size)
check_disk_space $required_space || exit 1

# Validate AWS credentials
validate_aws_credentials || exit 1

# Validate S3 bucket
validate_s3_bucket || exit 1

log "Starting backup process (ID: $BACKUP_DATE)"

# Create S3 backup directory structure
log "Creating S3 directory structure..."
aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "backups/${BACKUP_DATE}/"
if [[ $? -ne 0 ]]; then
    error "Failed to create S3 directory structure"
fi

# Create temporary directory
log "Creating temporary directory..."
mkdir -p "${TEMP_DIR}"
if [[ $? -ne 0 ]]; then
    error "Failed to create temporary directory: ${TEMP_DIR}"
fi

# Backup PostgreSQL
log "Backing up PostgreSQL database..."
if docker exec n8n-postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > "${TEMP_DIR}/db_${BACKUP_DATE}.sql"; then
    log "PostgreSQL backup completed"
    
    # Verify backup
    if verify_backup "${TEMP_DIR}/db_${BACKUP_DATE}.sql" sql; then
        log "PostgreSQL backup verified"
        
        # Upload to S3
        log "Uploading PostgreSQL backup to S3..."
        aws s3 cp "${TEMP_DIR}/db_${BACKUP_DATE}.sql" "${S3_BACKUP_PATH}/database/db_${BACKUP_DATE}.sql"
        if [[ $? -ne 0 ]]; then
            error "Failed to upload PostgreSQL backup to S3"
        fi
    else
        error "PostgreSQL backup verification failed"
    fi
else
    error "PostgreSQL backup failed"
fi

# Backup n8n workflows and data
log "Backing up n8n data..."
if tar -czf "${TEMP_DIR}/n8n_${BACKUP_DATE}.tar.gz" -C "$BACKUP_ROOT/n8n" .; then
    log "n8n backup completed"
    
    # Verify backup
    if verify_backup "${TEMP_DIR}/n8n_${BACKUP_DATE}.tar.gz" tar; then
        log "n8n backup verified"
        
        # Upload to S3
        log "Uploading n8n backup to S3..."
        aws s3 cp "${TEMP_DIR}/n8n_${BACKUP_DATE}.tar.gz" "${S3_BACKUP_PATH}/n8n/n8n_${BACKUP_DATE}.tar.gz"
        if [[ $? -ne 0 ]]; then
            error "Failed to upload n8n backup to S3"
        fi
    else
        error "n8n backup verification failed"
    fi
else
    error "n8n backup failed"
fi

# Backup Qdrant data
log "Backing up Qdrant data..."
if tar -czf "${TEMP_DIR}/qdrant_${BACKUP_DATE}.tar.gz" -C "$BACKUP_ROOT/qdrant" .; then
    log "Qdrant backup completed"
    
    # Verify backup
    if verify_backup "${TEMP_DIR}/qdrant_${BACKUP_DATE}.tar.gz" tar; then
        log "Qdrant backup verified"
        
        # Upload to S3
        log "Uploading Qdrant backup to S3..."
        aws s3 cp "${TEMP_DIR}/qdrant_${BACKUP_DATE}.tar.gz" "${S3_BACKUP_PATH}/qdrant/qdrant_${BACKUP_DATE}.tar.gz"
        if [[ $? -ne 0 ]]; then
            error "Failed to upload Qdrant backup to S3"
        fi
    else
        error "Qdrant backup verification failed"
    fi
else
    error "Qdrant backup failed"
fi

# Create a single archive containing all backups
log "Creating full backup archive..."
cd "${TEMP_DIR}"
if tar -czf "${TEMP_DIR}/full_backup_${BACKUP_DATE}.tar.gz" .; then
    log "Full backup archive created"
    
    # Upload to S3
    log "Uploading full backup archive to S3..."
    aws s3 cp "${TEMP_DIR}/full_backup_${BACKUP_DATE}.tar.gz" "s3://${S3_BUCKET_NAME}/backups/full_backup_${BACKUP_DATE}.tar.gz"
    if [[ $? -ne 0 ]]; then
        error "Failed to upload full backup archive to S3"
    fi
else
    error "Failed to create full backup archive"
fi

# Create backup manifest
log "Creating backup manifest..."
cat > "${TEMP_DIR}/manifest.json" << EOF
{
    "backup_id": "${BACKUP_DATE}",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "components": {
        "database": "db_${BACKUP_DATE}.sql",
        "n8n": "n8n_${BACKUP_DATE}.tar.gz",
        "qdrant": "qdrant_${BACKUP_DATE}.tar.gz"
    },
    "full_backup": "full_backup_${BACKUP_DATE}.tar.gz",
    "bucket": "${S3_BUCKET_NAME}",
    "backup_path": "backups/${BACKUP_DATE}",
    "retention_days": ${RETENTION_DAYS}
}
EOF

# Upload manifest
log "Uploading backup manifest..."
aws s3 cp "${TEMP_DIR}/manifest.json" "${S3_BACKUP_PATH}/manifest.json"
if [[ $? -ne 0 ]]; then
    error "Failed to upload backup manifest"
fi

# Create latest backup pointer
log "Updating latest backup pointer..."
aws s3 cp "${S3_BACKUP_PATH}/manifest.json" "s3://${S3_BUCKET_NAME}/backups/latest_backup_manifest.json"
if [[ $? -ne 0 ]]; then
    error "Failed to update latest backup pointer"
fi

# Cleanup temporary files
log "Cleaning up temporary files..."
rm -rf "${TEMP_DIR}"

# Clean up old backups
cleanup_old_backups

log "Backup process completed successfully"
log "Backup ID: ${BACKUP_DATE}"
log "Backup location: ${S3_BACKUP_PATH}"
