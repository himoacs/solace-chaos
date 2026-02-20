#!/bin/bash

# Load environment variables from .env file
ENV_FILE="$(dirname $0)/../.env"

if [ -f "$ENV_FILE" ]; then
    # Strip inline comments and empty lines before exporting
    export $(cat "$ENV_FILE" | grep -v '^#' | sed 's/#.*$//' | grep -v '^\s*$' | xargs)
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
    # Use eval for bash 3.2 compatibility instead of ${!var}
    value=$(eval echo \$$var)
    if [ -z "$value" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done

# SEMP API configuration
SOLACE_SEMP_URL="http://${SOLACE_BROKER_HOST}:8080"

# Broker Type Detection Function
detect_broker_type() {
    # Check if manual override is set
    if [ "$SOLACE_BROKER_TYPE" = "software" ] || [ "$SOLACE_BROKER_TYPE" = "appliance" ]; then
        echo "$SOLACE_BROKER_TYPE"
        return 0
    fi
    
    # Auto-detect via SEMP API (query /SEMP/v2/about endpoint)
    local response=$(curl -s -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        "${SOLACE_SEMP_URL}/SEMP/v2/about" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        # Check for platform field - appliances identify as "Appliance"
        local platform=$(echo "$response" | grep -o '"platform":"[^"]*"' | cut -d'"' -f4)
        
        if echo "$platform" | grep -iq "appliance"; then
            echo "appliance"
            return 0
        else
            echo "software"
            return 0
        fi
    fi
    
    # Fallback to software if detection fails
    echo "software"
    return 1
}

# Detect and export broker type
export DETECTED_BROKER_TYPE=$(detect_broker_type)

# SEMP API Helper Functions
get_queue_usage() {
    local queue_name="$1"
    local vpn_name="$2"
    
    if [ -z "$queue_name" ] || [ -z "$vpn_name" ]; then
        echo "0"
        return 1
    fi
    
    # Query SEMP API for queue usage using collections.msgs.count
    local response=$(curl -s -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
        "${SOLACE_SEMP_URL}/SEMP/v2/monitor/msgVpns/${vpn_name}/queues/${queue_name}" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        # Get collections.msgs.count (number of available message objects)
        local msg_count=$(echo "$response" | jq -r '.collections.msgs.count // 0')
        
        if [ ! -z "$msg_count" ] && [ "$msg_count" != "null" ]; then
            # Calculate percentage based on reasonable queue capacity (1000 messages = 100%)
            local usage_percent=$((msg_count * 100 / 1000))
            # Cap at 100%
            if [ $usage_percent -gt 100 ]; then
                usage_percent=100
            fi
            echo "$usage_percent"
            return 0
        fi
        
        # Fall back to spooledMsgCount if collections data not available
        local spooled_count=$(echo "$response" | grep -o '"spooledMsgCount":[0-9]*' | cut -d':' -f2 | head -1)
        if [ ! -z "$spooled_count" ] && [ "$spooled_count" != "null" ]; then
            # Estimate percentage: assume full at ~120K messages
            local estimated_percent=$((spooled_count * 100 / 120000))
            # Cap at 100%
            if [ $estimated_percent -gt 100 ]; then
                estimated_percent=100
            fi
            echo "$estimated_percent"
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

# Function to wait for process IDs to exit cleanly
wait_for_pids_to_exit() {
    local pids="$@"
    local max_wait=10
    local count=0
    
    for pid in $pids; do
        while kill -0 "$pid" 2>/dev/null && [ $count -lt $max_wait ]; do
            sleep 1
            count=$((count + 1))
        done
    done
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
