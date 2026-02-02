#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Bombing default VPN with connections"
    
    # Start 25 market data consumers to hit connection limits
    for i in {1..25}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${MARKET_DATA_CONSUMER_USER}" \
            -cp="${MARKET_DATA_CONSUMER_PASSWORD}" \
            -stl="market-data/equities/NYSE/+/quotes" \
            -mr=1 -mn=1000 >> logs/connection-bomber.log 2>&1 &
    done
    
    wait
    echo "$(date): Market data connection bombing completed - waiting 300 seconds"
    sleep 300
done
