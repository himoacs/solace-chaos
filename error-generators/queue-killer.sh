#!/bin/bash
source scripts/load-env.sh

# Target queue configuration
TARGET_QUEUE="equity_order_queue"
TARGET_VPN="trading-vpn"
FULL_THRESHOLD=85  # Consider queue "full" at 85%
DRAIN_THRESHOLD=20 # Resume attacks when below 20%

while true; do
    echo "$(date): Starting intelligent queue killer attack on ${TARGET_QUEUE}"
    
    # Check if queue is already full
    if check_queue_full "${TARGET_QUEUE}" "${TARGET_VPN}" "${FULL_THRESHOLD}"; then
        echo "$(date): Queue ${TARGET_QUEUE} already full - waiting for drain first"
        wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" "${DRAIN_THRESHOLD}"
    fi
    
    # Start attack with connection retry logic
    attack_successful=false
    retry_count=0
    max_retries=3
    
    while [ ${retry_count} -lt ${max_retries} ] && [ "${attack_successful}" = false ]; do
        echo "$(date): Starting attack attempt $((retry_count + 1))/${max_retries}"
        
        if bash "${SDKPERF_SCRIPT_PATH}" \
            -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
            -cu="${CHAOS_GENERATOR_USER}" \
            -cp="${CHAOS_GENERATOR_PASSWORD}" \
            -ptl="trading/orders/equities/NYSE/new" \
            -mt=persistent \
            -mr=1000 \
            -mn=100000 \
            -msa=5000 >> logs/queue-killer.log 2>&1; then
            
            attack_successful=true
            echo "$(date): Attack completed successfully"
        else
            retry_count=$((retry_count + 1))
            echo "$(date): Attack failed, retry ${retry_count}/${max_retries}"
            sleep 10
        fi
    done
    
    if [ "${attack_successful}" = false ]; then
        echo "$(date): All attack attempts failed - waiting 300 seconds before retry"
        sleep 300
        continue
    fi
    
    # Wait for queue to fill and then drain
    echo "$(date): Monitoring queue fullness..."
    
    # Wait up to 10 minutes for queue to fill
    fill_timeout=600
    start_time=$(date +%s)
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if check_queue_full "${TARGET_QUEUE}" "${TARGET_VPN}" "${FULL_THRESHOLD}"; then
            echo "$(date): Queue successfully filled! Now waiting for drain..."
            break
        elif [ ${elapsed} -ge ${fill_timeout} ]; then
            echo "$(date): Queue didn't fill within ${fill_timeout}s - checking current state"
            usage=$(get_queue_usage "${TARGET_QUEUE}" "${TARGET_VPN}")
            echo "$(date): Queue usage: ${usage}% - continuing anyway"
            break
        else
            sleep 10
        fi
    done
    
    # Wait for queue to drain before next attack
    wait_for_queue_to_drain "${TARGET_QUEUE}" "${TARGET_VPN}" "${DRAIN_THRESHOLD}"
    
    echo "$(date): Queue killer cycle completed - brief pause before next cycle"
    sleep 60
done
