#!/bin/bash
source scripts/load-env.sh

# Cleanup function for graceful shutdown
cleanup_baseline_trade() {
    echo "$(date): Baseline trade flow shutting down - cleaning up processes"
    cleanup_sdkperf_processes "trading/orders/equities"
    cleanup_sdkperf_processes "equity_order_queue" 
    cleanup_sdkperf_processes "baseline_queue"
    exit 0
}

# Set up signal handlers
trap cleanup_baseline_trade SIGTERM SIGINT

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
    
    # Add limited queue consumers for automatic draining (prevents permanent queue buildup)
    # NOTE: Skip equity_order_queue - reserved for chaos testing (queue-killer)
    # bash "${SDKPERF_SCRIPT_PATH}" \
    #     -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
    #     -cu="${ORDER_ROUTER_USER}" \
    #     -cp="${ORDER_ROUTER_PASSWORD}" \
    #     -sql="equity_order_queue" >> logs/baseline-trade.log 2>&1 &
    # EQUITY_CONSUMER_PID=$!
    
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -sql="baseline_queue" >> logs/baseline-trade.log 2>&1 &
    BASELINE_CONSUMER_PID=$!
        
    # Let it run for configured interval then restart for rate adjustments
    local restart_interval="${TRAFFIC_RESTART_INTERVAL:-3600}"
    sleep "$restart_interval"
    sleep 2
    
    echo "$(date): Baseline trade flow cycle completed - restarting for rate check"
done
