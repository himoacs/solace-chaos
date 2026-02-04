#!/bin/bash

# Intelligent Queue Killer - Publisher Burst Strategy
# Uses controlled publisher bursts to fill queues, then gradual reduction to drain

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/load-env.sh" || {
    echo "Error: Could not load environment. Make sure load-env.sh exists."
    exit 1
}

# Configuration
TARGET_QUEUE="equity_order_queue"
TARGET_VPN="trading-vpn"
FULL_THRESHOLD=85
DRAIN_THRESHOLD=20
BASE_RATE=4000           # Base publisher rate (msg/sec) 
BURST_RATE=6000          # Each burst publisher rate (msg/sec)
MAX_BURST_PUBLISHERS=3   # Maximum burst publishers to add

echo "$(date): Starting intelligent queue killer with publisher burst strategy"
echo "$(date): Target: ${TARGET_QUEUE} on ${TARGET_VPN}"
echo "$(date): Strategy: Burst publishers to fill, then gradual reduction to drain"

cleanup() {
    echo "$(date): Cleaning up all publishers..."
    pkill -f "trading/orders/equities/NYSE" 2>/dev/null
    pkill -f "chaos-generator" 2>/dev/null
    exit 0
}

trap cleanup INT TERM

while true; do
    echo "$(date): "
    echo "=== Starting new burst cycle ==="
    echo ""
    
    # Step 1: Ensure we have baseline publisher + consumer (equilibrium)
    echo "$(date): 📊 Establishing baseline equilibrium..."
    
    # Start baseline publisher
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/baseline" \
        -mt=persistent \
        -mr=${BASE_RATE} \
        -mn=999999999 \
        -msa=512 >> logs/queue-killer.log 2>&1 &
    BASE_PUBLISHER_PID=$!
    
    # Ensure exactly 1 consumer exists
    consumer_count=$(ps aux | grep "sql=${TARGET_QUEUE}" | grep -v grep | wc -l | tr -d ' ')
    if [ "$consumer_count" -eq 0 ]; then
        echo "$(date): Adding baseline consumer..."
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${CHAOS_GENERATOR_USER}" \
            -cp="${CHAOS_GENERATOR_PASSWORD}" \
            -sql="${TARGET_QUEUE}" >> logs/queue-killer.log 2>&1 &
        CONSUMER_PID=$!
    elif [ "$consumer_count" -gt 1 ]; then
        echo "$(date): Too many consumers ($consumer_count), cleaning up excess..."
        ./scripts/cleanup-excess-consumers.sh >/dev/null
    fi
    
    # Step 2: Add burst publishers to overwhelm the single consumer
    echo "$(date): 🚀 Adding burst publishers to overwhelm consumer..."
    BURST_PIDS=""
    
    for i in $(seq 1 $MAX_BURST_PUBLISHERS); do
        bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${CHAOS_GENERATOR_USER}" \
            -cp="${CHAOS_GENERATOR_PASSWORD}" \
            -ptl="trading/orders/equities/NYSE/burst${i}" \
            -mt=persistent \
            -mr=${BURST_RATE} \
            -mn=999999999 \
            -msa=1024 >> logs/queue-killer.log 2>&1 &
        BURST_PIDS="$! $BURST_PIDS"
        
        total_rate=$((BASE_RATE + i * BURST_RATE))
        echo "$(date): Added burst publisher $i (Total rate: ${total_rate} msg/sec)"
        sleep 2
    done
    
    total_burst_rate=$((BASE_RATE + MAX_BURST_PUBLISHERS * BURST_RATE))
    echo "$(date): 💥 Full burst active: ${total_burst_rate} msg/sec vs ~7000 msg/sec consumer"
    echo "$(date): Net fill rate: ~$((total_burst_rate - 7000)) msg/sec"
    
    # Step 3: Monitor queue fill to threshold
    echo "$(date): 📈 Monitoring queue fill to ${FULL_THRESHOLD}%..."
    fill_timeout=300  # 5 minutes max
    start_time=$(date +%s)
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        current_usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
        
        if [ "$current_usage" -ge "$FULL_THRESHOLD" ]; then
            echo "$(date): 🎯 Queue reached ${current_usage}% (target: ${FULL_THRESHOLD}%)"
            break
        elif [ $elapsed -ge $fill_timeout ]; then
            echo "$(date): ⏰ Fill timeout after ${fill_timeout}s at ${current_usage}%"
            break
        else
            if [ $((elapsed % 30)) -eq 0 ]; then
                echo "$(date): Queue at ${current_usage}% after ${elapsed}s (target: ${FULL_THRESHOLD}%)"
            fi
            sleep 10
        fi
    done
    
    # Step 4: Gradually remove burst publishers to let consumer drain
    echo "$(date): 📉 Gradually removing burst publishers for controlled drain..."
    
    burst_count=$MAX_BURST_PUBLISHERS
    for pid in $BURST_PIDS; do
        if kill "$pid" 2>/dev/null; then
            burst_count=$((burst_count - 1))
            remaining_rate=$((BASE_RATE + burst_count * BURST_RATE))
            echo "$(date): Removed burst publisher (Remaining rate: ${remaining_rate} msg/sec)"
            
            # Wait a bit to let consumer catch up
            sleep 30
            
            current_usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
            echo "$(date): Queue now at ${current_usage}% with ${remaining_rate} msg/sec publish rate"
        fi
    done
    
    # Step 5: Wait for baseline consumer to drain to threshold
    echo "$(date): 🔄 Baseline rate active (${BASE_RATE} msg/sec), waiting for drain to ${DRAIN_THRESHOLD}%..."
    
    drain_timeout=300  # 5 minutes max
    start_time=$(date +%s)
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        current_usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
        
        if [ "$current_usage" -le "$DRAIN_THRESHOLD" ]; then
            echo "$(date): ✅ Queue drained to ${current_usage}% (target: ${DRAIN_THRESHOLD}%)"
            break
        elif [ $elapsed -ge $drain_timeout ]; then
            echo "$(date): ⏰ Drain timeout after ${drain_timeout}s at ${current_usage}%"
            break
        else
            if [ $((elapsed % 30)) -eq 0 ]; then
                echo "$(date): Queue at ${current_usage}% after ${elapsed}s (draining to ${DRAIN_THRESHOLD}%)"
            fi
            sleep 10
        fi
    done
    
    # Step 6: Clean up and prepare for next cycle
    echo "$(date): 🧹 Cleaning up baseline publisher..."
    kill "$BASE_PUBLISHER_PID" 2>/dev/null
    
    echo "$(date): 💤 Cycle complete. Resting 60 seconds before next burst..."
    sleep 60
done