#!/bin/bash
# Full Environment Cleanup Script - Resets entire chaos testing environment
# This script stops all processes, cleans logs, and optionally destroys Terraform resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/full-cleanup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create logs directory
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log with timestamp and color
log() {
    local color=$1
    shift
    echo -e "${color}$(date '+%Y-%m-%d %H:%M:%S') - $*${NC}" | tee -a "$LOG_FILE"
}

# Function to prompt for confirmation
confirm() {
    while true; do
        read -p "$1 (y/N): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# Function to stop all chaos processes
stop_processes() {
    log "$YELLOW" "Stopping all chaos testing processes..."
    
    # Use the daemon to stop everything cleanly
    if [ -x "$SCRIPT_DIR/chaos-daemon.sh" ]; then
        log "$BLUE" "Using chaos daemon to stop processes..."
        "$SCRIPT_DIR/chaos-daemon.sh" stop 2>&1 | tee -a "$LOG_FILE"
    else
        log "$YELLOW" "Chaos daemon not found, using manual process termination..."
        
        # Kill processes by pattern
        local patterns=("baseline-market-data" "baseline-trade-flow" "queue-killer" "sdkperf")
        
        for pattern in "${patterns[@]}"; do
            local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
            if [ -n "$pids" ]; then
                log "$YELLOW" "Killing processes matching '$pattern': $pids"
                pkill -f "$pattern" 2>/dev/null || true
                sleep 2
                
                # Force kill if still running
                local remaining_pids=$(pgrep -f "$pattern" 2>/dev/null || true)
                if [ -n "$remaining_pids" ]; then
                    log "$RED" "Force killing remaining processes: $remaining_pids"
                    pkill -9 -f "$pattern" 2>/dev/null || true
                fi
            fi
        done
    fi
    
    log "$GREEN" "✅ All chaos processes stopped"
}

# Function to clean up log files
cleanup_logs() {
    log "$YELLOW" "Cleaning up log files..."
    
    if [ -d "$SCRIPT_DIR/logs" ]; then
        # Create backup of logs if they exist and are not empty
        local log_backup_dir="$SCRIPT_DIR/log-backups/$(date +%Y%m%d_%H%M%S)"
        
        local has_logs=false
        for logfile in "$SCRIPT_DIR/logs"/*.log; do
            if [ -f "$logfile" ] && [ -s "$logfile" ]; then
                has_logs=true
                break
            fi
        done
        
        if [ "$has_logs" = true ]; then
            if confirm "Do you want to backup existing logs before cleaning?"; then
                mkdir -p "$log_backup_dir"
                cp "$SCRIPT_DIR/logs"/*.log "$log_backup_dir/" 2>/dev/null || true
                cp "$SCRIPT_DIR/logs"/*.pid "$log_backup_dir/" 2>/dev/null || true
                log "$GREEN" "Logs backed up to: $log_backup_dir"
            fi
        fi
        
        # Clean up log files
        rm -f "$SCRIPT_DIR/logs"/*.log
        rm -f "$SCRIPT_DIR/logs"/*.pid
        rm -f "$SCRIPT_DIR/logs"/*.lock
        
        log "$GREEN" "✅ Log files cleaned"
    else
        log "$YELLOW" "No logs directory found"
    fi
}

# Function to clean up SDKPerf extracted files
cleanup_sdkperf() {
    if confirm "Do you want to clean up extracted SDKPerf files? (You'll need to re-run bootstrap to extract them)"; then
        log "$YELLOW" "Cleaning up SDKPerf extracted files..."
        
        if [ -d "$SCRIPT_DIR/sdkperf-tools/extracted" ]; then
            rm -rf "$SCRIPT_DIR/sdkperf-tools/extracted"
            log "$GREEN" "✅ SDKPerf extracted files removed"
        else
            log "$YELLOW" "No extracted SDKPerf files found"
        fi
    fi
}

# Function to reset environment variables
reset_env() {
    if [ -f "$SCRIPT_DIR/.env.template" ]; then
        if confirm "Do you want to reset the .env file to template defaults? (This will lose your current broker configuration)"; then
            log "$YELLOW" "Resetting .env file..."
            
            if [ -f "$SCRIPT_DIR/.env" ]; then
                # Backup current .env
                cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)"
                log "$GREEN" "Current .env backed up"
            fi
            
            cp "$SCRIPT_DIR/.env.template" "$SCRIPT_DIR/.env"
            log "$GREEN" "✅ .env reset to template defaults"
            log "$YELLOW" "⚠️  You will need to reconfigure broker settings in .env"
        fi
    else
        log "$YELLOW" "No .env.template found, skipping reset option"
    fi
}

# Function to show cleanup summary
show_summary() {
    log "$BLUE" "=== Cleanup Summary ==="
    log "$GREEN" "The following actions were completed:"
    log "$GREEN" "  ✅ All chaos testing processes stopped"
    log "$GREEN" "  ✅ Log files cleaned (with optional backup)"
    
    if [ "$terraform_cleaned" = true ]; then
        log "$GREEN" "  ✅ Terraform resources destroyed"
    else
        log "$YELLOW" "  ⏸️  Terraform resources preserved (use terraform-cleanup.sh separately)"
    fi
    
    log "$BLUE" "Environment is now clean and ready for fresh setup!"
    log "$YELLOW" "To restart the environment, run: ./scripts/bootstrap-chaos-environment.sh"
}

# Main execution
main() {
    log "$BLUE" "=== Solace Chaos Environment - Full Cleanup ==="
    
    # Show what this script will do
    log "$YELLOW" "This script will:"
    log "$YELLOW" "  1. Stop all chaos testing processes"
    log "$YELLOW" "  2. Clean up log files (with optional backup)"  
    log "$YELLOW" "  3. Optionally clean up SDKPerf extracted files"
    log "$YELLOW" "  4. Optionally run Terraform cleanup"
    echo ""
    
    if ! confirm "Do you want to proceed with the cleanup?"; then
        log "$YELLOW" "Cleanup cancelled by user"
        exit 0
    fi
    
    # Stop all processes
    stop_processes
    
    # Clean up logs
    cleanup_logs
    
    # Optional SDKPerf cleanup
    cleanup_sdkperf
    
    # Optional Terraform cleanup
    terraform_cleaned=false
    if confirm "Do you want to run Terraform cleanup (destroy all broker resources)?"; then
        log "$BLUE" "Running Terraform cleanup..."
        if [ -x "$SCRIPT_DIR/terraform-cleanup.sh" ]; then
            "$SCRIPT_DIR/terraform-cleanup.sh"
            terraform_cleaned=true
        else
            log "$RED" "terraform-cleanup.sh not found or not executable"
            log "$YELLOW" "You can run it manually later if needed"
        fi
    fi
    
    # Show summary
    show_summary
    
    log "$GREEN" "🎉 Full environment cleanup completed!"
}

# Handle script interruption
trap 'log "$RED" "Cleanup interrupted by user"; exit 130' INT TERM

# Run main function
main "$@"