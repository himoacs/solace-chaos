#!/bin/bash
source scripts/load-env.sh

# Background execution setup
SCRIPT_NAME="baseline-trade-flow"
LOG_FILE="logs/${SCRIPT_NAME}.log"
PID_FILE="logs/${SCRIPT_NAME}.pid"

# Create logs directory if it doesn't exist
mkdir -p logs

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $1" | tee -a "$LOG_FILE"
}

# Function to cleanup on exit
cleanup() {
    log "Cleaning up background processes..."
    pkill -f "trading/"
    rm -f "$PID_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Write PID to file
echo $$ > "$PID_FILE"

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_RATE}"
    else
        echo "${WEEKDAY_RATE}"
    fi
}

while true; do
    log "Starting baseline trade flow - Queue-based guaranteed messaging"
    
    # Order routing (persistent messages to queues)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -pql="equity_order_queue" \
        -mr="$(($(date +%u | awk '{if($1==6||$1==7) print 30; else print 300}') / 3))" \
        -mn=100000 \
        -md &
        
    # Trade processing
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${TRADE_PROCESSOR_USER}" \
        -cp="${TRADE_PROCESSOR_PASSWORD}" \
        -pql="baseline_queue" \
        -mr="$(($(date +%u | awk '{if($1==6||$1==7) print 30; else print 300}') / 3))" \
        -mn=100000 \
        -md &
        
    # Settlement processing
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${TRADE_PROCESSOR_USER}" \
        -cp="${TRADE_PROCESSOR_PASSWORD}" \
        -pql="settlement_queue" \
        -mr="$(($(date +%u | awk '{if($1==6||$1==7) print 30; else print 300}') / 3))" \
        -mn=100000 \
        -md &
        
    log "Trade flow publishers started - waiting for completion..."
    wait
    
    log "Trade flow cycle completed - restarting in 30 seconds"
    sleep 30
done
