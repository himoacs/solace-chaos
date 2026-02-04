#!/bin/bash
# Continuous Publisher - Auto-restarts when SDKPerf finishes
# Provides truly low-touch operation for long-running chaos testing

source scripts/load-env.sh

# Default parameters
RESTART_DELAY=5  # seconds between restarts
MAX_RESTARTS=0   # 0 = infinite restarts
CURRENT_RESTARTS=0

# Publisher configuration
USER="${CHAOS_GENERATOR_USER}"
PASSWORD="${CHAOS_GENERATOR_PASSWORD}"
TOPIC="trading/orders/equities/NYSE/new"
RATE=4000
CONNECTIONS=2
MESSAGE_COUNT=1000000  # 1M messages per cycle (~4 minutes at 4k/sec)
MESSAGE_SIZE=15000

# Log file
LOG_FILE="logs/continuous-publisher.log"
mkdir -p logs

echo "$(date): 🚀 Starting continuous publisher" | tee -a "$LOG_FILE"
echo "$(date): Rate: ${RATE} msg/sec x ${CONNECTIONS} connections = $((RATE * CONNECTIONS)) total" | tee -a "$LOG_FILE"
echo "$(date): Message size: ${MESSAGE_SIZE} bytes" | tee -a "$LOG_FILE"
echo "$(date): Cycle size: ${MESSAGE_COUNT} messages (~$((MESSAGE_COUNT / (RATE * CONNECTIONS) / 60)) minutes per cycle)" | tee -a "$LOG_FILE"

# Function to run publisher
run_publisher() {
    echo "$(date): 📤 Starting publisher cycle $((CURRENT_RESTARTS + 1))" | tee -a "$LOG_FILE"
    
    "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="$USER" \
        -cp="$PASSWORD" \
        -ptl="$TOPIC" \
        -mr="$RATE" \
        -cc="$CONNECTIONS" \
        -mn="$MESSAGE_COUNT" \
        -msa="$MESSAGE_SIZE" >> "$LOG_FILE" 2>&1
    
    local exit_code=$?
    echo "$(date): 📝 Publisher cycle completed (exit code: $exit_code)" | tee -a "$LOG_FILE"
    return $exit_code
}

# Main loop
while true; do
    run_publisher
    
    CURRENT_RESTARTS=$((CURRENT_RESTARTS + 1))
    
    # Check if we've hit the restart limit (0 = infinite)
    if [ $MAX_RESTARTS -gt 0 ] && [ $CURRENT_RESTARTS -ge $MAX_RESTARTS ]; then
        echo "$(date): 🛑 Reached maximum restarts ($MAX_RESTARTS), stopping" | tee -a "$LOG_FILE"
        break
    fi
    
    echo "$(date): ⏱️  Waiting ${RESTART_DELAY} seconds before next cycle..." | tee -a "$LOG_FILE"
    sleep $RESTART_DELAY
done

echo "$(date): ✅ Continuous publisher stopped" | tee -a "$LOG_FILE"