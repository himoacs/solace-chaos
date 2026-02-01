#!/bin/bash
# Chaos Testing Daemon - Master control script for background processes

source scripts/load-env.sh

# Configuration
DAEMON_NAME="chaos-daemon"
LOG_FILE="logs/${DAEMON_NAME}.log"
PID_DIR="logs"
LOCK_FILE="logs/${DAEMON_NAME}.lock"

# Component scripts
MARKET_DATA_SCRIPT="./traffic-generators/baseline-market-data.sh"
TRADE_FLOW_SCRIPT="./traffic-generators/baseline-trade-flow.sh"
QUEUE_KILLER_SCRIPT="./error-generators/queue-killer.sh"

# Create logs directory
mkdir -p logs

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${DAEMON_NAME}] $1" | tee -a "$LOG_FILE"
}

# Function to check if process is running
is_running() {
    local script_name="$1"
    local pid_file="logs/${script_name}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0  # Running
        else
            rm -f "$pid_file"  # Clean up stale PID file
            return 1  # Not running
        fi
    fi
    return 1  # Not running
}

# Function to start a component
start_component() {
    local script_path="$1"
    local component_name="$2"
    
    if is_running "$component_name"; then
        log "$component_name is already running"
        return 0
    fi
    
    log "Starting $component_name..."
    nohup bash "$script_path" >> "logs/${component_name}-daemon.log" 2>&1 &
    local pid=$!
    echo $pid > "logs/${component_name}.pid"
    
    sleep 2
    if ps -p $pid > /dev/null 2>&1; then
        log "$component_name started successfully (PID: $pid)"
        return 0
    else
        log "Failed to start $component_name"
        rm -f "logs/${component_name}.pid"
        return 1
    fi
}

# Function to stop a component
stop_component() {
    local component_name="$1"
    local pid_file="logs/${component_name}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            log "Stopping $component_name (PID: $pid)..."
            kill -TERM "$pid"
            sleep 5
            
            if ps -p "$pid" > /dev/null 2>&1; then
                log "Force killing $component_name..."
                kill -KILL "$pid"
            fi
        fi
        rm -f "$pid_file"
    fi
    
    # Kill any remaining processes by pattern
    pkill -f "$component_name" > /dev/null 2>&1
    log "$component_name stopped"
}

# Function to show status
show_status() {
    log "=== Chaos Testing Environment Status ==="
    
    local components=("baseline-market-data" "baseline-trade-flow" "queue-killer")
    local all_running=true
    
    for component in "${components[@]}"; do
        if is_running "$component"; then
            local pid=$(cat "logs/${component}.pid")
            log "✅ $component: RUNNING (PID: $pid)"
        else
            log "❌ $component: STOPPED"
            all_running=false
        fi
    done
    
    if $all_running; then
        log "🎉 All chaos testing components are running"
    else
        log "⚠️  Some components are not running"
    fi
    
    # Show recent activity
    log "=== Recent Activity ==="
    if [ -f "logs/baseline-market-data.log" ]; then
        log "Market Data: $(tail -1 logs/baseline-market-data.log 2>/dev/null || echo 'No logs')"
    fi
}

# Function to start all components
start_all() {
    log "Starting all chaos testing components..."
    
    # Check if another daemon is running
    if [ -f "$LOCK_FILE" ]; then
        local existing_pid=$(cat "$LOCK_FILE")
        if ps -p "$existing_pid" > /dev/null 2>&1; then
            log "Another chaos daemon is already running (PID: $existing_pid)"
            exit 1
        else
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # Create lock file
    echo $$ > "$LOCK_FILE"
    
    start_component "$MARKET_DATA_SCRIPT" "baseline-market-data"
    sleep 5
    start_component "$TRADE_FLOW_SCRIPT" "baseline-trade-flow"
    sleep 5  
    start_component "$QUEUE_KILLER_SCRIPT" "queue-killer"
    
    log "All components started. Use 'chaos-daemon.sh status' to check status"
}

# Function to stop all components
stop_all() {
    log "Stopping all chaos testing components..."
    
    stop_component "baseline-market-data"
    stop_component "baseline-trade-flow"
    stop_component "queue-killer"
    
    rm -f "$LOCK_FILE"
    log "All components stopped"
}

# Function to restart all components
restart_all() {
    log "Restarting all chaos testing components..."
    stop_all
    sleep 5
    start_all
}

# Main execution
case "$1" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        restart_all
        ;;
    status)
        show_status
        ;;
    daemon)
        # Run as a daemon - keep monitoring and restarting failed components
        start_all
        log "Running in daemon mode - monitoring components..."
        
        while [ -f "$LOCK_FILE" ]; do
            sleep 60  # Check every minute
            
            # Restart any failed components
            if ! is_running "baseline-market-data"; then
                log "Market data component failed, restarting..."
                start_component "$MARKET_DATA_SCRIPT" "baseline-market-data"
            fi
            
            if ! is_running "baseline-trade-flow"; then
                log "Trade flow component failed, restarting..."
                start_component "$TRADE_FLOW_SCRIPT" "baseline-trade-flow"
            fi
            
            if ! is_running "queue-killer"; then
                log "Queue killer component failed, restarting..."
                start_component "$QUEUE_KILLER_SCRIPT" "queue-killer"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|daemon}"
        echo ""
        echo "Commands:"
        echo "  start   - Start all chaos testing components in background"
        echo "  stop    - Stop all chaos testing components"
        echo "  restart - Restart all chaos testing components" 
        echo "  status  - Show status of all components"
        echo "  daemon  - Run as daemon with automatic restart of failed components"
        echo ""
        echo "Examples:"
        echo "  ./chaos-daemon.sh start     # Start everything"
        echo "  ./chaos-daemon.sh status    # Check what's running"
        echo "  ./chaos-daemon.sh daemon &  # Run as background daemon"
        exit 1
        ;;
esac