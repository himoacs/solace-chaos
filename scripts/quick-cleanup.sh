#!/bin/bash
# Quick Cleanup Script - Just stops processes and cleans logs
# Preserves Terraform resources and configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log with color
log() {
    local color=$1
    shift
    echo -e "${color}$(date '+%Y-%m-%d %H:%M:%S') - $*${NC}"
}

main() {
    log "$BLUE" "=== Quick Cleanup - Stop Processes Only ==="
    
    # Stop chaos testing processes
    log "$YELLOW" "Stopping chaos testing processes..."
    pkill -f "run-chaos.sh" 2>/dev/null || true
    pkill -f "traffic-generator.sh" 2>/dev/null || true
    pkill -f "chaos-generator.sh" 2>/dev/null || true
    pkill -f "sdkperf" 2>/dev/null || true
    sleep 2
    
    # Force kill any remaining
    pkill -9 -f "run-chaos.sh" 2>/dev/null || true
    pkill -9 -f "traffic-generator.sh" 2>/dev/null || true
    pkill -9 -f "chaos-generator.sh" 2>/dev/null || true
    pkill -9 -f "sdkperf" 2>/dev/null || true
    
    # Clean up PID files and locks
    rm -f "$SCRIPT_DIR/../logs/pids"/*.pid 2>/dev/null || true
    rm -f "$SCRIPT_DIR/../tmp/pids"/*.pid 2>/dev/null || true
    rm -f "$SCRIPT_DIR/logs"/*.pid 2>/dev/null || true
    rm -f "$SCRIPT_DIR/logs"/*.lock 2>/dev/null || true
    
    log "$GREEN" "✅ All chaos processes stopped"
    log "$BLUE" "Broker resources and configuration preserved"
    log "$YELLOW" "To restart: bash run-chaos.sh &"
    log "$YELLOW" "For full cleanup: ./scripts/full-cleanup.sh"
}

main "$@"