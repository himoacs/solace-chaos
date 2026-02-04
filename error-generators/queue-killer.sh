#!/bin/bash
source scripts/load-env.sh

# Target queue configuration
TARGET_QUEUE="equity_order_queue"
TARGET_VPN="trading-vpn"
FULL_THRESHOLD=85  # Consider queue "full" at 85%
DRAIN_THRESHOLD=20 # Resume attacks when below 20%
DRAIN_PIDS=""      # Track drain consumer PIDs for cleanup
PUBLISHER_PID=""   # Track publisher PID for control

while true; do
    echo "$(date): Starting intelligent queue killer attack on ${TARGET_QUEUE}"
    DRAIN_PIDS=""  # Reset drain consumer tracking for new cycle
    
    # Check if queue is already full
    if check_queue_full "${TARGET_QUEUE}" "${TARGET_VPN}" "${FULL_THRESHOLD}"; then
        echo "$(date): 🚨 Queue ${TARGET_QUEUE} already at ${FULL_THRESHOLD}%! Starting drain consumer immediately..."
        
        # Start drain consumer - exclusive queues allow only one consumer per queue
        bash "${SDKPERF_SCRIPT_PATH}" \
                -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
                -cu="${ORDER_ROUTER_USER}" \
                -cp="${ORDER_ROUTER_PASSWORD}" \
                -sql="${TARGET_QUEUE}" >> logs/queue-killer.log 2>&1 &
        DRAIN_PIDS="$!"
        
        echo "$(date): 🔄 Started 1 drain consumer, waiting for queue to drop to ${DRAIN_THRESHOLD}%..."
        wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" "${DRAIN_THRESHOLD}" 300
        
        # Stop all drain consumers
        if [ -n "$DRAIN_PIDS" ]; then
            echo "$(date): ✅ Queue drained! Stopping all drain consumers..."
            kill $DRAIN_PIDS 2>/dev/null
            wait_for_pids_to_exit $DRAIN_PIDS
        fi
        
        echo "$(date): 💤 Queue drained, waiting 60 seconds before starting fill cycle..."
        sleep 60
    fi
    
    # Start persistent publisher in background to fill queue (very high rate to overcome active consumers)
    echo "$(date): Starting persistent publisher to fill queue to ${FULL_THRESHOLD}%..."
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${CHAOS_GENERATOR_USER}" \
        -cp="${CHAOS_GENERATOR_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/new" \
        -mt=persistent \
        -mr=10000 \
        -mn=500000 \
        -msa=5000 >> logs/queue-killer.log 2>&1 &
    
    PUBLISHER_PID=$!
    echo "$(date): Publisher started (PID: ${PUBLISHER_PID}), monitoring queue fill..."
    
    # Monitor queue until it reaches the threshold
    fill_timeout=300  # 5 minutes max to fill
    start_time=$(date +%s)
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if check_queue_full "${TARGET_QUEUE}" "${TARGET_VPN}" "${FULL_THRESHOLD}"; then
            echo "$(date): 🚨 Queue reached ${FULL_THRESHOLD}%! Stopping publisher and starting drain consumers..."
            
            # Stop the publisher first
            kill ${PUBLISHER_PID} 2>/dev/null
            
            # Start drain consumer - exclusive queues allow only one consumer per queue
            bash "${SDKPERF_SCRIPT_PATH}" \
                    -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
                    -cu="${ORDER_ROUTER_USER}" \
                    -cp="${ORDER_ROUTER_PASSWORD}" \
                    -sql="${TARGET_QUEUE}" >> logs/queue-killer.log 2>&1 &
            DRAIN_PIDS="$!"
        
        echo "$(date): 🔄 Started 1 drain consumer, waiting for queue to drop to ${DRAIN_THRESHOLD}%..."
            # Wait for queue to drain to threshold
            wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" "${DRAIN_THRESHOLD}" 300
            
            # Stop all drain consumers
            if [ -n "$DRAIN_PIDS" ]; then
                echo "$(date): ✅ Queue drained! Stopping all drain consumers..."
                kill $DRAIN_PIDS 2>/dev/null
                wait_for_pids_to_exit $DRAIN_PIDS
            fi
            
            echo "$(date): 💤 Cycle complete. Waiting 60 seconds before next attack..."
            sleep 60
            break
            
        elif [ ${elapsed} -ge ${fill_timeout} ]; then
            echo "$(date): ⏰ Publisher timeout after ${fill_timeout}s"
            usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
            echo "$(date): Final queue usage: ${usage}%"
            
            # Kill publisher and clean up any partial fill
            kill ${PUBLISHER_PID} 2>/dev/null
            
            if [ "$usage" -gt 10 ]; then
                echo "$(date): Cleaning up ${usage}% partial fill..."
                bash "${SDKPERF_SCRIPT_PATH}" \
                    -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
                    -cu="${ORDER_ROUTER_USER}" \
                    -cp="${ORDER_ROUTER_PASSWORD}" \
                    -sql="${TARGET_QUEUE}" >> logs/queue-killer.log 2>&1 &
                DRAIN_PIDS="$!"
                
                wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" 5 60
                
                if [ -n "$DRAIN_PIDS" ]; then
                    kill $DRAIN_PIDS 2>/dev/null
                fi
            fi
            
            break
        else
            # Show progress every 30 seconds
            if [ $((elapsed % 30)) -eq 0 ]; then
                current_usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
                echo "$(date): Queue at ${current_usage}% after ${elapsed}s (target: ${FULL_THRESHOLD}%)"
            fi
            sleep 10
        fi
    done
done
