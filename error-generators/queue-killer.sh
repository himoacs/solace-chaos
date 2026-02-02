#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Starting queue killer attack on equity-order-queue"
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="trading/orders/equity/NYSE/new" \
        -mt=persistent \
        -mr=1000 \
        -mn=100000 \
        -msa=5000 >> logs/queue-killer.log 2>&1
        
    echo "$(date): Queue killer stopped (queue probably full!) - waiting 120 seconds"
    sleep 120
done
