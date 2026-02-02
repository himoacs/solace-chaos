#!/bin/bash

# Master chaos orchestrator - runs all components with health monitoring
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
source scripts/load-env.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MASTER_LOG="logs/master-chaos-$(date +%Y%m%d_%H%M%S).log"
HEALTH_CHECK_INTERVAL=300  # 5 minutes

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

# Component management
declare -A COMPONENT_PIDS
declare -A COMPONENT_START_TIMES

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
    
    if [[ -n "${COMPONENT_PIDS[$component]}" ]] && kill -0 "${COMPONENT_PIDS[$component]}" 2>/dev/null; then
        return 0
    fi
    
    log_message "Starting component: $component_name"
    
    "./$component" &
    local pid=$!
    COMPONENT_PIDS[$component]=$pid
    COMPONENT_START_TIMES[$component]=$(date +%s)
    
    log_success "Started $component_name (PID: $pid)"
}

check_component_health() {
    local component="$1"
    local component_name=$(basename "$component" .sh)
    local pid="${COMPONENT_PIDS[$component]}"
    
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        log_warning "Component $component_name is not running - restarting"
        start_component "$component"
        return 1
    fi
    
    return 0
}

cleanup_and_exit() {
    local signal=$1
    log_message "Received signal $signal - shutting down gracefully"
    
    for component in "${!COMPONENT_PIDS[@]}"; do
        local pid="${COMPONENT_PIDS[$component]}"
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
            
            for component in "${TRAFFIC_GENERATORS[@]}" "${ERROR_GENERATORS[@]}"; do
                check_component_health "$component"
            done
            
            last_health_check=$current_time
        fi
        
        # Heartbeat every hour
        if (( loop_counter % 120 == 0 )); then
            log_message "Orchestrator heartbeat - loop $loop_counter, components: ${#COMPONENT_PIDS[@]} managed"
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
