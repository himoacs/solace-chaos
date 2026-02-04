#!/bin/bash

# Weekly chaos runner - automatically restarts chaos testing every week
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root
cd "$PROJECT_ROOT"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

WEEKLY_LOG="scripts/logs/weekly-chaos-$(date +%Y%m%d_%H%M%S).log"

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} ${message}"
    echo "[${timestamp}] ${message}" >> "$WEEKLY_LOG"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✅ ${message}${NC}"
    echo "SUCCESS: ${message}" >> "$WEEKLY_LOG"
}

cleanup_and_exit() {
    log_message "Weekly chaos runner shutting down"
    # Kill any remaining chaos processes
    pkill -f "master-chaos.sh" 2>/dev/null
    pkill -f "baseline-" 2>/dev/null
    pkill -f "sdkperf" 2>/dev/null
    exit 0
}

# Signal handlers
trap 'cleanup_and_exit' SIGTERM SIGINT SIGHUP

log_message "🔄 Weekly Chaos Testing Runner Started"
log_message "Will restart chaos testing every 7 days automatically"

cycle_count=0

while true; do
    cycle_count=$((cycle_count + 1))
    log_message "Starting chaos testing cycle #${cycle_count}"
    
    # Start the master chaos orchestrator
    bash scripts/master-chaos.sh
    
    # When master-chaos.sh exits (after 7 days), log and restart
    exit_code=$?
    log_message "Chaos testing cycle #${cycle_count} completed (exit code: ${exit_code})"
    log_success "Cycle completed successfully - restarting in 60 seconds"
    
    # Brief pause before restart
    sleep 60
done