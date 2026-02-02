#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Starting cross-VPN bridge stress test"
    
    # Heavy publisher on default VPN
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/NYSE/AAPL/L1" \
        -mr=5000 -mn=50000 -msa=2048 >> logs/bridge-killer.log 2>&1 &
    
    PUB_PID=$!
    
    # Multiple consumers on default VPN (simplified - no bridge needed)
    for i in {1..5}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${RISK_CALCULATOR_USER}" \
            -cp="${RISK_CALCULATOR_PASSWORD}" \
            -stl="market-data/bridge-stress/equities/NYSE/AAPL/L1" \
            -sql=cross-market-data-queue \
            -pe -md >> logs/bridge-killer.log 2>&1 &
    done
    
    # Let it run for 10 minutes then kill
    sleep 600
    kill $PUB_PID 2>/dev/null
    pkill -f "bridge-stress" 2>/dev/null
    
    echo "$(date): Bridge stress test completed - waiting 300 seconds"
    sleep 300
done
