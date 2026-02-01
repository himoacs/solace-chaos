#!/bin/bash
source scripts/load-env.sh

# Background execution setup
SCRIPT_NAME="baseline-market-data"
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
    pkill -f "market-data/"
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

# Start continuous market data publishers for hierarchical topics (direct messaging, no queues)
# Simulate real market data with multiple symbols and exchanges
CURRENT_RATE=$(get_weekend_rate)
log "Starting baseline market data feed - rate: ${CURRENT_RATE} msgs/sec total across all topics"

# Calculate message count to run for ~24 hours per stream
# Price streams: CURRENT_RATE/30 msgs/sec * 86400 seconds = ~24 hours of messages
PRICE_MESSAGE_COUNT=$((CURRENT_RATE * 86400 / 30))
# Quote streams: CURRENT_RATE/60 msgs/sec * 86400 seconds = ~24 hours of messages  
QUOTE_MESSAGE_COUNT=$((CURRENT_RATE * 86400 / 60))

# Ensure minimum counts for low rates
if [ $PRICE_MESSAGE_COUNT -lt 10000 ]; then
    PRICE_MESSAGE_COUNT=10000
fi
if [ $QUOTE_MESSAGE_COUNT -lt 5000 ]; then
    QUOTE_MESSAGE_COUNT=5000
fi

log "Message counts - Prices: ${PRICE_MESSAGE_COUNT}, Quotes: ${QUOTE_MESSAGE_COUNT} (~24hr runtime)"

for symbol in AAPL GOOGL MSFT TSLA NVDA; do
    for exchange in NYSE NASDAQ; do
        # Price updates - higher frequency (runs for ~24 hours)
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${MARKET_DATA_FEED_USER}" \
            -cp="${MARKET_DATA_FEED_PASSWORD}" \
            -ptl="market-data/prices/${exchange}/${symbol}" \
            -mr="$((CURRENT_RATE / 30))" \
            -mn="${PRICE_MESSAGE_COUNT}" \
            -msa=128 &
        
        # Quote updates (bid/ask) - lower frequency (runs for ~24 hours)
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${MARKET_DATA_FEED_USER}" \
            -cp="${MARKET_DATA_FEED_PASSWORD}" \
            -ptl="market-data/quotes/${exchange}/${symbol}/bid" \
            -mr="$((CURRENT_RATE / 60))" \
            -mn="${QUOTE_MESSAGE_COUNT}" \
            -msa=64 &
            
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${MARKET_DATA_FEED_USER}" \
            -cp="${MARKET_DATA_FEED_PASSWORD}" \
            -ptl="market-data/quotes/${exchange}/${symbol}/ask" \
            -mr="$((CURRENT_RATE / 60))" \
            -mn="${QUOTE_MESSAGE_COUNT}" \
            -msa=64 &
    done
done

log "All market data publishers started (30 continuous streams)"
log "Price updates: $((CURRENT_RATE / 30)) msgs/sec per symbol/exchange (10 streams)"
log "Quote updates: $((CURRENT_RATE / 60)) msgs/sec per bid/ask (20 streams)"

# Keep the script running and monitor the background processes
while true; do
    sleep 300  # Check every 5 minutes
    
    # Check if rate should change (weekend vs weekday)
    NEW_RATE=$(get_weekend_rate)
    if [ "$NEW_RATE" != "$CURRENT_RATE" ]; then
        log "Rate change detected ($CURRENT_RATE -> $NEW_RATE), restarting publishers..."
        pkill -f "market-data/"
        sleep 5
        exec "$0"  # Restart this script
    fi
    
    log "Market data publishers still running (PID: $$)..."
done
