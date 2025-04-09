#!/bin/bash
source "$(dirname "$0")/common.sh"

# Default values
CI_MODE=false

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ci)
                CI_MODE=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Test database connection
test_database() {
    if [ "$CI_MODE" = true ]; then
        log "Skipping database test in CI mode"
        return 0
    fi
    
    docker exec n8n-postgres pg_isready -U n8n
    return $?
}

# Test n8n API
test_n8n_api() {
    if [ "$CI_MODE" = true ]; then
        log "Skipping n8n API test in CI mode"
        return 0
    fi
    
    curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz
    return $?
}

# Test Qdrant connection
test_qdrant() {
    if [ "$CI_MODE" = true ]; then
        log "Skipping Qdrant test in CI mode"
        return 0
    fi
    
    curl -s -o /dev/null -w "%{http_code}" http://localhost:6333/health
    return $?
}

# Test backup system
test_backup_system() {
    if [ "$CI_MODE" = true ]; then
        log "Skipping backup system test in CI mode"
        return 0
    fi
    
    # Check if recent backup exists (within last 24h)
    find "/opt/n8n-data" -name "backup_*.log" -mtime -1 | grep -q .
    return $?
}

# Test script syntax
test_script_syntax() {
    local failed=0
    
    log "Testing shell script syntax..."
    
    # Test shell scripts in utils directory
    for script in $(find "$(dirname "$0")" -name "*.sh"); do
        log "Checking syntax for $script"
        bash -n "$script" || failed=1
    done
    
    # Test shell scripts in local directory
    if [ -d "$(dirname "$0")/../local" ]; then
        for script in $(find "$(dirname "$0")/../local" -name "*.sh"); do
            log "Checking syntax for $script"
            bash -n "$script" || failed=1
        done
    fi
    
    # Test shell scripts in s3 directory
    if [ -d "$(dirname "$0")/../s3" ]; then
        for script in $(find "$(dirname "$0")/../s3" -name "*.sh"); do
            log "Checking syntax for $script"
            bash -n "$script" || failed=1
        done
    fi
    
    # Test shell scripts in traefik directory
    if [ -d "$(dirname "$0")/../traefik" ]; then
        for script in $(find "$(dirname "$0")/../traefik" -name "*.sh"); do
            log "Checking syntax for $script"
            bash -n "$script" || failed=1
        done
    fi
    
    return $failed
}

# Test YAML syntax
test_yaml_syntax() {
    local failed=0
    
    log "Testing YAML syntax..."
    
    # Check if yamllint is available
    if command -v yamllint >/dev/null 2>&1; then
        # Test YAML files
        for yaml_file in $(find "$(dirname "$0")/.." -name "*.yml" -o -name "*.yaml"); do
            log "Checking syntax for $yaml_file"
            yamllint -d relaxed "$yaml_file" || failed=1
        done
    else
        log "yamllint not found, skipping YAML syntax check"
    fi
    
    return $failed
}

# Run all tests
run_tests() {
    local failed=0
    
    # Always run script syntax tests
    test_script_syntax || failed=1
    
    # Always run YAML syntax tests
    test_yaml_syntax || failed=1
    
    # Run deployment tests if not in CI mode
    if [ "$CI_MODE" = false ]; then
        log "Testing PostgreSQL connection..."
        test_database || failed=1
        
        log "Testing n8n API..."
        test_n8n_api || failed=1
        
        log "Testing Qdrant connection..."
        test_qdrant || failed=1
        
        log "Testing backup system..."
        test_backup_system || failed=1
    else
        log "Running in CI mode, skipping deployment tests"
    fi
    
    return $failed
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    
    run_tests
    if [ $? -eq 0 ]; then
        log "All tests passed successfully!"
        exit 0
    else
        error "Some tests failed. Please check the logs."
        exit 1
    fi
fi
