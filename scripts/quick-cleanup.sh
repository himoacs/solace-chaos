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
    
    # Stop chaos daemon processes
    if [ -x "$SCRIPT_DIR/chaos-daemon.sh" ]; then
        log "$YELLOW" "Stopping chaos testing processes..."
        "$SCRIPT_DIR/chaos-daemon.sh" stop
    else
        log "$YELLOW" "Stopping processes manually..."
        pkill -f "baseline-market-data" 2>/dev/null || true
        pkill -f "baseline-trade-flow" 2>/dev/null || true  
        pkill -f "queue-killer" 2>/dev/null || true
        pkill -f "sdkperf" 2>/dev/null || true
        sleep 2
    fi
    
    # Clean up PID files and locks
    rm -f "$SCRIPT_DIR/logs"/*.pid 2>/dev/null || true
    rm -f "$SCRIPT_DIR/logs"/*.lock 2>/dev/null || true
    
    log "$GREEN" "✅ All chaos processes stopped"
    log "$BLUE" "Terraform resources and configuration preserved"
    log "$YELLOW" "To restart: ./scripts/chaos-daemon.sh start"
    log "$YELLOW" "For full cleanup: ./scripts/full-cleanup.sh"
}

main "$@"