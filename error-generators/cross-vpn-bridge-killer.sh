#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Starting cross-VPN bridge stress test"
    
    # Heavy publisher on default VPN (continuous publishing)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${MARKET_DATA_FEED_USER}" \
        -cp="${MARKET_DATA_FEED_PASSWORD}" \
        -ptl="market-data/bridge-stress/equities/NYSE/AAPL/L1" \
        -mr=5000 -mn=999999999 -msa=2048 >> logs/bridge-killer.log 2>&1 &
    
    PUB_PID=$!
    
    # Queue consumers on default VPN
    for i in {1..3}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${RISK_CALCULATOR_USER}" \
            -cp="${RISK_CALCULATOR_PASSWORD}" \
            -sql=cross_market_data_queue \
            -pe >> logs/bridge-killer.log 2>&1 &
    done
    
    # Cross-VPN bridge consumers on trading-vpn (actual bridge testing)
    for i in {1..2}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${ORDER_ROUTER_USER}" \
            -cp="${ORDER_ROUTER_PASSWORD}" \
            -sql=bridge_receive_queue \
            -pe >> logs/bridge-killer.log 2>&1 &
    done
    
    # Let it run for 1 hour then restart
    sleep 3600
    kill $PUB_PID 2>/dev/null
    pkill -f "bridge-stress" 2>/dev/null
    
    echo "$(date): Bridge stress test cycle completed - restarting"
done
