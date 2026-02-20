#!/bin/bash
source scripts/load-env.sh

# Configurable attack intervals
ATTACK_DURATION="${BRIDGE_ATTACK_DURATION:-600}"  # 10 minutes default
SLEEP_INTERVAL="${BRIDGE_SLEEP_INTERVAL:-300}"    # 5 minutes between attacks default

while true; do
    echo "$(date): Starting bridge stress test (duration: ${ATTACK_DURATION}s)"
    
    # Heavy publisher on default VPN
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/NYSE/AAPL/L1" \
        -mr=2000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
    
    # Additional publishers for different exchanges and securities
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/NASDAQ/MSFT/L1" \
        -mr=2000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
        
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/LSE/TSLA/L2" \
        -mr=1000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
    
    PUB_PID=$!
    
    # Bridge client will consume from cross_market_data_queue automatically
    # No need for additional SDKPerf consumers
    
    # Cross-VPN bridge consumers on trading VPN (actual bridge testing)
    # Start single drain consumer for exclusive queue
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -sql=bridge_receive_queue \
        -pe >> logs/bridge-killer.log 2>&1 &
    
    # Let it run for 10 minutes then kill
    sleep 600
    kill $PUB_PID 2>/dev/null
    pkill -f "bridge-stress" 2>/dev/null
    
    echo "$(date): Bridge stress test completed - waiting 300 seconds"
    sleep 300
done
