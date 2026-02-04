#!/bin/bash
source scripts/load-env.sh

# Cleanup function for graceful shutdown
cleanup_baseline_market() {
    echo "$(date): Baseline market data shutting down - cleaning up processes"
    cleanup_sdkperf_processes "market-data/equities/quotes"
    exit 0
}

# Set up signal handlers
trap cleanup_baseline_market SIGTERM SIGINT

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_MARKET_DATA_RATE}"
    else
        echo "${WEEKDAY_MARKET_DATA_RATE}"
    fi
}

while true; do
    CURRENT_RATE=$(get_weekend_rate)
    echo "$(date): Starting baseline market data feed - rate: ${CURRENT_RATE} msgs/sec"
    
    # Publish to multiple securities across different exchanges
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/equities/quotes/NYSE/AAPL,market-data/equities/quotes/NASDAQ/MSFT,market-data/equities/quotes/LSE/GOOGL" \
        -stl="market-data/equities/quotes/>" \
        -mr="${CURRENT_RATE}" \
        -mn=999999999 \
        -msa=256 >> logs/baseline-market.log 2>&1 &
        
    # Let it run for 1 hour then restart for rate adjustments
    sleep 3600
    pkill -f "market-data/equities/quotes" 2>/dev/null
    
    echo "$(date): Baseline market data cycle completed - restarting for rate check"
done
