#!/bin/bash
# config-parser.sh - Parse infrastructure definitions from .env
# This is the single source of truth for queue, user, and ACL configurations
#
# Note: Uses simple arrays for bash 3.2 compatibility (macOS default bash)
# Format: "key=value|key2=value2|..."

# Simple storage using indexed arrays (bash 3.2 compatible)
QUEUE_KEYS=()
QUEUE_VALUES=()
USER_KEYS=()
USER_VALUES=()
ACL_KEYS=()
ACL_VALUES=()

# Parse queue definitions
parse_queues() {
    local i=1
    while true; do
        local queue_var="QUEUE_${i}"
        local queue_def=$(eval echo \$${queue_var})
        [[ -z "$queue_def" ]] && break
        
        IFS=',' read -r name vpn quota access_type subscriptions <<< "$queue_def"
        QUEUE_KEYS+=("$name")
        QUEUE_VALUES+=("vpn=$vpn|quota=$quota|access_type=$access_type|subscriptions=$subscriptions")
        ((i++))
    done
}

# Parse user definitions
parse_users() {
    local i=1
    while true; do
        local user_var="USER_${i}"
        local user_def=$(eval echo \$${user_var})
        [[ -z "$user_def" ]] && break
        
        IFS=',' read -r role vpn password acl_profile client_profile <<< "$user_def"
        USER_KEYS+=("$role")
        USER_VALUES+=("vpn=$vpn|password=$password|acl_profile=$acl_profile|client_profile=$client_profile")
        ((i++))
    done
}

# Parse ACL profile definitions
parse_acl_profiles() {
    local i=1
    while true; do
        local acl_var="ACL_${i}"
        local acl_def=$(eval echo \$${acl_var})
        [[ -z "$acl_def" ]] && break
        
        IFS=',' read -r name vpn connect publish subscribe <<< "$acl_def"
        ACL_KEYS+=("$name")
        ACL_VALUES+=("vpn=$vpn|connect=$connect|publish=$publish|subscribe=$subscribe")
        ((i++))
    done
}

# Helper function to find index by key (bash 3.2 compatible)
_find_index() {
    local array_name=$1
    local search_key=$2
    local i=0
    
    # Use eval to access array by name (bash 3.2 compatible)
    eval "local keys_array=(\"\${${array_name}[@]}\")"
    
    for key in "${keys_array[@]}"; do
        [[ "$key" == "$search_key" ]] && echo $i && return 0
        ((i++))
    done
    return 1
}

# Helper function to extract value from pipe-delimited string (macOS compatible)
_extract_value() {
    local data=$1
    local key=$2
    # Use sed instead of grep -P for macOS compatibility
    echo "$data" | sed -n "s/.*${key}=\([^|]*\).*/\1/p"
}

# Get queue configuration
# Usage: get_queue_config "queue_name" "property"
get_queue_config() {
    local queue_name="$1"
    local property="$2"
    local idx=$(_find_index QUEUE_KEYS "$queue_name")
    
    [[ -z "$idx" ]] && return 1
    
    local config="${QUEUE_VALUES[$idx]}"
    _extract_value "$config" "$property"
}

# Get user configuration
# Usage: get_user_config "role" "property"
get_user_config() {
    local role="$1"
    local property="$2"
    local idx=$(_find_index USER_KEYS "$role")
    
    [[ -z "$idx" ]] && return 1
    
    local config="${USER_VALUES[$idx]}"
    _extract_value "$config" "$property"
}

# Get ACL profile configuration
# Usage: get_acl_config "profile_name" "property"
get_acl_config() {
    local profile_name="$1"
    local property="$2"
    local idx=$(_find_index ACL_KEYS "$profile_name")
    
    [[ -z "$idx" ]] && return 1
    
    local config="${ACL_VALUES[$idx]}"
    _extract_value "$config" "$property"
}

# List all queues
list_queues() {
    echo "${QUEUE_KEYS[@]}"
}

# List all users
list_users() {
    echo "${USER_KEYS[@]}"
}

# List all ACL profiles
list_acl_profiles() {
    echo "${ACL_KEYS[@]}"
}

# Get queues for a specific VPN
get_vpn_queues() {
    local vpn="$1"
    local result=()
    
    for queue_name in "${QUEUE_KEYS[@]}"; do
        local queue_vpn=$(get_queue_config "$queue_name" "vpn")
        if [[ "$queue_vpn" == "$vpn" ]]; then
            result+=("$queue_name")
        fi
    done
    
    echo "${result[@]}"
}

# Get users for a specific VPN
get_vpn_users() {
    local vpn="$1"
    local result=()
    
    for role in "${USER_KEYS[@]}"; do
        local user_vpn=$(get_user_config "$role" "vpn")
        if [[ "$user_vpn" == "$vpn" ]]; then
            result+=("$role")
        fi
    done
    
    echo "${result[@]}"
}

# Get ACL profiles for a specific VPN
get_vpn_acl_profiles() {
    local vpn="$1"
    local result=()
    
    for profile_name in "${ACL_KEYS[@]}"; do
        local profile_vpn=$(get_acl_config "$profile_name" "vpn")
        if [[ "$profile_vpn" == "$vpn" ]]; then
            result+=("$profile_name")
        fi
    done
    
    echo "${result[@]}"
}

# Validate infrastructure configuration
validate_config() {
    local errors=0
    
    # Check if any queues are defined
    if [[ ${#QUEUES[@]} -eq 0 ]]; then
        echo "ERROR: No queues defined. Add QUEUE_N variables to .env" >&2
        ((errors++))
    fi
    
    # Check if any users are defined
    if [[ ${#USERS[@]} -eq 0 ]]; then
        echo "ERROR: No users defined. Add USER_N variables to .env" >&2
        ((errors++))
    fi
    
    # Check if any ACL profiles are defined
    if [[ ${#ACL_PROFILES[@]} -eq 0 ]]; then
        echo "ERROR: No ACL profiles defined. Add ACL_N variables to .env" >&2
        ((errors++))
    fi
    
    # Validate queue properties
    for queue_name in "${!QUEUES[@]}"; do
        local vpn=$(get_queue_config "$queue_name" "vpn")
        local quota=$(get_queue_config "$queue_name" "quota")
        
        if [[ -z "$vpn" ]]; then
            echo "ERROR: Queue '$queue_name' missing VPN assignment" >&2
            ((errors++))
        fi
        
        if [[ -z "$quota" || ! "$quota" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Queue '$queue_name' has invalid quota: $quota" >&2
            ((errors++))
        fi
    done
    
    # Validate user properties
    for role in "${!USERS[@]}"; do
        local vpn=$(get_user_config "$role" "vpn")
        local password=$(get_user_config "$role" "password")
        local acl=$(get_user_config "$role" "acl_profile")
        
        if [[ -z "$vpn" ]]; then
            echo "ERROR: User '$role' missing VPN assignment" >&2
            ((errors++))
        fi
        
        if [[ -z "$password" ]]; then
            echo "ERROR: User '$role' missing password" >&2
            ((errors++))
        fi
        
        if [[ -z "$acl" ]]; then
            echo "ERROR: User '$role' missing ACL profile" >&2
            ((errors++))
        fi
    done
    
    return $errors
}

# Initialize - parse all configurations
init_config_parser() {
    parse_queues
    parse_users
    parse_acl_profiles
    
    # Enable verbose mode if requested
    if [[ "${CONFIG_PARSER_VERBOSE:-false}" == "true" ]]; then
        echo "Parsed ${#QUEUES[@]} queues, ${#USERS[@]} users, ${#ACL_PROFILES[@]} ACL profiles"
    fi
}

# Auto-initialize when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_config_parser
fi
