#!/bin/bash
# cleanup-excess-consumers.sh - Clean up excess SDKPerf consumer processes

# Load environment
source "$(dirname "$0")/load-env.sh" || {
    echo "Error: Could not load environment. Make sure load-env.sh exists."
    exit 1
}

# Function to clean up excess consumers for a specific queue
cleanup_queue_consumers() {
    local queue_name="$1"
    local max_consumers="$2"
    
    echo "$(date): Checking consumers for ${queue_name}..."
    
    # Find SDKPerf consumer processes for this queue
    CONSUMER_PIDS=$(ps aux | grep -v grep | grep "sdkperf" | grep "${queue_name}" | awk '{print $2}')
    
    if [ -z "$CONSUMER_PIDS" ]; then
        echo "$(date): No consumers found for ${queue_name}"
        return
    fi
    
    CONSUMER_COUNT=$(echo "$CONSUMER_PIDS" | wc -l)
    echo "$(date): Found ${CONSUMER_COUNT} consumers for ${queue_name}"
    
    if [ "$CONSUMER_COUNT" -gt "$max_consumers" ]; then
        EXCESS_COUNT=$((CONSUMER_COUNT - max_consumers))
        echo "$(date): Killing ${EXCESS_COUNT} excess consumers..."
        
        # Kill the oldest excess consumers (keep the most recent ones)
        echo "$CONSUMER_PIDS" | head -n "$EXCESS_COUNT" | while read pid; do
            echo "$(date): Killing consumer PID ${pid}"
            kill "$pid" 2>/dev/null
        done
        
        sleep 2
        echo "$(date): Cleanup complete for ${queue_name}"
    else
        echo "$(date): Consumer count for ${queue_name} is within limits (${CONSUMER_COUNT}/${max_consumers})"
    fi
}

echo "$(date): Starting consumer cleanup..."

# Clean up excess consumers (allow max 2 per queue)
cleanup_queue_consumers "equity_order_queue" 2
cleanup_queue_consumers "baseline_queue" 2
cleanup_queue_consumers "bridge_receive_queue" 2
# Unused queues removed: options_order_queue, settlement_queue

echo "$(date): Consumer cleanup complete"

# Show current queue status after cleanup
echo "$(date): Current queue status:"
./scripts/queue-manager.sh status