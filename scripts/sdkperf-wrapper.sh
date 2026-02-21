#!/bin/bash
# sdkperf-wrapper.sh - Centralized SDKPerf connection management
# Eliminates repetitive connection patterns across generator scripts

# Source required dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load-env.sh"
source "${SCRIPT_DIR}/config-parser.sh"

# Build base SDKPerf connection string for a user role
# Usage: sdkperf_base_connection "role_name"
# Returns: Base connection arguments for SDKPerf
sdkperf_base_connection() {
    local role="$1"
    
    # Get user configuration from config parser
    local vpn=$(get_user_config "$role" "vpn")
    local password=$(get_user_config "$role" "password")
    
    if [[ -z "$vpn" || -z "$password" ]]; then
        echo "ERROR: User role '$role' not found in configuration" >&2
        return 1
    fi
    
    # Construct username in format role@vpn
    local username="${role}@${vpn}"
    
    # Return base connection string (without -sql to avoid unwanted subscriptions)
    echo "-cip=${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT} -cu=${username} -cp=${password}"
}

# Execute SDKPerf publisher with standard connection
# Usage: sdkperf_publish -user "role" -topics "topic/path" -rate 1000 [additional_args...]
sdkperf_publish() {
    local user_role=""
    local topics=""
    local rate=""
    local additional_args=()
    
    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -user)
                user_role="$2"
                shift 2
                ;;
            -topics)
                topics="$2"
                shift 2
                ;;
            -rate)
                rate="$2"
                shift 2
                ;;
            *)
                additional_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$user_role" ]]; then
        echo "ERROR: -user parameter required" >&2
        return 1
    fi
    
    # Get base connection
    local base_conn=$(sdkperf_base_connection "$user_role")
    [[ $? -ne 0 ]] && return 1
    
    # Build command
    local cmd="${SDKPERF_SCRIPT_PATH} ${base_conn}"
    
    [[ -n "$topics" ]] && cmd+=" -mt=persistent -mn=999999999 -mr=999999999 -pql=100"
    [[ -n "$topics" ]] && cmd+=" -mt=persistent -ptl=${topics}"
    [[ -n "$rate" ]] && cmd+=" -mr=${rate}"
    
    # Add additional arguments
    for arg in "${additional_args[@]}"; do
        cmd+=" ${arg}"
    done
    
    # Execute command
    eval "$cmd"
}

# Execute SDKPerf subscriber with standard connection
# Usage: sdkperf_subscribe -user "role" -queue "queue_name" [additional_args...]
sdkperf_subscribe() {
    local user_role=""
    local queue=""
    local additional_args=()
    
    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -user)
                user_role="$2"
                shift 2
                ;;
            -queue)
                queue="$2"
                shift 2
                ;;
            *)
                additional_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$user_role" ]]; then
        echo "ERROR: -user parameter required" >&2
        return 1
    fi
    
    # Get base connection
    local base_conn=$(sdkperf_base_connection "$user_role")
    [[ $? -ne 0 ]] && return 1
    
    # Build command
    local cmd="${SDKPERF_SCRIPT_PATH} ${base_conn}"
    
    [[ -n "$queue" ]] && cmd+=" -pql=${queue}"
    
    # Add additional arguments
    for arg in "${additional_args[@]}"; do
        cmd+=" ${arg}"
    done
    
    # Execute command
    eval "$cmd"
}

# Execute raw SDKPerf command with auto-injected connection
# Usage: sdkperf_exec -user "role" [raw_sdkperf_args...]
sdkperf_exec() {
    local user_role=""
    local additional_args=()
    
    # Parse user role
    if [[ "$1" == "-user" ]]; then
        user_role="$2"
        shift 2
    else
        echo "ERROR: First parameter must be -user" >&2
        return 1
    fi
    
    # Get base connection
    local base_conn=$(sdkperf_base_connection "$user_role")
    [[ $? -ne 0 ]] && return 1
    
    # Execute with all remaining arguments
    ${SDKPERF_SCRIPT_PATH} ${base_conn} "$@"
}

# Get SDKPerf connection string for use in existing scripts
# Usage: conn=$(sdkperf_get_connection "role")
sdkperf_get_connection() {
    local role="$1"
    sdkperf_base_connection "$role"
}

# Validate SDKPerf is available
validate_sdkperf() {
    if [[ ! -f "$SDKPERF_SCRIPT_PATH" ]]; then
        echo "ERROR: SDKPerf not found at: $SDKPERF_SCRIPT_PATH" >&2
        echo "Run bootstrap script or download SDKPerf to sdkperf-tools/" >&2
        return 1
    fi
    
    if [[ ! -x "$SDKPERF_SCRIPT_PATH" ]]; then
        echo "ERROR: SDKPerf script is not executable: $SDKPERF_SCRIPT_PATH" >&2
        return 1
    fi
    
    return 0
}

# Get username for a role (format: role@vpn)
# Usage: username=$(sdkperf_get_username "role")
sdkperf_get_username() {
    local role="$1"
    local vpn=$(get_user_config "$role" "vpn")
    
    if [[ -z "$vpn" ]]; then
        echo "ERROR: User role '$role' not found" >&2
        return 1
    fi
    
    echo "${role}@${vpn}"
}

# Get password for a role
# Usage: password=$(sdkperf_get_password "role")
sdkperf_get_password() {
    local role="$1"
    get_user_config "$role" "password"
}

# Export functions for use in other scripts
export -f sdkperf_base_connection
export -f sdkperf_publish
export -f sdkperf_subscribe
export -f sdkperf_exec
export -f sdkperf_get_connection
export -f validate_sdkperf
export -f sdkperf_get_username
export -f sdkperf_get_password
