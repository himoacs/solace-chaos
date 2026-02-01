#!/bin/bash
# Terraform Cleanup Script - Destroys all Solace broker resources
# Use with caution - this will remove all queues, users, ACLs, and VPNs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform/environments/base"
LOG_FILE="${SCRIPT_DIR}/logs/terraform-cleanup.log"

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

# Function to check if Terraform is initialized
check_terraform_init() {
    if [ ! -d "$TERRAFORM_DIR/.terraform" ]; then
        log "$RED" "ERROR: Terraform not initialized in $TERRAFORM_DIR"
        log "$YELLOW" "Run './bootstrap-chaos-environment.sh' first to initialize Terraform"
        exit 1
    fi
}

# Function to show what will be destroyed
show_plan() {
    log "$BLUE" "Checking what resources will be destroyed..."
    cd "$TERRAFORM_DIR"
    
    if terraform plan -destroy -out=destroy.tfplan > /tmp/terraform-destroy-plan.txt 2>&1; then
        log "$YELLOW" "=== RESOURCES TO BE DESTROYED ==="
        grep -A 1000 "Terraform will perform the following actions:" /tmp/terraform-destroy-plan.txt | head -50
        echo ""
        log "$YELLOW" "Full plan saved to: /tmp/terraform-destroy-plan.txt"
        rm -f destroy.tfplan
    else
        log "$RED" "Failed to generate destroy plan. Check Terraform configuration."
        cat /tmp/terraform-destroy-plan.txt
        exit 1
    fi
}

# Function to destroy Terraform resources
destroy_resources() {
    log "$RED" "Destroying all Terraform resources..."
    cd "$TERRAFORM_DIR"
    
    if terraform destroy -auto-approve 2>&1 | tee -a "$LOG_FILE"; then
        log "$GREEN" "✅ All Terraform resources destroyed successfully"
    else
        log "$RED" "❌ Failed to destroy some resources. Check the logs above."
        log "$YELLOW" "You may need to manually clean up some resources in the Solace broker"
        exit 1
    fi
}

# Function to clean up Terraform state
cleanup_terraform_state() {
    cd "$TERRAFORM_DIR"
    
    if confirm "Do you want to remove Terraform state files? (This cannot be undone)"; then
        log "$YELLOW" "Backing up Terraform state..."
        
        # Create backup directory with timestamp
        BACKUP_DIR="${SCRIPT_DIR}/terraform-backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Backup state files
        [ -f "terraform.tfstate" ] && cp terraform.tfstate "$BACKUP_DIR/"
        [ -f "terraform.tfstate.backup" ] && cp terraform.tfstate.backup "$BACKUP_DIR/"
        [ -f ".terraform.lock.hcl" ] && cp .terraform.lock.hcl "$BACKUP_DIR/"
        
        log "$GREEN" "State files backed up to: $BACKUP_DIR"
        
        # Remove state files
        rm -f terraform.tfstate terraform.tfstate.backup
        log "$GREEN" "✅ Terraform state files removed"
    else
        log "$YELLOW" "Keeping Terraform state files"
    fi
}

# Main execution
main() {
    log "$BLUE" "=== Solace Chaos Environment - Terraform Cleanup ==="
    
    # Check if Terraform is initialized
    check_terraform_init
    
    # Show warning
    log "$RED" "⚠️  WARNING: This will destroy ALL resources created by Terraform!"
    log "$RED" "This includes:"
    log "$RED" "  - VPNs (trading-vpn)"
    log "$RED" "  - All queues and their messages"
    log "$RED" "  - All user accounts"
    log "$RED" "  - All ACL profiles"
    log "$RED" "  - All queue subscriptions"
    echo ""
    
    # Show what will be destroyed
    show_plan
    echo ""
    
    # Confirm destruction
    if ! confirm "Are you sure you want to destroy all these resources?"; then
        log "$YELLOW" "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    if ! confirm "This is your FINAL confirmation. Proceed with destruction?"; then
        log "$YELLOW" "Cleanup cancelled by user"
        exit 0
    fi
    
    # Destroy resources
    destroy_resources
    
    # Optionally clean up state
    cleanup_terraform_state
    
    log "$GREEN" "🎉 Terraform cleanup completed successfully!"
    log "$GREEN" "All Solace broker resources have been removed."
    log "$YELLOW" "Note: The default VPN and its built-in users (admin) are preserved."
}

# Handle script interruption
trap 'log "$RED" "Cleanup interrupted by user"; exit 130' INT TERM

# Run main function
main "$@"