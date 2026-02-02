#!/bin/bash
source scripts/load-env.sh

# Trap signals for cleanup
cleanup() {
    echo "$(date): Received shutdown signal - cleaning up baseline trade flow processes..." >> logs/baseline-trade.log
    pkill -P $$ 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_TRADING_RATE}"
    else
        echo "${WEEKDAY_TRADING_RATE}"
    fi
}

# Start continuous trade flow publisher and subscriber
echo "$(date): Starting continuous baseline trade flow..." >> logs/baseline-trade.log

# Start subscriber first (using guaranteed messaging with queue)
echo "$(date): Starting trade flow subscriber..." >> logs/baseline-trade.log
bash "${SDKPERF_SCRIPT_PATH}" \
    -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
    -cu="${ORDER_ROUTER_USER}" \
    -cp="${ORDER_ROUTER_PASSWORD}" \
    -sql="equity_order_queue" >> logs/baseline-trade-subscriber.log 2>&1 &

SUBSCRIBER_PID=$!

# Wait a moment for subscriber to connect
sleep 5

# Start continuous publisher
while true; do
    CURRENT_RATE=$(get_weekend_rate)
    echo "$(date): Starting trade flow publisher - rate: ${CURRENT_RATE} msgs/sec" >> logs/baseline-trade.log
    
    # Publish to trading/orders/equity/baseline/executions (specific topic that subscriber will receive via queue subscription)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -ptl="trading/orders/equity/baseline/executions" \
        -mr="${CURRENT_RATE}" \
        -mn=999999999 \
        -msa=512 >> logs/baseline-trade-publisher.log 2>&1 &
        
    PUBLISHER_PID=$!
    
    # Wait for this publisher cycle and check health
    sleep 3600
    
    # Stop current publisher for restart
    kill $PUBLISHER_PID 2>/dev/null
    wait $PUBLISHER_PID 2>/dev/null
    
    echo "$(date): Trade flow publisher cycle completed - restarting" >> logs/baseline-trade.log
done
