#!/bin/bash
source scripts/load-env.sh

# Cleanup function for graceful shutdown
cleanup_connection_bomber() {
    echo "$(date): Connection bomber shutting down - cleaning up processes"
    cleanup_sdkperf_processes "market-data/equities/quotes/NYSE"
    exit 0
}

# Set up signal handlers
trap cleanup_connection_bomber SIGTERM SIGINT

while true; do
    echo "$(date): Starting gentle connection pressure test"
    
    # Check resource limits before starting
    if ! check_resource_limits 75; then  # Higher limit for intensive connection testing
        echo "$(date): Resource limits exceeded - waiting before retry"
        sleep 300
        continue
    fi
    
    # Start 25 long-running market data consumers (intensive connection load)
    for i in {1..25}; do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${MARKET_DATA_CONSUMER_USER}" \
            -cp="${MARKET_DATA_CONSUMER_PASSWORD}" \
            -stl="market-data/equities/quotes/NYSE/>" >> logs/connection-bomber.log 2>&1 &
    done
    
    # Let connections run for 2 hours then cycle
    sleep 7200
    cleanup_sdkperf_processes "market-data/equities/quotes/NYSE"
    echo "$(date): Connection pressure cycle completed - restarting"
    sleep 60
done
