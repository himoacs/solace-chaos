#!/bin/bash
# SEMP Library - Reusable functions for Solace SEMP API v2 operations

# SEMP API base functions
semp_post() {
    local endpoint="$1"
    local payload="$2"
    local description="${3:-Creating resource}"
    
    local response=$(curl -X POST \
        -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${SOLACE_SEMP_URL}${endpoint}" \
        -d "$payload" \
        -s -w "\n%{http_code}")
    
    local body=$(echo "$response" | sed '$d')
    local http_code=$(echo "$response" | tail -n 1)
    
    # Check for success or "already exists" error
    if [[ "$http_code" =~ ^(200|201|204)$ ]]; then
        return 0
    elif [[ "$http_code" == "400" ]] && echo "$body" | grep -q "ALREADY_EXISTS"; then
        # Resource already exists - this is OK for idempotency
        return 0
    else
        echo "ERROR: $description failed (HTTP $http_code)" >&2
        echo "$body" | jq -r '.meta.error.description // .meta.error.status // "Unknown error"' 2>/dev/null || echo "$body" >&2
        return 1
    fi
}

semp_get() {
    local endpoint="$1"
    
    local response=$(curl -X GET \
        -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${SOLACE_SEMP_URL}${endpoint}" \
        -s -w "\n%{http_code}")
    
    local body=$(echo "$response" | sed '$d')
    local http_code=$(echo "$response" | tail -n 1)
    
    if [[ "$http_code" == "200" ]]; then
        echo "$body"
        return 0
    else
        return 1
    fi
}

semp_delete() {
    local endpoint="$1"
    local description="${2:-Deleting resource}"
    
    local response=$(curl -X DELETE \
        -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        "${SOLACE_SEMP_URL}${endpoint}" \
        -s -w "\n%{http_code}")
    
    local body=$(echo "$response" | sed '$d')
    local http_code=$(echo "$response" | tail -n 1)
    
    if [[ "$http_code" =~ ^(200|204)$ ]]; then
        return 0
    elif [[ "$http_code" == "404" ]]; then
        # Resource doesn't exist - this is OK for cleanup
        return 0
    else
        echo "ERROR: $description failed (HTTP $http_code)" >&2
        echo "$body" | jq -r '.meta.error.description // .meta.error.status // "Unknown error"' 2>/dev/null || echo "$body" >&2
        return 1
    fi
}

check_resource_exists() {
    local monitor_endpoint="$1"
    
    if semp_get "$monitor_endpoint" >/dev/null 2>&1; then
        return 0  # Exists
    else
        return 1  # Doesn't exist
    fi
}

url_encode() {
    local string="$1"
    echo "$string" | jq -sRr @uri
}

# Logging functions with colors
log_semp_step() {
    echo -e "\033[0;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

log_semp_success() {
    echo -e "\033[0;32m✅ $1\033[0m"
}

log_semp_error() {
    echo -e "\033[0;31m❌ $1\033[0m"
}

log_semp_warning() {
    echo -e "\033[1;33m⚠️  $1\033[0m"
}

# Wait for resource to be ready (some resources need time)
wait_for_resource() {
    local monitor_endpoint="$1"
    local max_wait="${2:-10}"
    local interval="${3:-1}"
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if check_resource_exists "$monitor_endpoint"; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    return 1
}
