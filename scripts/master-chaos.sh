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

# Component management using file-based PID storage (compatible with bash 3.2)
PID_DIR="scripts/logs/pids"
mkdir -p "$PID_DIR"

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
    local pid_file="$PID_DIR/${component_name}.pid"
    local start_time_file="$PID_DIR/${component_name}.start"
    
    if [[ -f "$pid_file" ]]; then
        local existing_pid=$(cat "$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            return 0
        fi
    fi
    
    log_message "Starting component: $component_name"
    
    "./$component" &
    local pid=$!
    echo "$pid" > "$pid_file"
    date +%s > "$start_time_file"
    
    log_success "Started $component_name (PID: $pid)"
}

check_component_health() {
    local component="$1"
    local component_name=$(basename "$component" .sh)
    local pid_file="$PID_DIR/${component_name}.pid"
    
    if [[ ! -f "$pid_file" ]]; then
        log_warning "Component $component_name is not running - restarting"
        start_component "$component"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
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
    
    for pid_file in "$PID_DIR"/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            local component_name=$(basename "$pid_file" .pid)
            
            if kill -0 "$pid" 2>/dev/null; then
                log_message "Stopping $component_name (PID: $pid)"
                kill -TERM "$pid"
                sleep 2
                kill -KILL "$pid" 2>/dev/null
            fi
            rm -f "$pid_file"
        fi
    done
    
    # Clean up start time files
    rm -f "$PID_DIR"/*.start
    
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
            local component_count=$(ls "$PID_DIR"/*.pid 2>/dev/null | wc -l)
            log_message "Orchestrator heartbeat - loop $loop_counter, components: $component_count managed"
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
