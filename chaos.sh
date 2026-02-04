#!/bin/bash

# Simple wrapper to maintain backward compatibility
# All main scripts have been moved to scripts/ directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to clean up old log files (older than 24 hours)
cleanup_old_logs() {
    echo "🧹 Cleaning up log files older than 24 hours..."
    
    # Clean main logs directory (files older than 1440 minutes = 24 hours)
    find "$SCRIPT_DIR/logs" -name "*.log" -type f -mmin +1440 -exec rm -f {} \; 2>/dev/null || true
    
    # Clean scripts/logs directory
    find "$SCRIPT_DIR/scripts/logs" -name "*.log" -type f -mmin +1440 -exec rm -f {} \; 2>/dev/null || true
    find "$SCRIPT_DIR/scripts/logs" -name "*.start" -type f -mmin +1440 -exec rm -f {} \; 2>/dev/null || true
    
    # Clean log backups (older than 7 days)
    find "$SCRIPT_DIR/scripts/log-backups" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    
    echo "✅ Log cleanup completed"
}

case "$1" in
    "bootstrap"|"setup"|"init")
        exec "$SCRIPT_DIR/scripts/bootstrap-chaos-environment.sh" "${@:2}"
        ;;
    "start"|"run"|"chaos")
        # Clean up old logs before starting
        cleanup_old_logs
        exec "$SCRIPT_DIR/scripts/master-chaos.sh" "${@:2}"
        ;;
    "weekly"|"week")
        exec "$SCRIPT_DIR/scripts/weekly-chaos-runner.sh" "${@:2}"
        ;;
    "stop"|"kill")
        # Kill all chaos testing processes
        echo "🛑 Stopping all chaos testing processes..."
        
        # Kill shell scripts first
        pkill -f "baseline-market-data.sh" 2>/dev/null
        pkill -f "baseline-trade-flow.sh" 2>/dev/null
        pkill -f "master-chaos.sh" 2>/dev/null
        pkill -f "queue-killer.sh" 2>/dev/null
        pkill -f "multi-vpn-acl-violator.sh" 2>/dev/null
        pkill -f "market-data-connection-bomber.sh" 2>/dev/null
        pkill -f "cross-vpn-bridge-killer.sh" 2>/dev/null
        
        # Kill underlying Java SDKPerf processes
        pkill -f "SDKPerf_java" 2>/dev/null
        pkill -f "sdkperf_java.sh" 2>/dev/null
        
        # Wait a moment then force kill any remaining
        sleep 2
        pkill -9 -f "SDKPerf_java" 2>/dev/null
        pkill -9 -f "sdkperf_java.sh" 2>/dev/null
        
        # Clean up PID files
        rm -f scripts/logs/*.pid 2>/dev/null
        rm -f scripts/logs/*.start_time 2>/dev/null
        
        echo "✅ All chaos testing processes stopped"
        ;;
    "daemon"|"manage")
        exec "$SCRIPT_DIR/scripts/chaos-daemon.sh" "${@:2}"
        ;;
    "cleanup"|"clean")
        case "${2:-all}" in
            "logs")
                cleanup_old_logs
                ;;
            "all"|*)
                cleanup_old_logs
                exec "$SCRIPT_DIR/scripts/full-cleanup.sh" "${@:2}"
                ;;
        esac
        ;;
    "quick-cleanup"|"quick")
        exec "$SCRIPT_DIR/scripts/quick-cleanup.sh" "${@:2}"
        ;;
    "terraform-cleanup"|"tf-clean")
        exec "$SCRIPT_DIR/scripts/terraform-cleanup.sh" "${@:2}"
        ;;
    "nuclear"|"nuke"|"kill-all")
        echo "☢️  Nuclear cleanup - killing ALL SDKPerf processes..."
        exec "$SCRIPT_DIR/scripts/kill-all-sdkperf.sh" "${@:2}"
        ;;
    "status"|"check")
        exec "$SCRIPT_DIR/scripts/status-check.sh" "${@:2}"
        ;;
    *)
        echo "🚀 Solace Chaos Testing Environment"
        echo "================================="
        echo ""
        echo "Available commands:"
        echo "  ./chaos.sh bootstrap    # Initial environment setup"
        echo "  ./chaos.sh start        # Start chaos testing (auto-cleans old logs)"
        echo "  ./chaos.sh weekly       # Start chaos testing with weekly restarts"
        echo "  ./chaos.sh stop         # Stop all chaos testing processes"
        echo "  ./chaos.sh daemon       # Process management daemon"
        echo "  ./chaos.sh status       # Check component status"
        echo "  ./chaos.sh cleanup      # Full interactive cleanup + old logs"
        echo "  ./chaos.sh cleanup logs # Only clean old logs (24h+)"
        echo "  ./chaos.sh quick        # Quick process cleanup"
        echo "  ./chaos.sh tf-clean     # Terraform-only cleanup"
        echo ""
        echo "Direct script access:"
        echo "  ./scripts/bootstrap-chaos-environment.sh"
        echo "  ./scripts/master-chaos.sh"
        echo "  ./scripts/chaos-daemon.sh"
        echo "  ./scripts/full-cleanup.sh"
        echo "  ./scripts/quick-cleanup.sh"
        echo "  ./scripts/terraform-cleanup.sh"
        echo ""
        ;;
esac