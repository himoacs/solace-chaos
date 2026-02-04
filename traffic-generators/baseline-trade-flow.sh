#!/bin/bash
source scripts/load-env.sh

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_TRADE_FLOW_RATE}"
    else
        echo "${WEEKDAY_TRADE_FLOW_RATE}"
    fi
}

while true; do
    CURRENT_RATE=$(get_weekend_rate)
    echo "$(date): Starting baseline trade flow - rate: ${CURRENT_RATE} msgs/sec"
    
    # Publish trade executions for multiple securities
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/AAPL,trading/orders/equities/NASDAQ/TSLA" \
        -mt=persistent \
        -mr="${CURRENT_RATE}" \
        -mn=999999999 \
        -msa=512 >> logs/baseline-trade.log 2>&1 &
        
    # Let it run for 1 hour then restart for rate adjustments
    sleep 3600
    pkill -f "trading/orders/equities" 2>/dev/null
    
    echo "$(date): Baseline trade flow cycle completed - restarting for rate check"
done
