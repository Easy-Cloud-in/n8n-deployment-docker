#!/bin/bash

# Common utilities for n8n deployment scripts
# This script provides standardized error handling, logging, and utility functions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/opt/n8n-data/deployment.log"

# Function to log messages
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

# Function to log warnings
warn() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "${YELLOW}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

# Function to log errors
error() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "${RED}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

# Function to log debug information
debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        local message="[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1"
        echo -e "${BLUE}${message}${NC}"
        echo "$message" >> "$LOG_FILE"
    fi
}

# Function to handle errors
handle_error() {
    local exit_code=$1
    local error_message=$2
    local cleanup_function=$3
    
    if [[ $exit_code -ne 0 ]]; then
        error "$error_message (Exit code: $exit_code)"
        
        # Run cleanup function if provided
        if [[ -n "$cleanup_function" && $(type -t "$cleanup_function") == "function" ]]; then
            debug "Running cleanup function: $cleanup_function"
            $cleanup_function
        fi
        
        exit $exit_code
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to check if a service is running
service_running() {
    local container_name=$1
    docker ps | grep -q "$container_name"
    return $?
}

# Function to create directory safely
create_directory_safe() {
    local dir=$1
    local owner=${2:-1000:1000}  # Default to n8n user
    local permissions=${3:-755}
    
    if [[ ! -d "$dir" ]]; then
        debug "Creating directory: $dir"
        mkdir -p "$dir"
        handle_error $? "Failed to create directory: $dir"
    else
        debug "Directory exists: $dir"
    fi
    
    chown -R "$owner" "$dir"
    handle_error $? "Failed to set ownership on directory: $dir"
    
    chmod -R "$permissions" "$dir"
    handle_error $? "Failed to set permissions on directory: $dir"
}

# Function to safely remove files/directories
safe_remove() {
    local path=$1
    
    # Don't allow removing critical paths
    if [[ "$path" == "/" || "$path" == "/home" || "$path" == "/opt" || "$path" == "/etc" ]]; then
        error "Refusing to remove critical system path: $path"
        return 1
    fi
    
    # Don't allow wildcards directly at the root of important directories
    if [[ "$path" =~ ^/opt/n8n-data/[^/]*\*$ ]]; then
        error "Refusing to remove with dangerous wildcard: $path"
        return 1
    fi
    
    # If path exists, remove it
    if [[ -e "$path" ]]; then
        debug "Removing: $path"
        rm -rf "$path"
        handle_error $? "Failed to remove: $path"
    else
        debug "Path does not exist, nothing to remove: $path"
    fi
}

# Function to validate path safety
validate_path() {
    local path=$1
    
    # Check for path traversal attempts
    if [[ "$path" == *".."* ]]; then
        error "Path contains directory traversal sequences: $path"
        return 1
    fi
    
    # Check for absolute paths when relative is expected
    if [[ "$path" == /* && "$2" == "relative" ]]; then
        error "Expected relative path but got absolute path: $path"
        return 1
    fi
    
    return 0
}

# Function to validate backup ID format
validate_backup_id() {
    local backup_id=$1
    
    # Check if backup ID matches expected format (YYYYMMDD_HHMMSS)
    if ! [[ $backup_id =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        error "Invalid backup ID format: $backup_id. Expected format: YYYYMMDD_HHMMSS"
        return 1
    fi
    
    return 0
}

# Function to validate environment variables
validate_environment() {
    local env_file=$1
    local required_vars=("${@:2}")
    local missing_vars=()
    
    # Check if environment file exists
    if [[ ! -f "$env_file" ]]; then
        error "Environment file not found: $env_file"
        return 1
    fi
    
    # Source the environment file
    source "$env_file"
    
    # Check for required variables
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    # Report missing variables
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

# Function to validate password strength
validate_password() {
    local password=$1
    local min_length=16
    
    if [[ ${#password} -lt $min_length ]]; then
        return 1
    fi
    
    # Check for at least one uppercase, lowercase, digit, and special character
    if ! [[ $password =~ [A-Z] && $password =~ [a-z] && $password =~ [0-9] && $password =~ [^A-Za-z0-9] ]]; then
        return 1
    fi
    
    return 0
}

# Function to check disk space
check_disk_space() {
    local required_space=$1  # in MB
    local path=${2:-"/opt/n8n-data"}
    local available_space=$(df -m "$path" | awk 'NR==2 {print $4}')
    
    if [[ $available_space -lt $required_space ]]; then
        error "Insufficient disk space at $path. Required: ${required_space}MB, Available: ${available_space}MB"
        return 1
    fi
    
    return 0
}

# Function to estimate backup size
estimate_backup_size() {
    local backup_root=${1:-"/opt/n8n-data"}
    local n8n_size=$(du -sm "$backup_root/n8n" 2>/dev/null | awk '{print $1}')
    local postgres_size=$(du -sm "$backup_root/postgres" 2>/dev/null | awk '{print $1}')
    local qdrant_size=$(du -sm "$backup_root/qdrant" 2>/dev/null | awk '{print $1}')
    
    # Default to minimum sizes if directories don't exist yet
    n8n_size=${n8n_size:-100}
    postgres_size=${postgres_size:-100}
    qdrant_size=${qdrant_size:-100}
    
    # Add 20% overhead for compression and temporary files
    local total_size=$(( (n8n_size + postgres_size + qdrant_size) * 120 / 100 ))
    echo $total_size
}

# Add timeout wrapper function
execute_with_timeout() {
    local cmd="$1"
    local timeout="${2:-300}"  # Default 5 minutes
    
    timeout "$timeout" bash -c "$cmd"
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        error "Command timed out after ${timeout} seconds: $cmd"
        return 124
    fi
    return $exit_code
}

# Initialize log file directory if it doesn't exist
init_logging() {
    local log_dir=$(dirname "$LOG_FILE")
    
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
        if [[ $? -ne 0 ]]; then
            echo "ERROR: Failed to create log directory: $log_dir"
            echo "Logging will be disabled"
            LOG_FILE="/dev/null"
        fi
    fi
}

# Call init_logging to ensure log directory exists
init_logging
# Test comment
