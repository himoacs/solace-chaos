#!/bin/bash
# chaos-generator.sh - Unified parameterized chaos/error generator
# Supports multiple chaos scenarios: queue-killer, acl-violation, connection-storm, bridge-stress

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/load-env.sh"
source "${SCRIPT_DIR}/../scripts/sdkperf-wrapper.sh"

# Usage information
usage() {
    cat <<EOF
Usage: $0 --scenario <scenario> [options]

Chaos Scenarios:
  queue-killer       Fill queue with burst traffic, then drain slowly
  acl-violation      Test ACL profile violations across VPNs
  connection-storm   Create connection limit stress
  bridge-stress      Stress test cross-VPN bridges

Queue Killer Options:
  --target-queue NAME   Queue to fill (default: equity_order_queue)
  --burst-duration SEC  Duration of burst in seconds (default: 10)
  --inter-burst SEC     Inter-burst gap duration in seconds (default: 30)
  --message-size BYTES  Message size in bytes (default: 5000)
  --cycle-interval SEC  Restart interval (default: from .env)

ACL Violation Options:
  --test-user ROLE      User role to test (default: restricted-market)
  --violation-rate NUM  Attempts per second (default: 0.0002778, ~1/hour)

Connection Storm Options:
  --connection-count NUM Max concurrent connections (default: 25)
  --storm-duration SEC   Duration of storm (default: 600)

Bridge Stress Options:
  --attack-duration SEC  Duration of attack (default: from .env)
  --sleep-interval SEC   Sleep between attacks (default: from .env)

Common Options:
  --scenario SCENARIO   Chaos scenario (required)
  --log-file PATH       Log file path (default: logs/<scenario>-chaos.log)
  --help                Show this help message

Examples:
  $0 --scenario queue-killer
  $0 --scenario queue-killer --target-queue baseline_queue --burst-duration 20 --inter-burst 60
  $0 --scenario acl-violation --test-user restricted-trade
  $0 --scenario connection-storm --connection-count 50
EOF
    exit 1
}

# Parse command line arguments
SCENARIO=""
TARGET_QUEUE="equity_order_queue"
BURST_DURATION="10"
INTER_BURST_DURATION="30"
MESSAGE_SIZE="5000"
CYCLE_INTERVAL=""
TEST_USER="restricted-market"
VIOLATION_RATE="0.0002778"
CONNECTION_COUNT="25"
STORM_DURATION="600"
ATTACK_DURATION=""
SLEEP_INTERVAL=""
LOG_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scenario)
            SCENARIO="$2"
            shift 2
            ;;
        --target-queue)
            TARGET_QUEUE="$2"
            shift 2
            ;;
        --burst-duration)
            BURST_DURATION="$2"
            shift 2
            ;;
        --inter-burst)
            INTER_BURST_DURATION="$2"
            shift 2
            ;;
        --message-size)
            MESSAGE_SIZE="$2"
            shift 2
            ;;
        --cycle-interval)
            CYCLE_INTERVAL="$2"
            shift 2
            ;;
        --test-user)
            TEST_USER="$2"
            shift 2
            ;;
        --violation-rate)
            VIOLATION_RATE="$2"
            shift 2
            ;;
        --connection-count)
            CONNECTION_COUNT="$2"
            shift 2
            ;;
        --storm-duration)
            STORM_DURATION="$2"
            shift 2
            ;;
        --attack-duration)
            ATTACK_DURATION="$2"
            shift 2
            ;;
        --sleep-interval)
            SLEEP_INTERVAL="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$SCENARIO" ]]; then
    echo "ERROR: --scenario is required"
    usage
fi

# Set defaults from .env if not overridden
[[ -z "$CYCLE_INTERVAL" ]] && CYCLE_INTERVAL="${QUEUE_KILLER_CYCLE_INTERVAL:-3600}"
[[ -z "$ATTACK_DURATION" ]] && ATTACK_DURATION="${BRIDGE_ATTACK_DURATION:-600}"
[[ -z "$SLEEP_INTERVAL" ]] && SLEEP_INTERVAL="${BRIDGE_SLEEP_INTERVAL:-3600}"
[[ -z "$LOG_FILE" ]] && LOG_FILE="logs/${SCENARIO}-chaos.log"

# Queue killer scenario
scenario_queue_killer() {
    chaos_log "chaos-generator" "Starting queue-killer scenario (queue: ${TARGET_QUEUE})"
    chaos_log "chaos-generator" "Parameters: burst_duration=${BURST_DURATION}s, inter_burst=${INTER_BURST_DURATION}s, size=${MESSAGE_SIZE}B"
    
    # Get queue VPN
    local target_vpn=$(get_queue_config "$TARGET_QUEUE" "vpn")
    if [[ -z "$target_vpn" ]]; then
        chaos_log "chaos-generator" "ERROR: Queue $TARGET_QUEUE not found in configuration"
        return 1
    fi
    
    while true; do
        chaos_log "chaos-generator" "Queue killer cycle starting"
        
        # Burst publisher using chaos-generator user
        local pub_conn=$(sdkperf_get_connection "chaos-generator")
        
        ${SDKPERF_SCRIPT_PATH} ${pub_conn} \
            -ptl="trading/orders/equities/NYSE/new" \
            -mt=persistent \
            -mr=10000 \
            -bd="${BURST_DURATION}" \
            -ibd="${INTER_BURST_DURATION}" \
            -msa="${MESSAGE_SIZE}" \
            -mn=999999999999999999 \
            -q > /dev/null 2>&1 &
        
        local burst_pid=$!
        echo "$burst_pid" > "logs/pids/queue-killer-burst.pid"
        
        # Drain consumer
        local drain_conn=$(sdkperf_get_connection "order-router")
        
        ${SDKPERF_SCRIPT_PATH} ${drain_conn} \
            -sql="${TARGET_QUEUE}" \
            -q > /dev/null 2>&1 &
        
        local drain_pid=$!
        echo "$drain_pid" > "logs/pids/queue-killer-drain.pid"
        
        chaos_log "chaos-generator" "Queue killer active (burst: $burst_pid, drain: $drain_pid)"
        
        # Run for cycle duration
        sleep "$CYCLE_INTERVAL"
        
        # SYNCHRONOUS cleanup
        chaos_log "chaos-generator" "Stopping queue-killer SDKPerf processes..."
        kill -9 "$burst_pid" "$drain_pid" 2>/dev/null || true
        pkill -9 -f "chaos-generator.*ptl=trading" 2>/dev/null || true
        pkill -9 -f "order-router.*sql=${TARGET_QUEUE}" 2>/dev/null || true
        
        # Verify dead
        for i in {1..5}; do
            if ! pgrep -f "chaos-generator.*trading" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        
        chaos_log "chaos-generator" "Queue killer cycle completed - restarting"
    done
}

# ACL violation scenario
scenario_acl_violation() {
    chaos_log "chaos-generator" "Starting ACL violation scenario (user: ${TEST_USER})"
    
    local user_conn=$(sdkperf_get_connection "$TEST_USER")
    
    while true; do
        chaos_log "chaos-generator" "ACL violation test cycle starting"
        
        # Test multiple ACL violations with publisher flows
        ${SDKPERF_SCRIPT_PATH} ${user_conn} \
            -ptl="market-data/premium/level3/NYSE/AAPL,trading/admin/cancel-all-orders,trading/orders/equities/NYSE/new" \
            -pfl=3 \
            -mr="${VIOLATION_RATE}" \
            -mn=999999999999999999 \
            -msa=256 \
            -q > /dev/null 2>&1 &
        
        local acl_pid=$!
        echo "$acl_pid" > "logs/pids/acl-violation.pid"
        
        # Run for 1 hour
        sleep 3600
        
        # SYNCHRONOUS cleanup
        chaos_log "chaos-generator" "Stopping ACL violation SDKPerf processes..."
        kill -9 "$acl_pid" 2>/dev/null || true
        pkill -9 -f "${TEST_USER}" 2>/dev/null || true
        
        # Verify dead
        for i in {1..5}; do
            if ! pgrep -f "${TEST_USER}" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        
        chaos_log "chaos-generator" "ACL violation cycle completed - restarting"
    done
}

# Connection storm scenario
scenario_connection_storm() {
    chaos_log "chaos-generator" "Starting connection storm scenario (count: ${CONNECTION_COUNT})"
    
    local user_conn=$(sdkperf_get_connection "market-consumer")
    
    while true; do
        chaos_log "chaos-generator" "Connection storm starting - ${CONNECTION_COUNT} connections"
        
        # Create connection storm using multiple flows
        ${SDKPERF_SCRIPT_PATH} ${user_conn} \
            -stl="market-data/equities/quotes/>" \
            -cfl="${CONNECTION_COUNT}" \
            -mr=1 \
            -mn=999999999999999999 \
            -q > /dev/null 2>&1 &
        
        local storm_pid=$!
        echo "$storm_pid" > "logs/pids/connection-storm.pid"
        
        # Run for storm duration
        sleep "$STORM_DURATION"
        
        # SYNCHRONOUS cleanup
        chaos_log "chaos-generator" "Stopping connection storm SDKPerf processes..."
        kill -9 "$storm_pid" 2>/dev/null || true
        pkill -9 -f "market-consumer" 2>/dev/null || true
        
        # Verify dead
        for i in {1..5}; do
            if ! pgrep -f "market-consumer" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        
        chaos_log "chaos-generator" "Connection storm completed - cooling down"
        sleep 300  # 5 minute cooldown
    done
}

# Bridge stress scenario
scenario_bridge_stress() {
    if [[ "${ENABLE_CROSS_VPN_BRIDGE}" != "true" ]]; then
        chaos_log "chaos-generator" "ERROR: Cross-VPN bridge is disabled"
        return 1
    fi
    
    chaos_log "chaos-generator" "Starting bridge stress scenario"
    chaos_log "chaos-generator" "Attack: ${ATTACK_DURATION}s, Sleep: ${SLEEP_INTERVAL}s"
    
    local pub_conn=$(sdkperf_get_connection "market-feed")
    
    while true; do
        chaos_log "chaos-generator" "Bridge stress attack starting"
        
        # Heavy publishing to bridge topics
        ${SDKPERF_SCRIPT_PATH} ${pub_conn} \
            -ptl="market-data/bridge-stress/>" \
            -mr=5000 \
            -msa=10000 \
            -mn=999999999999999999 \
            -q > /dev/null 2>&1 &
        
        local bridge_pid=$!
        echo "$bridge_pid" > "logs/pids/bridge-stress.pid"
        
        # Attack duration
        sleep "$ATTACK_DURATION"
        
        # SYNCHRONOUS cleanup
        chaos_log "chaos-generator" "Stopping bridge stress SDKPerf processes..."
        kill -9 "$bridge_pid" 2>/dev/null || true
        pkill -9 -f "market-feed.*bridge-stress" 2>/dev/null || true
        
        # Verify dead
        for i in {1..5}; do
            if ! pgrep -f "market-feed.*bridge-stress" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        
        chaos_log "chaos-generator" "Bridge stress attack completed - sleeping"
        sleep "$SLEEP_INTERVAL"
    done
}

# Cleanup on exit
cleanup() {
    chaos_log "chaos-generator" "Shutting down ${SCENARIO} chaos generator"
    
    # Kill any remaining processes
    pkill -f "${SCENARIO}-chaos" 2>/dev/null
    
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
case "$SCENARIO" in
    queue-killer)
        scenario_queue_killer
        ;;
    acl-violation)
        scenario_acl_violation
        ;;
    connection-storm)
        scenario_connection_storm
        ;;
    bridge-stress)
        scenario_bridge_stress
        ;;
    *)
        echo "ERROR: Unknown scenario: $SCENARIO"
        usage
        ;;
esac
