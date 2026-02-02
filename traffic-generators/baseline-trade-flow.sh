#!/bin/bash
source scripts/load-env.sh

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_TRADING_RATE}"
    else
        echo "${WEEKDAY_TRADING_RATE}"
    fi
}

while true; do
    CURRENT_RATE=$(get_weekend_rate)
    echo "$(date): Starting baseline trade flow - rate: ${CURRENT_RATE} msgs/sec"
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -ptl="trading/baseline/heartbeat" \
        -mt=persistent \
        -mr="${CURRENT_RATE}" \
        -mn=3600 \
        -msa=512 >> logs/baseline-trade.log 2>&1
        
    echo "$(date): Baseline trade flow cycle completed - restarting in 30 seconds"
    sleep 30
done
