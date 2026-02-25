#!/bin/bash
# traffic-generator.sh - Unified parameterized traffic generator
# Supports multiple traffic patterns: market-data, trade-flow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/load-env.sh"
source "${SCRIPT_DIR}/../scripts/sdkperf-wrapper.sh"

# Usage information
usage() {
    cat <<EOF
Usage: $0 --mode <mode> [options]

Traffic Generation Modes:
  market-data        Continuous market data feed (quotes, trades)
  trade-flow         Trade order flow with queue consumers

Options:
  --mode MODE           Traffic generation mode (required)
  --rate RATE           Publishing rate in msgs/sec (overrides .env)
  --weekend-rate RATE   Weekend rate in msgs/sec (overrides .env)
  --restart-interval SEC How often to restart and check rates (default: from .env)
  --log-file PATH       Log file path (default: logs/<mode>-traffic.log)
  --help                Show this help message

Examples:
  $0 --mode market-data
  $0 --mode market-data --rate 5000 --weekend-rate 500
  $0 --mode trade-flow --rate 1500
EOF
    exit 1
}

# Parse command line arguments
MODE=""
OVERRIDE_RATE=""
OVERRIDE_WEEKEND_RATE=""
OVERRIDE_RESTART_INTERVAL=""
LOG_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --rate)
            OVERRIDE_RATE="$2"
            shift 2
            ;;
        --weekend-rate)
            OVERRIDE_WEEKEND_RATE="$2"
            shift 2
            ;;
        --restart-interval)
            OVERRIDE_RESTART_INTERVAL="$2"
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
if [[ -z "$MODE" ]]; then
    echo "ERROR: --mode is required"
    usage
fi

# Set default log file if not specified
[[ -z "$LOG_FILE" ]] && LOG_FILE="logs/${MODE}-traffic.log"

# Get current rate based on day of week
get_current_rate() {
    local weekday_rate="$1"
    local weekend_rate="$2"
    local day_of_week=$(date +%u)
    
    # 6=Saturday, 7=Sunday
    if [[ $day_of_week -eq 6 || $day_of_week -eq 7 ]]; then
        echo "$weekend_rate"
    else
        echo "$weekday_rate"
    fi
}

# Market data traffic generation
generate_market_data() {
    local weekday_rate="${OVERRIDE_RATE:-${WEEKDAY_MARKET_DATA_RATE}}"
    local weekend_rate="${OVERRIDE_WEEKEND_RATE:-${WEEKEND_MARKET_DATA_RATE}}"
    local restart_interval="${OVERRIDE_RESTART_INTERVAL:-${TRAFFIC_RESTART_INTERVAL}}"
    
    chaos_log "traffic-generator" "Starting market data generator (weekday: ${weekday_rate}, weekend: ${weekend_rate})"
    
    while true; do
        local current_rate=$(get_current_rate "$weekday_rate" "$weekend_rate")
        chaos_log "traffic-generator" "Market data cycle starting - rate: ${current_rate} msgs/sec"
        
        # Use sdkperf-wrapper for connection
        local conn=$(sdkperf_get_connection "market-feed")
        
        chaos_log "traffic-generator" "SDKPerf command: ${SDKPERF_SCRIPT_PATH} ${conn} -ptl=... -stl=... -mr=${current_rate}"
        
        ${SDKPERF_SCRIPT_PATH} ${conn} \
            -ptl="market-data/equities/quotes/NYSE/AAPL,market-data/equities/quotes/NASDAQ/MSFT,market-data/equities/quotes/LSE/GOOGL" \
            -stl="market-data/equities/quotes/>" \
            -mr="${current_rate}" \
            -mn=999999999999999999 \
            -msa=256 \
            -q > /dev/null 2>&1 &
        
        local pid=$!
        echo "$pid" > "logs/pids/market-data-traffic.pid"
        
        # Wait for restart interval
        sleep "$restart_interval"
        
        # SYNCHRONOUS cleanup - verify ALL old processes are dead
        chaos_log "traffic-generator" "Stopping all market-feed SDKPerf processes..."
        
        # Kill tracked PID
        kill -9 "$pid" 2>/dev/null || true
        
        # Kill ALL matching processes and WAIT for them to die
        pkill -9 -f "market-feed" 2>/dev/null || true
        
        # Verify they're dead (wait up to 5 seconds)
        for i in {1..5}; do
            if ! pgrep -f "market-feed" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        
        chaos_log "traffic-generator" "Cleanup complete - starting new cycle"
        
        chaos_log "traffic-generator" "Market data cycle completed - restarting"
    done
}

# Trade flow traffic generation
generate_trade_flow() {
    local weekday_rate="${OVERRIDE_RATE:-${WEEKDAY_TRADE_FLOW_RATE}}"
    local weekend_rate="${OVERRIDE_WEEKEND_RATE:-${WEEKEND_TRADE_FLOW_RATE}}"
    local restart_interval="${OVERRIDE_RESTART_INTERVAL:-${TRAFFIC_RESTART_INTERVAL}}"
    local drain_consumers="${DEFAULT_DRAIN_CONSUMERS:-1}"
    
    chaos_log "traffic-generator" "Starting trade flow generator (weekday: ${weekday_rate}, weekend: ${weekend_rate})"
    
    while true; do
        local current_rate=$(get_current_rate "$weekday_rate" "$weekend_rate")
        chaos_log "traffic-generator" "Trade flow cycle starting - rate: ${current_rate} msgs/sec"
        
        # Publisher: order-router
        local pub_conn=$(sdkperf_get_connection "order-router")
        
        ${SDKPERF_SCRIPT_PATH} ${pub_conn} \
            -mt=persistent \
            -ptl="trading/orders/equities/AAPL,trading/orders/equities/MSFT,trading/orders/bonds/TSLA" \
            -stl="trading/orders/>" \
            -mr="${current_rate}" \
            -mn=999999999999999999 \
            -msa=512 \
            -q > /dev/null 2>&1 &
        
        local pub_pid=$!
        echo "$pub_pid" > "logs/pids/trade-flow-publisher.pid"
        
        # Subscriber: trade-processor consuming from baseline_queue
        local sub_conn=$(sdkperf_get_connection "trade-processor")
        
        ${SDKPERF_SCRIPT_PATH} ${sub_conn} \
            -sql=baseline_queue \
            -md \
            -q > /dev/null 2>&1 &
        
        local sub_pid=$!
        echo "$sub_pid" > "logs/pids/trade-flow-subscriber.pid"
        
        # Wait for restart interval
        sleep "$restart_interval"
        
        # SYNCHRONOUS cleanup - verify ALL old processes are dead
        chaos_log "traffic-generator" "Stopping all trade-flow SDKPerf processes..."
        
        # Kill tracked PIDs
        kill -9 "$pub_pid" "$sub_pid" 2>/dev/null || true
        
        # Kill ALL matching processes
        pkill -9 -f "order-router" 2>/dev/null || true
        pkill -9 -f "trade-processor.*sql=baseline" 2>/dev/null || true
        
        # Verify they're dead (wait up to 5 seconds)
        for i in {1..5}; do
            if ! pgrep -f "order-router.*trading" >/dev/null 2>&1 && \
               ! pgrep -f "trade-processor.*baseline" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        
        chaos_log "traffic-generator" "Cleanup complete - starting new cycle"
        
        chaos_log "traffic-generator" "Trade flow cycle completed - restarting"
    done
}

# Cleanup on exit
cleanup() {
    chaos_log "traffic-generator" "Shutting down ${MODE} traffic generator"
    
    # Read and kill tracked PIDs
    if [ -f "logs/pids/market-data-traffic.pid" ]; then
        local pid=$(cat "logs/pids/market-data-traffic.pid" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            sleep 2
            kill -9 "$pid" 2>/dev/null
        fi
    fi
    
    if [ -f "logs/pids/trade-flow-publisher.pid" ]; then
        local pid=$(cat "logs/pids/trade-flow-publisher.pid" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            sleep 2
            kill -9 "$pid" 2>/dev/null
        fi
    fi
    
    if [ -f "logs/pids/trade-flow-subscriber.pid" ]; then
        local pid=$(cat "logs/pids/trade-flow-subscriber.pid" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            sleep 2
            kill -9 "$pid" 2>/dev/null
        fi
    fi
    
    # Kill any remaining SDKPerf processes related to this mode
    pkill -f "${MODE}-traffic" 2>/dev/null
    
    # Grace period for broker-side cleanup
    sleep 2
    
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
case "$MODE" in
    market-data)
        generate_market_data
        ;;
    trade-flow)
        generate_trade_flow
        ;;
    *)
        echo "ERROR: Unknown mode: $MODE"
        usage
        ;;
esac
