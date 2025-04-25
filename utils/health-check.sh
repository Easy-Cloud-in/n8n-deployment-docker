#!/bin/bash
source "$(dirname "$0")/common.sh"

check_container_health() {
    local container="$1"
    local status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
    
    if [[ "$status" != "running" ]]; then
        error "Container $container is not running (status: $status)"
        return 1
    fi
    return 0
}

# Check all services
for service in n8n postgres qdrant; do
    check_container_health "n8n-$service"
done

# Check disk space
check_disk_space 1000  # Require 1GB free

# Check backup status
check_recent_backup() {
    find "${BASE_DIR}" -name "backup_*.log" -mtime -1 | grep -q .
    if [ $? -ne 0 ]; then
        error "No recent backup found in the last 24 hours"
        return 1
    fi
    return 0
}
