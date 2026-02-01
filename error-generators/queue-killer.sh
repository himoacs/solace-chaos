#!/bin/bash
source scripts/load-env.sh

# Background execution setup
SCRIPT_NAME="queue-killer"
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
    pkill -f "${CHAOS_GENERATOR_USER}"
    rm -f "$PID_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Write PID to file
echo $$ > "$PID_FILE"

while true; do
    log "Starting queue killer - generating ACL violations and connection chaos"
    
    # Generate ACL violations - try to publish to restricted topics
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="trading/orders/equity/NYSE/new" \
        -mr=5 \
        -mn=3600 &  # Run for 12 minutes at 5 msgs/sec
        
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="market-data/premium/level3/NYSE/AAPL" \
        -mr=3 \
        -mn=2160 &  # Run for 12 minutes at 3 msgs/sec
        
    log "ACL violation generators started - running for 12 minutes"
    wait
    
    log "Queue killer cycle completed - restarting in 60 seconds"
    sleep 60
done
