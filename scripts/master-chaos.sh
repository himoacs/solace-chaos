#!/bin/bash

# Master chaos orchestrator - runs all components with health monitoring
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root for consistent paths
cd "$PROJECT_ROOT"

# Load environment variables
source scripts/load-env.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MASTER_LOG="scripts/logs/master-chaos-$(date +%Y%m%d_%H%M%S).log"
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-300}  # 5 minutes (configurable via .env)
CONSUMER_CLEANUP_FREQUENCY=${CONSUMER_CLEANUP_FREQUENCY:-10}  # Every 10 health checks (~5 minutes)

# Components to manage
TRAFFIC_GENERATORS=(
    "traffic-generators/baseline-market-data.sh"
    "traffic-generators/baseline-trade-flow.sh"
)

ERROR_GENERATORS=(
    "error-generators/queue-killer.sh"
    "error-generators/multi-vpn-acl-violator.sh"
    "error-generators/market-data-connection-bomber.sh"
    "error-generators/cross-vpn-bridge-killer.sh"
)

# Component management - bash 3.2 compatible arrays
COMPONENT_PIDS=()
COMPONENT_NAMES=()
COMPONENT_START_TIMES=()

find_component_index() {
    local component="$1"
    local i
    for i in "${!COMPONENT_NAMES[@]}"; do
        if [[ "${COMPONENT_NAMES[i]}" == "$component" ]]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
}

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} ${message}"
    echo "[${timestamp}] ${message}" >> "$MASTER_LOG"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✅ ${message}${NC}"
    echo "SUCCESS: ${message}" >> "$MASTER_LOG"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  ${message}${NC}"
    echo "WARNING: ${message}" >> "$MASTER_LOG"
}

log_error() {
    local message="$1"
    echo -e "${RED}❌ ${message}${NC}"
    echo "ERROR: ${message}" >> "$MASTER_LOG"
}

start_component() {
    local component="$1"
    local component_name=$(basename "$component" .sh)
    local existing_index
    
    existing_index=$(find_component_index "$component")
    if [[ "$existing_index" != "-1" ]] && kill -0 "${COMPONENT_PIDS[existing_index]}" 2>/dev/null; then
        return 0
    fi
    
    log_message "Starting component: $component_name"
    
    "./$component" &
    local pid=$!
    
    if [[ "$existing_index" == "-1" ]]; then
        COMPONENT_NAMES+=("$component")
        COMPONENT_PIDS+=("$pid")
        COMPONENT_START_TIMES+=($(date +%s))
    else
        COMPONENT_PIDS[existing_index]="$pid"
        COMPONENT_START_TIMES[existing_index]=$(date +%s)
    fi
    
    log_success "Started $component_name (PID: $pid)"
}

check_component_health() {
    local component="$1"
    local component_name=$(basename "$component" .sh)
    local component_index
    local pid
    
    component_index=$(find_component_index "$component")
    if [[ "$component_index" == "-1" ]]; then
        log_error "No PID tracked for $component_name"
        start_component "$component"
        return 1
    fi
    
    pid="${COMPONENT_PIDS[component_index]}"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        log_warning "$component_name (PID: $pid) is not running - restarting"
        start_component "$component"
        return 1
    fi
    
    return 0
}

cleanup_and_exit() {
    local signal=$1
    log_message "Received signal $signal - shutting down gracefully"
    
    local i
    for i in "${!COMPONENT_NAMES[@]}"; do
        local component="${COMPONENT_NAMES[i]}"
        local pid="${COMPONENT_PIDS[i]}"
        local component_name=$(basename "$component" .sh)
        
        if kill -0 "$pid" 2>/dev/null; then
            log_message "Stopping $component_name (PID: $pid)"
            kill -TERM "$pid"
            sleep 2
            kill -KILL "$pid" 2>/dev/null
        fi
    done
    
    log_message "Master chaos orchestrator shutdown completed"
    exit 0
}

# Signal handlers
trap 'cleanup_and_exit SIGTERM' SIGTERM
trap 'cleanup_and_exit SIGINT' SIGINT
trap 'cleanup_and_exit SIGHUP' SIGHUP

# Main orchestration loop
main_orchestrator_loop() {
    local loop_counter=0
    local last_health_check=0
    
    log_message "Starting master chaos orchestrator"
    log_message "Broker: ${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}"
    
    # Start all components
    for component in "${TRAFFIC_GENERATORS[@]}" "${ERROR_GENERATORS[@]}"; do
        start_component "$component"
        sleep 2
    done
    
    log_success "All components started - entering monitoring loop"
    echo ""
    echo "Master orchestrator running. Press Ctrl+C to stop."
    
    while true; do
        current_time=$(date +%s)
        loop_counter=$((loop_counter + 1))
        
        # Health check cycle
        if (( current_time - last_health_check >= HEALTH_CHECK_INTERVAL )); then
            log_message "Health check cycle $loop_counter"
            
            # Run periodic consumer cleanup every N health checks
            if (( loop_counter % CONSUMER_CLEANUP_FREQUENCY == 0 )); then
                log_message "Running periodic consumer cleanup..."
                bash scripts/cleanup-excess-consumers.sh >> "$MASTER_LOG" 2>&1
                log_success "Consumer cleanup completed"
            fi
            
            for component in "${TRAFFIC_GENERATORS[@]}" "${ERROR_GENERATORS[@]}"; do
                check_component_health "$component"
            done
            
            last_health_check=$current_time
        fi
        
        # Heartbeat every hour
        if (( loop_counter % 120 == 0 )); then
            log_message "Orchestrator heartbeat - loop $loop_counter, components: ${#COMPONENT_NAMES[@]} managed"
        fi
        
        sleep 30
    done
}

# Main execution
main() {
    echo ""
    echo "🚀 Solace Chaos Testing Master Orchestrator"
    echo "==========================================="
    echo ""
    
    # Validate environment
    if [ ! -f "scripts/load-env.sh" ]; then
        echo "❌ Environment script not found. Run bootstrap-chaos-environment.sh first."
        exit 1
    fi
    
    # Start orchestration
    main_orchestrator_loop
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
