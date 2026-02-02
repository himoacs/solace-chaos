#!/bin/bash
source scripts/load-env.sh

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
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/baseline/heartbeat" \
        -mr="${CURRENT_RATE}" \
        -mn=3600 \
        -msa=256 2>&1 | tee -a logs/baseline-market.log
        
    echo "$(date): Baseline market data cycle completed - restarting in 30 seconds"
    sleep 30
done
