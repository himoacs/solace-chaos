#!/bin/bash

# Simple wrapper to maintain backward compatibility
# All main scripts have been moved to scripts/ directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$1" in
    "bootstrap"|"setup"|"init")
        exec "$SCRIPT_DIR/scripts/bootstrap-chaos-environment.sh" "${@:2}"
        ;;
    "start"|"run"|"chaos")
        exec "$SCRIPT_DIR/scripts/master-chaos.sh" "${@:2}"
        ;;
    "daemon"|"manage")
        exec "$SCRIPT_DIR/scripts/chaos-daemon.sh" "${@:2}"
        ;;
    "cleanup"|"clean")
        exec "$SCRIPT_DIR/scripts/full-cleanup.sh" "${@:2}"
        ;;
    "quick-cleanup"|"quick")
        exec "$SCRIPT_DIR/scripts/quick-cleanup.sh" "${@:2}"
        ;;
    "terraform-cleanup"|"tf-clean")
        exec "$SCRIPT_DIR/scripts/terraform-cleanup.sh" "${@:2}"
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
        echo "  ./chaos.sh start        # Start chaos testing"
        echo "  ./chaos.sh daemon       # Process management daemon"
        echo "  ./chaos.sh status       # Check component status"
        echo "  ./chaos.sh cleanup      # Full interactive cleanup"
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