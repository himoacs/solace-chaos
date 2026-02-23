#!/bin/bash

source scripts/load-env.sh

echo "🔍 Solace Chaos Environment Status"
echo "=================================="
echo ""

# Check if main orchestrator is running
if pgrep -f "run-chaos.sh" > /dev/null; then
    echo "✅ Main orchestrator (run-chaos.sh): RUNNING"
else
    echo "❌ Main orchestrator (run-chaos.sh): STOPPED"
fi

echo ""
echo "Component Status:"
echo "----------------"

components=(
    "traffic-generator.sh"
    "chaos-generator.sh"
)

for component in "${components[@]}"; do
    count=$(pgrep -f "$component" | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        echo "✅ $component: RUNNING ($count processes)"
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
