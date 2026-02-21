#!/bin/bash
# generate-terraform-config.sh - Generate terraform.tfvars from .env infrastructure definitions
# Eliminates hardcoded heredoc in bootstrap script

# Source required dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load-env.sh"
source "${SCRIPT_DIR}/config-parser.sh"

# Generate terraform.tfvars for specified broker environment
# Usage: generate_terraform_config "broker_type" "output_dir"
generate_terraform_config() {
    local broker_type="${1:-software}"
    local output_dir="${2:-terraform/environments/${broker_type}}"
    local output_file="${output_dir}/terraform.tfvars"
    
    echo "Generating Terraform configuration for ${broker_type}..."
    
    # Ensure output directory exists
    mkdir -p "$output_dir"
    
    # Start generating terraform.tfvars
    cat > "$output_file" <<EOF
# Auto-generated from .env infrastructure definitions
# Generated on: $(date)
# Broker type: ${broker_type}

solace_broker_url = "${SOLACE_SEMP_URL}"
solace_admin_user = "${SOLACE_ADMIN_USER}"
solace_admin_password = "${SOLACE_ADMIN_PASSWORD}"

# VPN Configuration
vpns = {
  "market_data" = {
    name = "${MARKET_DATA_VPN}"
    max_connections = 50
    max_subscriptions = 10000
  }
  "trading" = {
    name = "${TRADING_VPN}"
    max_connections = 100
    max_subscriptions = 5000
  }
}

# Queue Configuration (auto-generated from QUEUE_N definitions)
queues = {
EOF
    
    # Generate queue configurations
    local first_queue=true
    for queue_name in $(list_queues); do
        local vpn=$(get_queue_config "$queue_name" "vpn")
        local quota=$(get_queue_config "$queue_name" "quota")
        local subscriptions=$(get_queue_config "$queue_name" "subscriptions")
        
        # Add comma after previous entry
        if [ "$first_queue" = false ]; then
            echo "," >> "$output_file"
        fi
        first_queue=false
        
        # Write queue configuration
        cat >> "$output_file" <<EOF
  "${queue_name}" = {
    vpn = "${vpn}"
    quota = ${quota}
    topic_subscriptions = ["${subscriptions}"]
  }
EOF
    done
    
    # Close queues block and start users block
    cat >> "$output_file" <<EOF
}

# User Configuration (auto-generated from USER_N definitions)
vpn_users = {
EOF
    
    # Generate user configurations
    local first_user=true
    for role in $(list_users); do
        local vpn=$(get_user_config "$role" "vpn")
        local password=$(get_user_config "$role" "password")
        local acl=$(get_user_config "$role" "acl_profile")
        
        # Add comma after previous entry
        if [ "$first_user" = false ]; then
            echo "," >> "$output_file"
        fi
        first_user=false
        
        # Generate safe key name (replace hyphens with underscores for Terraform)
        local key_name="${role//-/_}"
        
        # Write user configuration
        cat >> "$output_file" <<EOF
  "${key_name}" = {
    vpn = "${vpn}"
    username = "${role}"
    password = "${password}"
    acl_profile = "${acl}"
  }
EOF
    done
    
    # Add bridge users if enabled
    if [[ "${ENABLE_CROSS_VPN_BRIDGE}" == "true" ]]; then
        cat >> "$output_file" <<EOF
,
  "bridge_user" = {
    vpn = "${TRADING_VPN}"
    username = "bridge-user"
    password = "bridge_pass"
    acl_profile = "bridge_access"
  },
  "bridge_user_market_data" = {
    vpn = "${MARKET_DATA_VPN}"
    username = "bridge-user"
    password = "bridge_pass"
    acl_profile = "bridge_access_market_data"
  }
EOF
    fi
    
    # Close users block and add bridge configuration
    cat >> "$output_file" <<EOF
}

# Bridge Configuration
enable_cross_vpn_bridge = ${ENABLE_CROSS_VPN_BRIDGE:-false}
bridge_username = "bridge-user"
bridge_password = "bridge_pass"
bridges = {}
EOF
    
    echo "Generated: $output_file"
    return 0
}

# Generate configs for all broker types
generate_all_configs() {
    local broker_types=("base" "software" "appliance")
    
    for broker_type in "${broker_types[@]}"; do
        generate_terraform_config "$broker_type" "terraform/environments/${broker_type}"
    done
    
    echo "All Terraform configurations generated successfully"
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if broker type was provided as argument
    if [[ $# -ge 1 ]]; then
        generate_terraform_config "$1" "${2:-terraform/environments/$1}"
    else
        # Default: generate for detected or default broker type
        local broker_type="${DETECTED_BROKER_TYPE:-${SOLACE_BROKER_TYPE:-software}}"
        generate_terraform_config "$broker_type"
    fi
fi
