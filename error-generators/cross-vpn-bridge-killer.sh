#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Starting cross-VPN bridge stress test (optimized with multi-flow)"
    
    # Consolidated publisher - all exchanges in one process with multiple topics
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/NYSE/AAPL/L1,market-data/bridge-stress/equities/NASDAQ/MSFT/L1,market-data/bridge-stress/equities/LSE/TSLA/L2" \
        -mr=2000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
    
    PUB_PID=$!
    
    # Bridge client will consume from cross_market_data_queue automatically
    # No need for additional SDKPerf consumers
    
    # Cross-VPN bridge consumers on trading VPN - single process with 2 flows
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -sql=bridge_receive_queue \
        -sfl=2 \
        -pe >> logs/bridge-killer.log 2>&1 &
    
    CONSUMER_PID=$!
    
    # Let it run for 10 minutes then kill
    sleep 600
    kill $PUB_PID $CONSUMER_PID 2>/dev/null
    
    echo "$(date): Bridge stress test completed - waiting 300 seconds"
    sleep 300
done
