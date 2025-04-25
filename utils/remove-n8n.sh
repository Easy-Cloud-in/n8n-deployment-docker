#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" || {
    echo "ERROR: Failed to source common.sh"
    exit 1
}

# Configuration
BASE_DIR="/opt/n8n-data"
DEPLOYMENT_DIRS=("local" "s3" "traefik")
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Check if .env file exists and load BASE_DIR from it
if [[ -f "$CONFIG_FILE" ]]; then
    debug "Loading BASE_DIR from $CONFIG_FILE"
    source "$CONFIG_FILE"
    debug "Using BASE_DIR: $BASE_DIR"
fi

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --all                 Remove everything (containers, images, volumes, networks, data, logs, cron jobs)"
    echo "  --containers          Remove only containers"
    echo "  --images              Remove n8n related images"
    echo "  --volumes             Remove volumes (requires confirmation)"
    echo "  --networks            Remove networks (requires confirmation)"
    echo "  --logs                Remove all logs"
    echo "  --data                Remove data directories (requires confirmation)"
    echo "  --cron                Remove n8n related cron jobs"
    echo "  --force               Skip all confirmations"
    echo "Example:"
    echo "  $0 --all              Remove everything (will ask for confirmation)"
    echo "  $0 --containers --images  Remove containers and images only"
    echo "  $0 --data --force     Remove data directories without confirmation"
    exit 1
}

# Function to check required commands
check_requirements() {
    debug "Checking required commands..."
    
    if ! command_exists docker; then
        error "docker is not installed. Please install docker first."
        exit 1
    fi
    
    if ! command_exists docker || ! docker compose version &>/dev/null; then
        warn "Docker or Docker Compose plugin is not installed. Some operations may fail."
    fi
}

# Function to remove containers
remove_containers() {
    log "Stopping and removing containers..."

    # Go to the compose file directory
    compose_dir="${SCRIPT_DIR}/.."
    if [ -f "${compose_dir}/docker-compose.yml" ]; then
        cd "${compose_dir}" || {
            error "Failed to change directory to ${compose_dir}"
            return 1 # Indicate failure
        }
        log "Stopping containers defined in docker-compose.yml..."
        docker compose down --remove-orphans # Use down to stop and remove
        handle_error $? "Failed to stop or remove containers using docker compose down"
        cd "${SCRIPT_DIR}" # Change back to original script dir
    else
        warn "docker-compose.yml not found in ${compose_dir}, attempting manual removal."
    fi

    # Fallback: Remove any remaining n8n related containers by pattern
    # Use a broader pattern to catch all related containers
    containers=$(docker ps -a --filter "name=n8n-" --format "{{.ID}}")
    if [ -n "$containers" ]; then
        log "Removing specific n8n-prefixed containers found..."
        docker rm -f $containers
        handle_error $? "Failed to remove some n8n-prefixed containers"
    else
        debug "No n8n-prefixed containers found for fallback removal."
    fi

    log "Container removal process finished."
}

# Function to remove images
remove_images() {
    log "Removing n8n related images..."

    # Images defined in docker-compose.yml (including pinned versions)
    images_to_remove=(
        "postgres:16-alpine"
        "n8nio/n8n:1.89.2"
        "qdrant/qdrant:v1.8.3"
        "traefik:v2.9"
        "amazon/aws-cli:2.17.11" # Base image for backup-scheduler
    )

    # Attempt to find the custom-built image name
    # Format is typically <directory_name>_<service_name>
    # Directory name might need adjustment if script is run from elsewhere
    compose_project_name=$(basename "${SCRIPT_DIR}/..")
    custom_backup_image_name="${compose_project_name}_backup-scheduler"
    # Docker compose V2 might use '-' instead of '_'
    custom_backup_image_name_alt="${compose_project_name}-backup-scheduler"

    # Add potential custom image names to the list
    images_to_remove+=("${custom_backup_image_name}" "${custom_backup_image_name_alt}")

    log "Attempting to remove the following images: ${images_to_remove[*]}"
    for image in "${images_to_remove[@]}"; do
        # Check if image exists before attempting removal
        if docker image inspect "$image" &> /dev/null; then
            docker rmi "$image"
            # Don't treat error as fatal, image might be in use by other containers
            if [ $? -ne 0 ]; then
                warn "Could not remove image '$image'. It might be in use or already removed."
            fi
        else
            debug "Image '$image' not found."
        fi
    done

    # Fallback: Also remove any dangling n8n images
    dangling_n8n_images=$(docker images --filter "dangling=true" --filter "reference=n8nio/n8n" --format "{{.ID}}")
    if [ -n "$dangling_n8n_images" ]; then
        log "Removing dangling n8nio/n8n images..."
        docker rmi -f $dangling_n8n_images
        # Optional: handle error if needed
    fi

    log "Image removal process finished."
}

# Function to remove volumes
remove_volumes() {
    if [[ "$FORCE" != "true" ]]; then
        read -p "Are you sure you want to remove all n8n volumes? This will delete all data! [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Volume removal cancelled"
            return
        fi
    fi
    
    log "Removing volumes..."
    volumes=$(docker volume ls | grep 'n8n-' | awk '{print $2}')
    if [ -n "$volumes" ]; then
        docker volume rm -f $volumes
        handle_error $? "Failed to remove some volumes"
    else
        debug "No n8n volumes found to remove"
    fi
    log "Volumes removed successfully"
}

# Function to remove networks
remove_networks() {
    if [[ "$FORCE" != "true" ]]; then
        read -p "Are you sure you want to remove the n8n networks (n8n-network, traefik-public)? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Network removal cancelled"
            return
        fi
    fi

    log "Removing networks (n8n-network, traefik-public)..."
    networks_to_remove=("n8n-network" "traefik-public")
    for network in "${networks_to_remove[@]}"; do
         # Check if network exists before attempting removal
        if docker network inspect "$network" &> /dev/null; then
            docker network rm "$network"
            if [ $? -ne 0 ]; then
                warn "Could not remove network '$network'. It might be in use or already removed."
            fi
        else
             debug "Network '$network' not found."
        fi
    done

    log "Network removal process finished."
}

# Function to remove logs
remove_logs() {
    log "Removing logs..."
    if [ -d "$BASE_DIR" ]; then
        safe_remove "${BASE_DIR}/*.log"
        handle_error $? "Failed to remove logs"
    else
        warn "Base directory $BASE_DIR does not exist, no logs to remove"
    fi
    log "Logs removed successfully"
}

# Function to remove data directories
remove_data() {
    if [[ "$FORCE" != "true" ]]; then
        read -p "Are you sure you want to remove the entire n8n base data directory (${BASE_DIR})? This cannot be undone! [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Data removal cancelled"
            return
        fi
    fi

    if [ ! -d "$BASE_DIR" ]; then
        warn "Base directory $BASE_DIR does not exist, no data to remove"
        return
    fi

    log "Removing base data directory: ${BASE_DIR}..."
    safe_remove "${BASE_DIR}"
    handle_error $? "Failed to remove base data directory ${BASE_DIR}"

    log "Base data directory removed successfully."
}

# Function to display the main menu
display_main_menu() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║       n8n Removal and Cleanup Tool         ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "Please select what you want to remove:"
    echo ""
    echo "1) Remove containers only"
    echo "2) Remove images only"
    echo "3) Remove volumes"
    echo "4) Remove networks"
    echo "5) Remove logs"
    echo "6) Remove base data directory (${BASE_DIR})"
    echo "8) Remove everything (complete cleanup)"
    echo "9) Help"
    echo "0) Exit"
    echo ""
    read -p "Enter your choice [0-9, excluding 7]: " main_choice
    
    case $main_choice in
        1) confirm_and_remove_containers ;;
        2) confirm_and_remove_images ;;
        3) confirm_and_remove_volumes ;;
        4) confirm_and_remove_networks ;;
        5) confirm_and_remove_logs ;;
        6) confirm_and_remove_data ;;
        8) confirm_and_remove_all ;;
        9) show_help_menu ;;
        0)
            echo "Exiting cleanup tool..."
            exit 0
            ;;
        *)
            echo "Invalid option. Press Enter to continue..."
            read
            display_main_menu
            ;;
    esac
}

# Function to show help menu
show_help_menu() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║                 Help Menu                  ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "n8n Removal and Cleanup Tool Help"
    echo ""
    echo "This tool helps you remove n8n components and clean up your system:"
    echo ""
    echo "1. Remove containers"
    echo "   - Stops and removes all n8n-related Docker containers using docker compose"
    echo "   - Does not affect your data or configuration"
    echo ""
    echo "2. Remove images"
    echo "   - Removes Docker images specified in docker-compose.yml and the custom built image"
    echo "   - Images can be re-downloaded when you run setup again"
    echo ""
    echo "3. Remove volumes"
    echo "   - Removes Docker volumes prefixed with 'n8n-' (e.g., n8n_storage, postgres_storage)"
    echo "   - WARNING: This will delete data stored ONLY in these Docker volumes"
    echo ""
    echo "4. Remove networks"
    echo "   - Removes Docker networks 'n8n-network' and 'traefik-public'"
    echo "   - Networks will be recreated when you run setup again"
    echo ""
    echo "5. Remove logs"
    echo "   - Deletes *.log files from the n8n base data directory (${BASE_DIR})"
    echo ""
    echo "6. Remove base data directory"
    echo "   - Deletes the entire base data directory: ${BASE_DIR}"
    echo "   - WARNING: This will permanently delete ALL persistent data (configs, db, etc.)"
    echo ""
    echo "8. Remove everything"
    echo "   - Performs a complete cleanup of all n8n components listed above"
    echo "   - WARNING: This will permanently delete all your n8n data and volumes"
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

# Wrapper functions for menu options with confirmation
confirm_and_remove_containers() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Remove Containers                ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "This will stop and remove all n8n-related Docker containers."
    echo "Your data will not be affected."
    echo ""
    read -p "Continue with container removal? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Nn] ]]; then
        remove_containers
        echo ""
        echo "Container removal completed."
    else
        echo ""
        echo "Operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

confirm_and_remove_images() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Remove Images                    ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "This will remove all Docker images used by n8n-related containers."
    echo "Images can be re-downloaded when you run setup again."
    echo ""
    read -p "Continue with image removal? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Nn] ]]; then
        remove_images
        echo ""
        echo "Image removal completed."
    else
        echo ""
        echo "Operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

confirm_and_remove_volumes() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Remove Volumes                   ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "⚠️  WARNING: This will delete all data stored in Docker volumes."
    echo "This operation cannot be undone."
    echo ""
    read -p "Are you sure you want to remove all n8n volumes? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        FORCE="true"  # Skip the confirmation in the remove_volumes function
        remove_volumes
        echo ""
        echo "Volume removal completed."
    else
        echo ""
        echo "Operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

confirm_and_remove_networks() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Remove Networks                  ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "This will remove all Docker networks created for n8n."
    echo "Networks will be recreated when you run setup again."
    echo ""
    read -p "Continue with network removal? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Nn] ]]; then
        FORCE="true"  # Skip the confirmation in the remove_networks function
        remove_networks
        echo ""
        echo "Network removal completed."
    else
        echo ""
        echo "Operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

confirm_and_remove_logs() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Remove Logs                      ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "This will delete all log files from the n8n data directory."
    echo ""
    read -p "Continue with log removal? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Nn] ]]; then
        remove_logs
        echo ""
        echo "Log removal completed."
    else
        echo ""
        echo "Operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

confirm_and_remove_data() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Remove Data Directories          ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "⚠️  WARNING: This will permanently delete all your n8n data."
    echo "Data directory: $BASE_DIR"
    echo "This operation cannot be undone."
    echo ""
    read -p "Are you sure you want to remove all n8n data directories? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        FORCE="true"  # Skip the confirmation in the remove_data function
        remove_data
        echo ""
        echo "Data directory removal completed."
    else
        echo ""
        echo "Operation cancelled."
    fi
    
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
}

confirm_and_remove_all() {
    clear
    echo "╔════════════════════════════════════════════╗"
    echo "║           Complete Cleanup                 ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "⚠️  WARNING: This will perform a complete cleanup of all n8n components:"
    echo "- Stop and remove all containers"
    echo "- Remove all related Docker images"
    echo "- Remove all Docker volumes"
    echo "- Remove all Docker networks"
    echo "- Delete all log files in ${BASE_DIR}"
    echo "- Delete the entire base data directory ${BASE_DIR}"
    echo ""
    echo "This operation cannot be undone and will result in complete data loss."
    echo ""
    read -p "Are you sure you want to perform a complete cleanup? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        FORCE="true"  # Skip all confirmations in the removal functions
        
        remove_containers
        remove_images
        remove_volumes
        remove_networks
        remove_logs
        remove_data
        echo ""
        echo "Complete cleanup finished successfully."
        echo ""
        echo "Press Enter to return to the main menu..."
        read
        display_main_menu
    else
        echo ""
        echo "Operation cancelled."
        echo ""
        echo "Press Enter to return to the main menu..."
        read
        display_main_menu
    fi
}

# Main execution
if [ "$EUID" -ne 0 ]; then
    error "Please run as root"
    exit 1
fi

# Check requirements
check_requirements

# If no arguments provided, show interactive menu
if [ "$#" -eq 0 ]; then
    display_main_menu
    exit 0
fi

# Initialize variables
FORCE="false"
ALL="false"
CONTAINERS="false"
IMAGES="false"
VOLUMES="false"
NETWORKS="false"
LOGS="false"
DATA="false"

# Check requirements
check_requirements

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --all)
            ALL="true"
            shift
            ;;
        --containers)
            CONTAINERS="true"
            shift
            ;;
        --images)
            IMAGES="true"
            shift
            ;;
        --volumes)
            VOLUMES="true"
            shift
            ;;
        --networks)
            NETWORKS="true"
            shift
            ;;
        --logs)
            LOGS="true"
            shift
            ;;
        --data)
            DATA="true"
            shift
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [ "$ALL" = "true" ]; then
    if [[ "$FORCE" != "true" ]]; then
        read -p "Are you sure you want to remove everything related to n8n? This cannot be undone! [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Removal cancelled"
            exit 0
        fi
    fi
    
    remove_containers
    remove_images
    remove_volumes
    remove_networks
    remove_logs
    remove_data
    echo ""
    echo "Complete cleanup finished successfully."
    echo ""
    echo "Press Enter to return to the main menu..."
    read
    display_main_menu
else
    [ "$CONTAINERS" = "true" ] && remove_containers
    [ "$IMAGES" = "true" ] && remove_images
    [ "$VOLUMES" = "true" ] && remove_volumes
    [ "$NETWORKS" = "true" ] && remove_networks
    [ "$LOGS" = "true" ] && remove_logs
    [ "$DATA" = "true" ] && remove_data
fi
log "n8n cleanup completed successfully"

# Display a friendly completion message if not in interactive mode
if [ "$#" -gt 0 ]; then
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║       n8n Cleanup Completed                ║"
    echo "║                                            ║"
    echo "║  All requested operations were successful  ║"
    echo "╚════════════════════════════════════════════╝"
fi
log "n8n cleanup completed successfully"