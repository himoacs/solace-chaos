#!/bin/bash
source scripts/load-env.sh

# Trap signals for cleanup
cleanup() {
    echo "$(date): Received shutdown signal - cleaning up baseline market data processes..." >> logs/baseline-market.log
    pkill -P $$ 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

get_weekend_rate() {
    local day_of_week=$(date +%u)
    if [ $day_of_week -eq 6 ] || [ $day_of_week -eq 7 ]; then
        echo "${WEEKEND_MARKET_DATA_RATE}"
    else
        echo "${WEEKDAY_MARKET_DATA_RATE}"
    fi
}

# Start continuous market data flow with publisher + subscriber
echo "$(date): Starting continuous baseline market data..." >> logs/baseline-market.log

# Start subscriber first  
echo "$(date): Starting market data subscriber..." >> logs/baseline-market.log
bash "${SDKPERF_SCRIPT_PATH}" \
    -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
    -cu="${MARKET_DATA_CONSUMER_USER}" \
    -cp="${MARKET_DATA_CONSUMER_PASSWORD}" \
    -stl="market-data/equities/NYSE/baseline/>" >> logs/baseline-market-subscriber.log 2>&1 &

SUBSCRIBER_PID=$!

# Wait a moment for subscriber to connect
sleep 5

# Start continuous publisher
while true; do
    CURRENT_RATE=$(get_weekend_rate)
    echo "$(date): Starting market data publisher - rate: ${CURRENT_RATE} msgs/sec" >> logs/baseline-market.log
    
    # Publish to market-data/equities/NYSE/baseline/quotes (specific topic that subscriber will receive via wildcard)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/equities/NYSE/baseline/quotes" \
        -mr="${CURRENT_RATE}" \
        -mn=999999999 \
        -msa=256 >> logs/baseline-market-publisher.log 2>&1 &
        
    PUBLISHER_PID=$!
    
    # Wait for this publisher cycle and check health
    sleep 3600
    
    # Stop current publisher for restart
    kill $PUBLISHER_PID 2>/dev/null
    wait $PUBLISHER_PID 2>/dev/null
    
    echo "$(date): Market data publisher cycle completed - restarting" >> logs/baseline-market.log
done
