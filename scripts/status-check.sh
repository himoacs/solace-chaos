#!/bin/bash

source scripts/load-env.sh

echo "🔍 Solace Chaos Environment Status"
echo "=================================="
echo ""

# Check if master orchestrator is running
if pgrep -f "master-chaos.sh" > /dev/null; then
    echo "✅ Master orchestrator: RUNNING"
else
    echo "❌ Master orchestrator: STOPPED"
fi

echo ""
echo "Component Status:"
echo "----------------"

components=(
    "baseline-market-data.sh"
    "baseline-trade-flow.sh"
    "queue-killer.sh"
    "multi-vpn-acl-violator.sh"
    "market-data-connection-bomber.sh"
    "cross-vpn-bridge-killer.sh"
)

for component in "${components[@]}"; do
    if pgrep -f "$component" > /dev/null; then
        echo "✅ $component: RUNNING"
    else
        echo "❌ $component: STOPPED"
    fi
done

echo ""
echo "Recent Log Activity:"
echo "-------------------"

for log in logs/*.log; do
    if [ -f "$log" ]; then
        echo "📄 $(basename $log): $(tail -1 $log 2>/dev/null | cut -c1-60)..."
    fi
done
