#!/bin/bash
source scripts/load-env.sh

# Target queue configuration
TARGET_QUEUE="equity_order_queue"
TARGET_VPN="trading"
BURST_SIZE=100000      # Messages per burst
BURST_INTERVAL=1800    # Seconds between bursts (30 minutes)
MESSAGE_SIZE=5000      # 5KB messages

echo "$(date): Starting optimized queue killer with built-in burst mode"
echo "$(date): Target: ${TARGET_QUEUE} on ${TARGET_VPN}"
echo "$(date): Strategy: ${BURST_SIZE} messages every ${BURST_INTERVAL} seconds"

while true; do
    echo "$(date): Starting burst publisher + drain consumer cycle"
    
    # Burst publisher - sends messages in waves using built-in burst mode
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/new" \
        -mt=persistent \
        -mr=0 \
        -mbs=${BURST_SIZE} \
        -mbi=${BURST_INTERVAL} \
        -msa=${MESSAGE_SIZE} \
        -mn=999999999 \
        -q >> logs/queue-killer.log 2>&1 &
    
    BURST_PID=$!
    echo "$(date): ✅ Burst publisher started (PID: ${BURST_PID})"
    
    # Drain consumer - always running to slowly drain the queue
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${ORDER_ROUTER_USER}" \
        -cp="${ORDER_ROUTER_PASSWORD}" \
        -sql="${TARGET_QUEUE}" \
        -mn=999999999 \
        -q >> logs/queue-killer.log 2>&1 &
    
    CONSUMER_PID=$!
    echo "$(date): ✅ Drain consumer started (PID: ${CONSUMER_PID})"
    echo "$(date): 🔄 Burst mode active: ${BURST_SIZE} msgs every ${BURST_INTERVAL}s"
    
    # Let it run for 2 hours, then clean restart
    sleep 7200
    
    echo "$(date): 🔄 Cycle complete, restarting for fresh state..."
    kill ${BURST_PID} ${CONSUMER_PID} 2>/dev/null
    pkill -f "sql=${TARGET_QUEUE}" 2>/dev/null
    sleep 5
done
