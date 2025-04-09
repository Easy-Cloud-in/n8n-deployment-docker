#!/bin/bash
source "$(dirname "$0")/common.sh"

# Configuration
DEFAULT_LOG_RETENTION_DAYS=30
DEFAULT_TEMP_RETENTION_DAYS=1
DEFAULT_BACKUP_RETENTION_DAYS=7

# Clean old logs
cleanup_logs() {
    local retention_days=${1:-$DEFAULT_LOG_RETENTION_DAYS}
    log "Cleaning logs older than $retention_days days..."
    
    find /opt/n8n-data -name "*.log" -mtime "+$retention_days" -type f -exec rm -f {} \;
    log "Log cleanup completed"
}

# Clean temporary files
cleanup_temp() {
    local retention_days=${1:-$DEFAULT_TEMP_RETENTION_DAYS}
    log "Cleaning temporary files older than $retention_days days..."
    
    find /opt/n8n-data -name "*.tmp" -mtime "+$retention_days" -type f -exec rm -f {} \;
    find /opt/n8n-data -name "*.temp" -mtime "+$retention_days" -type f -exec rm -f {} \;
    log "Temporary file cleanup completed"
}

# Clean old backups
cleanup_backups() {
    local retention_days=${1:-$DEFAULT_BACKUP_RETENTION_DAYS}
    log "Cleaning backups older than $retention_days days..."
    
    find /opt/n8n-data -name "backup_*" -mtime "+$retention_days" -exec rm -f {} \;
    find /opt/n8n-data -name "db_*.sql" -mtime "+$retention_days" -exec rm -f {} \;
    find /opt/n8n-data -name "n8n_*.tar.gz" -mtime "+$retention_days" -exec rm -f {} \;
    log "Backup cleanup completed"
}

# Check disk space and clean if needed
check_and_clean() {
    local threshold=${1:-90}  # Default threshold: 90%
    local usage=$(df -h /opt/n8n-data | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt "$threshold" ]; then
        warn "Disk usage is high ($usage%). Starting emergency cleanup..."
        cleanup_logs 15    # More aggressive cleanup
        cleanup_temp 0     # Clean all temp files
        cleanup_backups 3  # Keep only recent backups
    fi
}

# Show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --logs DAYS    Clean logs older than DAYS (default: $DEFAULT_LOG_RETENTION_DAYS)"
    echo "  --temp DAYS    Clean temp files older than DAYS (default: $DEFAULT_TEMP_RETENTION_DAYS)"
    echo "  --backups DAYS Clean backups older than DAYS (default: $DEFAULT_BACKUP_RETENTION_DAYS)"
    echo "  --check PCT    Check disk usage and clean if above PCT% (default: 90)"
    echo "  --all         Run all cleanups with default values"
    echo "Examples:"
    echo "  $0 --logs 15 --temp 1"
    echo "  $0 --check 85"
    echo "  $0 --all"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -eq 0 ]; then
        usage
        exit 1
    fi

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --logs)
                cleanup_logs "$2"
                shift 2
                ;;
            --temp)
                cleanup_temp "$2"
                shift 2
                ;;
            --backups)
                cleanup_backups "$2"
                shift 2
                ;;
            --check)
                check_and_clean "$2"
                shift 2
                ;;
            --all)
                cleanup_logs
                cleanup_temp
                cleanup_backups
                check_and_clean
                shift
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done
fi
