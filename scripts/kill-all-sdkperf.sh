#!/bin/bash

# Comprehensive SDKPerf process killer to handle zombies

echo "🧹 Cleaning up all SDKPerf processes..."

# Kill all Java SDKPerf processes
echo "Killing Java SDKPerf processes..."
pkill -f "SDKPerf_java" 2>/dev/null

# Kill SDKPerf shell scripts
echo "Killing SDKPerf shell scripts..."
pkill -f "sdkperf_java.sh" 2>/dev/null

# Kill baseline processes
echo "Killing baseline traffic generators..."
pkill -f "baseline-market-data" 2>/dev/null
pkill -f "baseline-trade-flow" 2>/dev/null

# Kill chaos components
echo "Killing chaos generators..."
pkill -f "connection-bomber" 2>/dev/null
pkill -f "queue-killer" 2>/dev/null
pkill -f "bridge-killer" 2>/dev/null
pkill -f "acl-violator" 2>/dev/null

# Wait a moment
sleep 2

# Force kill any remaining processes
echo "Force killing remaining processes..."
pkill -9 -f "SDKPerf_java" 2>/dev/null
pkill -9 -f "sdkperf_java.sh" 2>/dev/null
pkill -9 -f "baseline-" 2>/dev/null

# Show remaining java processes
echo "Remaining Java processes:"
ps aux | grep -E "(SDKPerf|sdkperf)" | grep -v grep || echo "✅ All SDKPerf processes cleaned up"

echo "🎉 SDKPerf cleanup completed"