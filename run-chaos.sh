#!/bin/bash
# run-chaos.sh - Single orchestrator for all chaos testing components
# Runs continuously until manually stopped, manages all generators with health monitoring
# Compatible with bash 3.2+ and zsh

# Get script directory (bash 3.2 and zsh compatible)
if [[ -n "$BASH_VERSION" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # zsh
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
fi
cd "$SCRIPT_DIR"

source scripts/load-env.sh || {
    echo "ERROR: Failed to load environment"
    exit 1
}

# Configuration
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-300}"  # 5 minutes
LOG_FILE="logs/chaos-orchestrator.log"
PID_DIR="logs/pids"
RESTART_DELAY=10  # Seconds to wait before restarting failed component

# Ensure directories exist
mkdir -p logs "$PID_DIR"

# Track running components (bash 3.2 compatible - using indexed arrays)
COMPONENT_NAMES=()
COMPONENT_PIDS=()
COMPONENT_RESTARTS=()

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ORCHESTRATOR] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Cleanup function
cleanup() {
    log "Shutdown signal received - stopping all components..."
    
    local i=0
    while [[ $i -lt ${#COMPONENT_NAMES[@]} ]]; do
        local component="${COMPONENT_NAMES[$i]}"
        local pid="${COMPONENT_PIDS[$i]}"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log "Stopping $component (PID: $pid)"
            kill -TERM "$pid" 2>/dev/null || true
        fi
        ((i++))
    done
    
    # Wait for graceful shutdown
    sleep 5
    
    # Force kill any remaining processes
    pkill -f "traffic-generator.sh" 2>/dev/null || true
    pkill -f "chaos-generator.sh" 2>/dev/null || true
    
    log "All components stopped - orchestrator shutting down"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Check if component is running
is_running() {
    local pid="$1"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# Start traffic generator
start_traffic_generator() {
    local mode="$1"
    local component_name="traffic-${mode}"
    
    log "Starting traffic generator: $mode"
    
    ./traffic-generators/traffic-generator.sh --mode "$mode" >> "logs/${component_name}.log" 2>&1 &
    local pid=$!
    
    COMPONENT_NAMES+=("$component_name")
    COMPONENT_PIDS+=("$pid")
    COMPONENT_RESTARTS+=("0")
    
    log "✓ Traffic generator $mode started (PID: $pid)"
}

# Start chaos generator
start_chaos_generator() {
    local scenario="$1"
    shift
    local extra_args="$@"
    local component_name="chaos-${scenario}"
    
    log "Starting chaos generator: $scenario"
    
    ./error-generators/chaos-generator.sh --scenario "$scenario" $extra_args >> "logs/${component_name}.log" 2>&1 &
    local pid=$!
    
    COMPONENT_NAMES+=("$component_name")
    COMPONENT_PIDS+=("$pid")
    COMPONENT_RESTARTS+=("0")
    
    log "✓ Chaos generator $scenario started (PID: $pid)"
}

# Health check and restart failed components
health_check() {
    log "Running health check on all components..."
    
    local failed_count=0
    local running_count=0
    
    local i=0
    while [[ $i -lt ${#COMPONENT_NAMES[@]} ]]; do
        local component="${COMPONENT_NAMES[$i]}"
        local pid="${COMPONENT_PIDS[$i]}"
        
        if is_running "$pid"; then
            running_count=$((running_count + 1))
        else
            failed_count=$((failed_count + 1))
            log_error "Component $component (PID: $pid) has stopped unexpectedly"
            
            # Track restart count
            local restart_count=$((${COMPONENT_RESTARTS[$i]} + 1))
            COMPONENT_RESTARTS[$i]=$restart_count
            
            log "Restarting $component (attempt #$restart_count) in ${RESTART_DELAY}s..."
            sleep "$RESTART_DELAY"
            
            # Restart based on component type
            if [[ "$component" == traffic-* ]]; then
                local mode="${component#traffic-}"
                start_traffic_generator "$mode"
            elif [[ "$component" == chaos-* ]]; then
                local scenario="${component#chaos-}"
                # Restart with default parameters
                case "$scenario" in
                    queue-killer)
                        start_chaos_generator "queue-killer"
                        ;;
                    acl-violation)
                        start_chaos_generator "acl-violation"
                        ;;
                    connection-storm)
                        start_chaos_generator "connection-storm"
                        ;;
                    bridge-stress)
                        if [[ "${ENABLE_CROSS_VPN_BRIDGE}" == "true" ]]; then
                            start_chaos_generator "bridge-stress"
                        fi
                        ;;
                esac
            fi
        fi
        ((i++))
    done
    
    log "Health check complete: $running_count running, $failed_count restarted"
}

# Trim all log files that exceed max size
trim_logs() {
    local max_size=$((${LOG_MAX_SIZE_MB:-50} * 1024 * 1024))
    local keep_lines=5000
    local trimmed_count=0
    
    log "Checking log files for trimming (max size: ${LOG_MAX_SIZE_MB:-50}MB)..."
    
    # Find all .log files in logs directory
    for log_file in logs/*.log; do
        [[ ! -f "$log_file" ]] && continue
        
        # Get file size (cross-platform compatible)
        local file_size=0
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            file_size=$(stat -f%z "$log_file" 2>/dev/null || echo "0")
        else
            # Linux
            file_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
        fi
        
        if (( file_size > max_size )); then
            local file_mb=$((file_size / 1024 / 1024))
            log "Trimming $log_file (${file_mb}MB > ${LOG_MAX_SIZE_MB:-50}MB)..."
            
            # Keep last N lines
            tail -n "$keep_lines" "$log_file" > "${log_file}.tmp" 2>/dev/null
            if [[ -f "${log_file}.tmp" ]]; then
                mv "${log_file}.tmp" "$log_file"
                trimmed_count=$((trimmed_count + 1))
            fi
        fi
    done
    
    if (( trimmed_count > 0 )); then
        log "Trimmed $trimmed_count log file(s) to last $keep_lines lines each"
    else
        log "No log files require trimming"
    fi
}

# Display status
show_status() {
    log "=========================================="
    log "Chaos Testing Orchestrator Status"
    log "=========================================="
    
    local i=0
    while [[ $i -lt ${#COMPONENT_NAMES[@]} ]]; do
        local component="${COMPONENT_NAMES[$i]}"
        local pid="${COMPONENT_PIDS[$i]}"
        local restart_count="${COMPONENT_RESTARTS[$i]}"
        
        if is_running "$pid"; then
            log "✓ $component (PID: $pid, Restarts: $restart_count)"
        else
            log "✗ $component (PID: $pid, Restarts: $restart_count) - NOT RUNNING"
        fi
        ((i++))
    done
    
    log "=========================================="
}

# Main startup sequence
startup() {
    log "=========================================="
    log "Chaos Testing Orchestrator Starting"
    log "=========================================="
    log "Configuration:"
    log "  - Health check interval: ${HEALTH_CHECK_INTERVAL}s"
    log "  - Restart delay: ${RESTART_DELAY}s"
    log "  - Log file: $LOG_FILE"
    log "=========================================="
    
    # Validate environment
    if [[ ! -f "$SDKPERF_SCRIPT_PATH" ]]; then
        log_error "SDKPerf not found at: $SDKPERF_SCRIPT_PATH"
        log_error "Please run bootstrap script first: ./scripts/bootstrap-chaos-environment.sh"
        exit 1
    fi
    
    # Start traffic generators
    log "Starting traffic generators..."
    start_traffic_generator "market-data"
    start_traffic_generator "trade-flow"
    
    sleep 2
    
    # Start chaos generators
    log "Starting chaos generators..."
    start_chaos_generator "queue-killer"
    start_chaos_generator "acl-violation"
    start_chaos_generator "connection-storm"
    
    # Start bridge stress only if bridges are enabled
    if [[ "${ENABLE_CROSS_VPN_BRIDGE}" == "true" ]]; then
        start_chaos_generator "bridge-stress"
    else
        log "Skipping bridge-stress (bridges disabled in config)"
    fi
    
    sleep 2
    
    log "=========================================="
    log "All components started successfully"
    log "=========================================="
    show_status
}

# Main monitoring loop
main_loop() {
    local iteration=0
    
    while true; do
        sleep "$HEALTH_CHECK_INTERVAL"
        
        iteration=$((iteration + 1))
        log "Monitoring cycle #$iteration"
        
        # Perform health check and restart failed components
        health_check
        
        # Show status every 5 health checks
        if (( iteration % 5 == 0 )); then
            show_status
        fi
        
        # Cleanup old logs every 10 health checks (if log file > max size)
        if (( iteration % 10 == 0 )); then
            trim_logs
        fi
    done
}

# Main execution
main() {
    startup
    main_loop
}

# Run main function
main
