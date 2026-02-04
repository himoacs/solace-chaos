#!/bin/bash

# Load environment variables from .env file
ENV_FILE="$(dirname $0)/../.env"

if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | grep -v '^#' | xargs)
else
    echo "ERROR: .env file not found at $ENV_FILE"
    echo "Please run bootstrap-chaos-environment.sh first"
    exit 1
fi

# Validate critical variables are set
REQUIRED_VARS=(
    "SOLACE_BROKER_HOST"
    "SOLACE_BROKER_PORT"
    "SDKPERF_SCRIPT_PATH"
    "CHAOS_GENERATOR_USER"
    "CHAOS_GENERATOR_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done

# SEMP API configuration
SOLACE_SEMP_URL="http://${SOLACE_BROKER_HOST}:8080"

# SEMP API Helper Functions
get_queue_usage() {
    local queue_name="$1"
    local vpn_name="$2"
    
    if [ -z "$queue_name" ] || [ -z "$vpn_name" ]; then
        echo "0"
        return 1
    fi
    
    # Query SEMP API for queue usage percentage
    local response=$(curl -s -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        "${SOLACE_SEMP_URL}/SEMP/v2/monitor/msgVpns/${vpn_name}/queues/${queue_name}" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        # Parse quota usage percentage
        local usage=$(echo "$response" | grep -o '"quotaByteUtilizationPercentage":[0-9.]*' | cut -d':' -f2 | head -1)
        if [ ! -z "$usage" ]; then
            echo "${usage%.*}"  # Convert to integer
            return 0
        fi
    fi
    
    echo "0"
    return 1
}

check_queue_full() {
    local queue_name="$1"
    local vpn_name="$2"
    local threshold="${3:-85}"
    
    local usage=$(get_queue_usage "$queue_name" "$vpn_name")
    
    if [ "$usage" -ge "$threshold" ]; then
        return 0  # Queue is full
    else
        return 1  # Queue is not full
    fi
}

wait_for_queue_to_drain() {
    local queue_name="$1"
    local vpn_name="$2"
    local threshold="${3:-20}"
    local timeout="${4:-1800}"  # 30 minutes default
    
    echo "$(date): Waiting for queue ${queue_name} to drain below ${threshold}%..."
    
    local start_time=$(date +%s)
    while true; do
        local usage=$(get_queue_usage "$queue_name" "$vpn_name")
        
        if [ "$usage" -le "$threshold" ]; then
            echo "$(date): Queue drained to ${usage}% - continuing"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "$(date): Drain timeout after ${timeout}s - queue still at ${usage}%"
            return 1
        fi
        
        sleep 30
    done
}

check_resource_limits() {
    local max_connections="${1:-40}"
    
    # Count current SDKPerf connections using process counting
    local current_connections=$(pgrep -f "sdkperf_java" | wc -l | tr -d ' ')
    
    echo "Connection usage - Default: , Trading: , Total: ${current_connections}/${max_connections}"
    
    if [ "$current_connections" -ge "$max_connections" ]; then
        echo "$(date): Connection limit reached (${current_connections}/${max_connections})"
        return 1  # Limit exceeded
    else
        return 0  # Within limits
    fi
}

cleanup_sdkperf_processes() {
    local filter="${1:-}"
    
    echo "$(date): Cleaning up SDKPerf processes${filter:+ with filter: $filter}..."
    
    if [ -z "$filter" ]; then
        # Kill all SDKPerf processes
        pkill -f "sdkperf_java" 2>/dev/null || true
    else
        # Kill processes matching the filter pattern
        pkill -f "sdkperf_java.*${filter}" 2>/dev/null || true
    fi
    
    # Wait a moment for cleanup
    sleep 2
    
    # Force kill any remaining processes
    if [ -z "$filter" ]; then
        pkill -9 -f "sdkperf_java" 2>/dev/null || true
    else
        pkill -9 -f "sdkperf_java.*${filter}" 2>/dev/null || true
    fi
}

# Direct queue clearing using SEMP API (immediate and efficient)
clear_queue_messages() {
    local queue_name="$1"
    local vpn_name="$2"
    
    if [ -z "$queue_name" ] || [ -z "$vpn_name" ]; then
        echo "Usage: clear_queue_messages <queue_name> <vpn_name>"
        return 1
    fi
    
    echo "$(date): Clearing all messages from queue ${queue_name} in VPN ${vpn_name}..."
    
    # Use SEMP API action endpoint to delete all messages (correct method: PUT)
    local response=$(curl -X PUT \
        -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${SOLACE_SEMP_URL}/SEMP/v2/action/msgVpns/${vpn_name}/queues/${queue_name}/deleteMsgs" \
        -d "{}" \
        -s -w "%{http_code}")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" =~ ^(200|204)$ ]]; then
        echo "$(date): Successfully cleared queue ${queue_name}"
        sleep 2  # Brief pause for queue stats to update
        local new_usage=$(get_queue_usage "$queue_name" "$vpn_name")
        echo "$(date): Queue usage after clearing: ${new_usage}%"
        return 0
    else
        echo "$(date): Failed to clear queue ${queue_name} - HTTP ${http_code}"
        echo "Response: ${body}"
        echo "$(date): Falling back to consumer-based draining..."
        # Fallback to consumer-based clearing
        drain_queue_manually "$queue_name" "$vpn_name" "consumer"
        return 1
    fi
}

# Emergency queue drain function for manual queue clearing
drain_queue_manually() {
    local queue_name="$1"
    local vpn_name="$2"
    local method="${3:-api}"  # 'api' for immediate SEMP clearing, 'consumer' for drain with consumers
    
    if [ -z "$queue_name" ] || [ -z "$vpn_name" ]; then
        echo "Usage: drain_queue_manually <queue_name> <vpn_name> [method: api|consumer]"
        return 1
    fi
    
    local start_usage=$(get_queue_usage "$queue_name" "$vpn_name")
    echo "$(date): Queue ${queue_name} current usage: ${start_usage}%"
    
    if [ "$method" = "api" ]; then
        # Use direct SEMP API clearing (immediate)
        clear_queue_messages "$queue_name" "$vpn_name"
    else
        # Use consumer-based draining (slower but more realistic)
        local duration=300
        echo "$(date): Consumer-based drain started - ${queue_name} in ${vpn_name}"
        echo "$(date): Draining for ${duration} seconds..."
        
        # Start multiple consumers to aggressively drain the queue
        for i in {1..5}; do
            timeout ${duration}s bash "${SDKPERF_SCRIPT_PATH}" \
                -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
                -cu="${SOLACE_ADMIN_USER}" \
                -cp="${SOLACE_ADMIN_PASSWORD}" \
                -sql="${queue_name}" \
                -md > /dev/null 2>&1 &
        done
        
        # Monitor progress
        sleep $duration
        local end_usage=$(get_queue_usage "$queue_name" "$vpn_name")
        echo "$(date): Consumer drain completed - ${queue_name}: ${start_usage}% -> ${end_usage}%"
        
        # Clean up drain consumers
        pkill -f "$queue_name" 2>/dev/null || true
    fi
}
