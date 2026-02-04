#!/bin/bash

# Queue Management Script - For manual queue operations during chaos testing
source scripts/load-env.sh

show_usage() {
    echo "Queue Management Commands:"
    echo "=========================="
    echo ""
    echo "  $0 status                    # Show all queue usage"
    echo "  $0 clear <queue> <vpn>       # Immediate SEMP API clear (recommended)"
    echo "  $0 drain <queue> <vpn>       # Consumer-based drain (slower)"
    echo "  $0 clear-all                 # Clear all trading queues (immediate)"
    echo "  $0 drain-all                 # Drain all queues with consumers"
    echo "  $0 monitor                   # Real-time queue monitoring"
    echo ""
    echo "Examples:"
    echo "  $0 clear equity_order_queue trading-vpn     # Immediate clear (trading VPN)"
    echo "  $0 clear cross_market_data_queue default    # Clear from default VPN"
    echo "  $0 drain baseline_queue trading-vpn         # Consumer drain"
    echo "  $0 clear-all                                # Emergency clear all"
}

show_queue_status() {
    echo "📊 Current Queue Status"
    echo "======================"
    echo ""
    
    local queues=(
        "equity_order_queue:trading-vpn"
        "baseline_queue:trading-vpn"
        "bridge_receive_queue:trading-vpn"
        "cross_market_data_queue:default"
        "risk_calculation_queue:default"
    )
    
    for queue_vpn in "${queues[@]}"; do
        local queue_name="${queue_vpn%%:*}"
        local vpn_name="${queue_vpn##*:}"
        local usage=$(get_queue_usage "$queue_name" "$vpn_name")
        
        # Get collections message count and spooled byte count
        local response=$(curl -s -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
            "${SOLACE_SEMP_URL}/SEMP/v2/monitor/msgVpns/${vpn_name}/queues/${queue_name}" 2>/dev/null)
        
        local collections_count=$(echo "$response" | jq -r '.collections.msgs.count // 0')
        local spooled_count=$(echo "$response" | grep -o '"spooledMsgCount":[0-9]*' | cut -d':' -f2 | head -1)
        local spool_bytes=$(echo "$response" | grep -o '"spooledByteCount":[0-9]*' | cut -d':' -f2 | head -1)
        
        if [ -z "$collections_count" ]; then collections_count="?"; fi
        if [ -z "$spooled_count" ]; then spooled_count="?"; fi
        if [ -z "$spool_bytes" ]; then 
            spool_bytes="?"
        else 
            # Convert bytes to MB for readability
            spool_bytes="$((spool_bytes / 1024 / 1024))MB"
        fi
        
        if [ "$usage" -gt 80 ]; then
            echo "🔴 $queue_name ($vpn_name): ${usage}% CRITICAL (${collections_count} avail, ${spooled_count} total, ${spool_bytes})"
        elif [ "$usage" -gt 50 ]; then
            echo "🟡 $queue_name ($vpn_name): ${usage}% WARNING (${collections_count} avail, ${spooled_count} total, ${spool_bytes})"
        else
            echo "🟢 $queue_name ($vpn_name): ${usage}% OK (${collections_count} avail, ${spooled_count} total, ${spool_bytes})"
        fi
    done
}

clear_all_queues() {
    echo "🚀 Emergency clear all queues (SEMP API)"
    echo "======================================="
    echo ""
    
    local queues=(
        "equity_order_queue:trading-vpn"
        "baseline_queue:trading-vpn"
        "bridge_receive_queue:trading-vpn"
        "cross_market_data_queue:default"
        "risk_calculation_queue:default"
    )
    
    for queue_vpn in "${queues[@]}"; do
        local queue_name="${queue_vpn%%:*}"
        local vpn_name="${queue_vpn##*:}"
        clear_queue_messages "$queue_name" "$vpn_name"
    done
    
    echo ""
    echo "All queues cleared. Current status:"
    show_queue_status
}

drain_all_queues() {
    echo "🚀 Emergency drain all queues (Consumer-based)"
    echo "=============================================="
    echo ""
    
    drain_queue_manually "equity_order_queue" "trading-vpn" "consumer" &
    drain_queue_manually "baseline_queue" "trading-vpn" "consumer" &
    drain_queue_manually "bridge_receive_queue" "trading-vpn" "consumer" &
    drain_queue_manually "cross_market_data_queue" "default" "consumer" &
    drain_queue_manually "risk_calculation_queue" "default" "consumer" &
    
    echo "Waiting for all drain operations to complete..."
    wait
    
    echo ""
    show_queue_status
}

monitor_queues() {
    echo "📈 Real-time Queue Monitor (Press Ctrl+C to stop)"
    echo "================================================="
    echo ""
    
    while true; do
        clear
        echo "$(date)"
        echo ""
        show_queue_status
        echo ""
        echo "Refreshing in 10 seconds..."
        sleep 10
    done
}

# Main execution
case "${1:-}" in
    "status"|"s")
        show_queue_status
        ;;
    "clear"|"c")
        if [ $# -lt 3 ]; then
            echo "❌ Error: clear requires queue name and VPN name"
            echo "Usage: $0 clear <queue_name> <vpn_name>"
            exit 1
        fi
        clear_queue_messages "$2" "$3"
        ;;
    "drain"|"d")
        if [ $# -lt 3 ]; then
            echo "❌ Error: drain requires queue name and VPN name"
            echo "Usage: $0 drain <queue_name> <vpn_name>"
            exit 1
        fi
        drain_queue_manually "$2" "$3" "consumer"
        ;;
    "clear-all"|"ca")
        clear_all_queues
        ;;
    "drain-all"|"da")
        drain_all_queues
        ;;
    "monitor"|"m")
        monitor_queues
        ;;
    "help"|"h"|"")
        show_usage
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac