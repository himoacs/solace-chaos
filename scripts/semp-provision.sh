#!/bin/bash
# SEMP Provisioning Script - Direct SEMP API provisioning for Solace chaos testing
# This script creates/deletes all Solace resources using SEMP API v2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment and SEMP helper library
source "$PROJECT_ROOT/.env"
source "$SCRIPT_DIR/semp-lib.sh"
source "$SCRIPT_DIR/config-parser.sh"

# Track created resources for rollback
CREATED_RESOURCES=()

# Track failed operations
FAILED_OPERATIONS=0

# Cleanup on failure
cleanup_on_failure() {
    log_semp_error "Provisioning failed! Rolling back created resources..."
    
    # Delete in reverse order
    for ((i=${#CREATED_RESOURCES[@]}-1; i>=0; i--)); do
        local resource="${CREATED_RESOURCES[i]}"
        log_semp_step "Rolling back: $resource"
        semp_delete "$resource" "Rollback" || true
    done
}

trap cleanup_on_failure ERR

# ============================================================================
# CREATE FUNCTIONS (in dependency order)
# ============================================================================

create_vpns() {
    log_semp_step "Creating Message VPNs..."
    
    # Market Data VPN
    local payload=$(cat <<EOF
{
    "msgVpnName": "${MARKET_DATA_VPN}",
    "enabled": true,
    "maxConnectionCount": 50,
    "maxSubscriptionCount": 10000,
    "maxTransactedSessionCount": 1000,
    "maxTransactionCount": 1000,
    "maxMsgSpoolUsage": 2000,
    "authenticationBasicEnabled": true,
    "authenticationBasicType": "internal"
}
EOF
)
    
    if semp_post "/SEMP/v2/config/msgVpns" "$payload" "Market Data VPN"; then
        log_semp_success "Created VPN: ${MARKET_DATA_VPN}"
        CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}")
    else
        ((FAILED_OPERATIONS++))
    fi
    
    # Trading VPN
    payload=$(cat <<EOF
{
    "msgVpnName": "${TRADING_VPN}",
    "enabled": true,
    "maxConnectionCount": 100,
    "maxSubscriptionCount": 5000,
    "maxTransactedSessionCount": 1000,
    "maxTransactionCount": 1000,
    "maxMsgSpoolUsage": 2000,
    "authenticationBasicEnabled": true,
    "authenticationBasicType": "internal"
}
EOF
)
    
    if semp_post "/SEMP/v2/config/msgVpns" "$payload" "Trading VPN"; then
        log_semp_success "Created VPN: ${TRADING_VPN}"
        CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${TRADING_VPN}")
    else
        ((FAILED_OPERATIONS++))
    fi
    
    # Wait for VPNs to be ready
    sleep 2
}

create_acl_profiles() {
    log_semp_step "Creating ACL Profiles..."
    
    # Iterate through all ACL profiles from config-parser
    for profile_name in $(list_acl_profiles); do
        local vpn=$(get_acl_config "$profile_name" "vpn")
        local connect=$(get_acl_config "$profile_name" "connect")
        local publish=$(get_acl_config "$profile_name" "publish")
        local subscribe=$(get_acl_config "$profile_name" "subscribe")
        
        local payload=$(cat <<EOF
{
    "aclProfileName": "$profile_name",
    "clientConnectDefaultAction": "$connect",
    "publishTopicDefaultAction": "$publish",
    "subscribeTopicDefaultAction": "$subscribe"
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/$vpn/aclProfiles" "$payload" "ACL Profile $profile_name"; then
            log_semp_success "Created ACL Profile: $vpn/$profile_name"
            CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/$vpn/aclProfiles/$profile_name")
        else
            ((FAILED_OPERATIONS++))
        fi
    done
}

create_client_profiles() {
    log_semp_step "Creating Client Profiles..."
    
    # Bridge client profiles (one per VPN)
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        local payload=$(cat <<EOF
{
    "clientProfileName": "bridge_client_profile",
    "allowBridgeConnectionsEnabled": true,
    "allowGuaranteedEndpointCreateEnabled": true,
    "allowGuaranteedMsgReceiveEnabled": true,
    "allowGuaranteedMsgSendEnabled": true
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/$vpn/clientProfiles" "$payload" "Bridge Client Profile"; then
            log_semp_success "Created Client Profile: $vpn/bridge_client_profile"
            CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/$vpn/clientProfiles/bridge_client_profile")
        else
            ((FAILED_OPERATIONS++))
        fi
    done
    
    # Guaranteed messaging profile for trading VPN
    local payload=$(cat <<EOF
{
    "clientProfileName": "guaranteed_messaging",
    "allowBridgeConnectionsEnabled": false,
    "allowGuaranteedEndpointCreateEnabled": true,
    "allowGuaranteedMsgReceiveEnabled": true,
    "allowGuaranteedMsgSendEnabled": true
}
EOF
)
    
    if semp_post "/SEMP/v2/config/msgVpns/${TRADING_VPN}/clientProfiles" "$payload" "Guaranteed Messaging Profile"; then
        log_semp_success "Created Client Profile: ${TRADING_VPN}/guaranteed_messaging"
        CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${TRADING_VPN}/clientProfiles/guaranteed_messaging")
    else
        ((FAILED_OPERATIONS++))
    fi
}

create_queues() {
    log_semp_step "Creating Queues..."
    
    # Iterate through all queues from config-parser
    for queue_name in $(list_queues); do
        local vpn=$(get_queue_config "$queue_name" "vpn")
        local quota=$(get_queue_config "$queue_name" "quota")
        local access_type=$(get_queue_config "$queue_name" "access_type")
        
        local payload=$(cat <<EOF
{
    "queueName": "${queue_name}",
    "accessType": "${access_type}",
    "egressEnabled": true,
    "ingressEnabled": true,
    "maxMsgSpoolUsage": ${quota},
    "permission": "consume",
    "rejectMsgToSenderOnDiscardBehavior": "when-queue-enabled"
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/${vpn}/queues" "$payload" "Queue ${queue_name}"; then
            log_semp_success "Created Queue: ${vpn}/${queue_name}"
            CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${vpn}/queues/${queue_name}")
        else
            ((FAILED_OPERATIONS++))
        fi
    done
}

create_queue_subscriptions() {
    log_semp_step "Creating Queue Subscriptions..."
    
    # Iterate through all queues and add their subscriptions
    for queue_name in $(list_queues); do
        local vpn=$(get_queue_config "$queue_name" "vpn")
        local subscriptions=$(get_queue_config "$queue_name" "subscriptions")
        
        # Split subscriptions by pipe character if multiple
        IFS='|' read -ra subs <<< "$subscriptions"
        
        for sub in "${subs[@]}"; do
            [[ -z "$sub" ]] && continue
            
            local payload="{\"subscriptionTopic\": \"$sub\"}"
            if semp_post "/SEMP/v2/config/msgVpns/${vpn}/queues/${queue_name}/subscriptions" "$payload" "Subscription"; then
                log_semp_success "Added subscription to ${queue_name}: $sub"
            else
                ((FAILED_OPERATIONS++))
            fi
        done
    done
    
    # bridge_receive_queue subscriptions
    sub="market-data/bridge-stress/>"
    payload="{\"subscriptionTopic\": \"$sub\"}"
    if semp_post "/SEMP/v2/config/msgVpns/${TRADING_VPN}/queues/bridge_receive_queue/subscriptions" "$payload" "Subscription"; then
        log_semp_success "Added subscription to bridge_receive_queue: $sub"
    else
        ((FAILED_OPERATIONS++))
    fi
    
    # cross_market_data_queue subscriptions
    sub="market-data/bridge-stress/>"
    payload="{\"subscriptionTopic\": \"$sub\"}"
    if semp_post "/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}/queues/cross_market_data_queue/subscriptions" "$payload" "Subscription"; then
        log_semp_success "Added subscription to cross_market_data_queue: $sub"
    else
        ((FAILED_OPERATIONS++))
    fi
}

create_users() {
    log_semp_step "Creating Client Usernames..."
    
    # Iterate through all users from config-parser
    for role in $(list_users); do
        local vpn=$(get_user_config "$role" "vpn")
        local password=$(get_user_config "$role" "password")
        local acl_profile=$(get_user_config "$role" "acl_profile")
        local client_profile=$(get_user_config "$role" "client_profile")
        
        # Use 'default' if client_profile not specified or empty
        [[ -z "$client_profile" || "$client_profile" == "default" ]] && client_profile="default"
        
        local payload=$(cat <<EOF
{
    "clientUsername": "$role",
    "password": "$password",
    "aclProfileName": "$acl_profile",
    "clientProfileName": "$client_profile",
    "enabled": true
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/${vpn}/clientUsernames" "$payload" "User $role"; then
            log_semp_success "Created user: ${vpn}/$role"
            CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${vpn}/clientUsernames/$role")
        else
            ((FAILED_OPERATIONS++))
        fi
    done
    
    # Create bridge users if bridges are enabled
    if [ "${ENABLE_CROSS_VPN_BRIDGE}" == "true" ]; then
        # Bridge user for market_data VPN
        local payload=$(cat <<EOF
{
    "clientUsername": "bridge-user",
    "password": "bridge_pass",
    "aclProfileName": "bridge_access_market_data",
    "clientProfileName": "bridge_client_profile",
    "enabled": true
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}/clientUsernames" "$payload" "User bridge-user"; then
            log_semp_success "Created bridge user: ${MARKET_DATA_VPN}/bridge-user"
            CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}/clientUsernames/bridge-user")
        else
            ((FAILED_OPERATIONS++))
        fi
        
        # Bridge user for trading VPN
        payload=$(cat <<EOF
{
    "clientUsername": "bridge-user",
    "password": "bridge_pass",
    "aclProfileName": "bridge_access",
    "clientProfileName": "bridge_client_profile",
    "enabled": true
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/${TRADING_VPN}/clientUsernames" "$payload" "User bridge-user"; then
            log_semp_success "Created bridge user: ${TRADING_VPN}/bridge-user"
            CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${TRADING_VPN}/clientUsernames/bridge-user")
        else
            ((FAILED_OPERATIONS++))
        fi
    fi
}

create_bridges() {
    if [ "${ENABLE_CROSS_VPN_BRIDGE}" != "true" ]; then
        log_semp_warning "Cross-VPN bridges disabled (ENABLE_CROSS_VPN_BRIDGE=false)"
        return 0
    fi
    
    log_semp_step "Creating Cross-VPN Bridges..."
    
    # Bridge from market_data to trading
    local bridge_name="market_data-to-trading-bridge"
    local virtual_router="primary"
    local payload=$(cat <<EOF
{
    "bridgeName": "$bridge_name",
    "bridgeVirtualRouter": "$virtual_router",
    "enabled": true,
    "maxTtl": 8,
    "remoteAuthenticationBasicClientUsername": "bridge-user",
    "remoteAuthenticationBasicPassword": "bridge_pass",
    "remoteAuthenticationScheme": "basic"
}
EOF
)
    
    if semp_post "/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}/bridges" "$payload" "Bridge $bridge_name"; then
        log_semp_success "Created bridge: $bridge_name"
        CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}/bridges/${bridge_name},${virtual_router}")
        
        # Try to add remote VPN (may not be supported in older SEMP versions)
        payload=$(cat <<EOF
{
    "remoteMsgVpnName": "${TRADING_VPN}",
    "remoteMsgVpnLocation": "127.0.0.1:55555",
    "remoteMsgVpnInterface": "",
    "enabled": true,
    "queueBinding": "bridge_receive_queue"
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}/bridges/${bridge_name},${virtual_router}/remoteMsgVpns" "$payload" "Remote VPN" 2>/dev/null; then
            log_semp_success "Added remote VPN to bridge: ${TRADING_VPN}"
            
            # Add remote subscription
            payload=$(cat <<EOF
{
    "remoteSubscriptionTopic": "market-data/bridge-stress/>",
    "deliverAlwaysEnabled": true
}
EOF
)
            
            semp_post "/SEMP/v2/config/msgVpns/${MARKET_DATA_VPN}/bridges/${bridge_name},${virtual_router}/remoteMsgVpns/${TRADING_VPN}/remoteSubscriptions" "$payload" "Remote Subscription" 2>/dev/null || true
        else
            log_semp_warning "Remote VPN configuration not supported in this SEMP version (bridge still created)"
            ((FAILED_OPERATIONS++))
        fi
    else
        ((FAILED_OPERATIONS++))
    fi
    
    # Bridge from trading to market_data
    bridge_name="trading-to-market_data-bridge"
    payload=$(cat <<EOF
{
    "bridgeName": "$bridge_name",
    "bridgeVirtualRouter": "$virtual_router",
    "enabled": true,
    "maxTtl": 8,
    "remoteAuthenticationBasicClientUsername": "bridge-user",
    "remoteAuthenticationBasicPassword": "bridge_pass",
    "remoteAuthenticationScheme": "basic"
}
EOF
)
    
    if semp_post "/SEMP/v2/config/msgVpns/${TRADING_VPN}/bridges" "$payload" "Bridge $bridge_name"; then
        log_semp_success "Created bridge: $bridge_name"
        CREATED_RESOURCES+=("/SEMP/v2/config/msgVpns/${TRADING_VPN}/bridges/${bridge_name},${virtual_router}")
        
        # Try to add remote VPN (may not be supported in older SEMP versions)
        payload=$(cat <<EOF
{
    "remoteMsgVpnName": "${MARKET_DATA_VPN}",
    "remoteMsgVpnLocation": "127.0.0.1:55555",
    "remoteMsgVpnInterface": "",
    "enabled": true,
    "queueBinding": "cross_market_data_queue"
}
EOF
)
        
        if semp_post "/SEMP/v2/config/msgVpns/${TRADING_VPN}/bridges/${bridge_name},${virtual_router}/remoteMsgVpns" "$payload" "Remote VPN" 2>/dev/null; then
            log_semp_success "Added remote VPN to bridge: ${MARKET_DATA_VPN}"
        else
            log_semp_warning "Remote VPN configuration not supported in this SEMP version (bridge still created)"
            ((FAILED_OPERATIONS++))
        fi
    else
        ((FAILED_OPERATIONS++))
    fi
}

# ============================================================================
# DELETE FUNCTIONS (reverse dependency order)
# ============================================================================

delete_bridges() {
    log_semp_step "Deleting Bridges..."
    
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        # List bridges in this VPN - bridge endpoints include virtual router
        local bridge_data=$(semp_get "/SEMP/v2/config/msgVpns/$vpn/bridges" 2>/dev/null)
        local bridges=$(echo "$bridge_data" | jq -r '.data[] | "\(.bridgeName),\(.bridgeVirtualRouter)"' 2>/dev/null || true)
        
        for bridge_full in $bridges; do
            if [ -n "$bridge_full" ]; then
                # bridge_full is in format "bridgeName,virtualRouter"
                local bridge_name=$(echo "$bridge_full" | cut -d',' -f1)
                
                # First, try to delete remote VPNs (may not exist in older SEMP versions)
                local remote_vpns=$(semp_get "/SEMP/v2/config/msgVpns/$vpn/bridges/$bridge_full/remoteMsgVpns" 2>/dev/null | jq -r '.data[].remoteMsgVpnName' 2>/dev/null || true)
                
                for remote_vpn in $remote_vpns; do
                    if [ -n "$remote_vpn" ]; then
                        # Delete remote VPN (subscriptions are deleted automatically)
                        semp_delete "/SEMP/v2/config/msgVpns/$vpn/bridges/$bridge_full/remoteMsgVpns/$remote_vpn" "Remote VPN $remote_vpn" 2>/dev/null || true
                    fi
                done
                
                # Now delete the bridge itself (with virtual router in path)
                semp_delete "/SEMP/v2/config/msgVpns/$vpn/bridges/$bridge_full" "Bridge $vpn/$bridge_name" || true
                log_semp_success "Deleted bridge: $vpn/$bridge_name"
            fi
        done
    done
}

delete_users() {
    log_semp_step "Deleting Client Usernames..."
    
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        local users=$(semp_get "/SEMP/v2/config/msgVpns/$vpn/clientUsernames" 2>/dev/null | jq -r '.data[].clientUsername' 2>/dev/null || true)
        
        for user in $users; do
            # Skip default and system resources (starting with #)
            if [ -n "$user" ] && [ "$user" != "default" ] && [[ ! "$user" =~ ^# ]]; then
                semp_delete "/SEMP/v2/config/msgVpns/$vpn/clientUsernames/$user" "User $vpn/$user" || true
                log_semp_success "Deleted user: $vpn/$user"
            fi
        done
    done
}

delete_queue_subscriptions() {
    log_semp_step "Deleting Queue Subscriptions..."
    
    # Subscriptions are deleted automatically when queues are deleted
    log_semp_success "Queue subscriptions will be deleted with queues"
}

delete_queues() {
    log_semp_step "Deleting Queues..."
    
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        local queues=$(semp_get "/SEMP/v2/config/msgVpns/$vpn/queues" 2>/dev/null | jq -r '.data[].queueName' 2>/dev/null || true)
        
        for queue in $queues; do
            # Skip system resources (starting with #)
            if [ -n "$queue" ] && [[ ! "$queue" =~ ^# ]]; then
                semp_delete "/SEMP/v2/config/msgVpns/$vpn/queues/$queue" "Queue $vpn/$queue" || true
                log_semp_success "Deleted queue: $vpn/$queue"
            fi
        done
    done
}

delete_client_profiles() {
    log_semp_step "Deleting Client Profiles..."
    
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        local profiles=$(semp_get "/SEMP/v2/config/msgVpns/$vpn/clientProfiles" 2>/dev/null | jq -r '.data[].clientProfileName' 2>/dev/null || true)
        
        for profile in $profiles; do
            # Skip default and system resources (starting with #)
            if [ -n "$profile" ] && [ "$profile" != "default" ] && [[ ! "$profile" =~ ^# ]]; then
                semp_delete "/SEMP/v2/config/msgVpns/$vpn/clientProfiles/$profile" "Client Profile $vpn/$profile" || true
                log_semp_success "Deleted client profile: $vpn/$profile"
            fi
        done
    done
}

delete_acl_profiles() {
    log_semp_step "Deleting ACL Profiles..."
    
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        local profiles=$(semp_get "/SEMP/v2/config/msgVpns/$vpn/aclProfiles" 2>/dev/null | jq -r '.data[].aclProfileName' 2>/dev/null || true)
        
        for profile in $profiles; do
            # Skip default and system resources (starting with #)
            if [ -n "$profile" ] && [ "$profile" != "default" ] && [[ ! "$profile" =~ ^# ]]; then
                semp_delete "/SEMP/v2/config/msgVpns/$vpn/aclProfiles/$profile" "ACL Profile $vpn/$profile" || true
                log_semp_success "Deleted ACL profile: $vpn/$profile"
            fi
        done
    done
}

delete_vpns() {
    log_semp_step "Deleting Message VPNs..."
    
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        semp_delete "/SEMP/v2/config/msgVpns/$vpn" "VPN $vpn" || true
        log_semp_success "Deleted VPN: $vpn"
    done
}

# ============================================================================
# MAIN OPERATIONS
# ============================================================================

provision_create() {
    log_semp_step "Starting SEMP provisioning (create mode)..."
    echo ""
    
    # Reset failure counter for this run
    FAILED_OPERATIONS=0
    
    create_vpns
    create_acl_profiles
    create_client_profiles
    create_queues
    create_queue_subscriptions
    create_users
    create_bridges
    
    echo ""
    if [ $FAILED_OPERATIONS -eq 0 ]; then
        log_semp_success "✅ All resources created successfully!"
        echo ""
        echo "Created resources:"
        echo "  - 2 VPNs (${MARKET_DATA_VPN}, ${TRADING_VPN})"
        echo "  - 10 ACL Profiles"
        echo "  - 3 Client Profiles"
        echo "  - 4 Queues with subscriptions"
        echo "  - 10 Client Usernames"
        if [ "${ENABLE_CROSS_VPN_BRIDGE}" = "true" ]; then
            echo "  - 2 Cross-VPN Bridges"
        fi
        echo ""
    else
        log_semp_error "❌ Provisioning failed with $FAILED_OPERATIONS errors!"
        echo ""
        echo "Common causes:"
        echo "  1. Insufficient permissions - The admin user needs 'admin' or 'read-write' access level"
        echo "  2. On hardware brokers, the user must have proper authorization:"
        echo "     - Check CLI: show client-username <username> authorization access-level"
        echo "     - Should be 'admin' for full provisioning"
        echo "  3. VPNs may already exist - Use 'verify' command to check"
        echo ""
        echo "To fix authorization on hardware broker:"
        echo "  enable"
        echo "  configure"
        echo "  client-username ${SOLACE_ADMIN_USER}"
        echo "    authorization"
        echo "      access-level admin"
        echo "    exit"
        echo "  end"
        echo ""
        return 1
    fi
}

provision_delete() {
    log_semp_step "Starting SEMP provisioning (delete mode)..."
    echo ""
    
    # Check for --force flag
    if [ "$1" != "--force" ]; then
        echo "⚠️  This will delete ALL chaos testing resources from the broker!"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_semp_warning "Delete operation cancelled"
            exit 0
        fi
    fi
    
    delete_bridges
    delete_users
    delete_queue_subscriptions
    delete_queues
    delete_client_profiles
    delete_acl_profiles
    delete_vpns
    
    echo ""
    log_semp_success "✅ All resources deleted successfully!"
    echo ""
}

provision_verify() {
    log_semp_step "Verifying provisioned resources..."
    echo ""
    
    local errors=0
    
    # Check VPNs
    for vpn in "${MARKET_DATA_VPN}" "${TRADING_VPN}"; do
        if check_resource_exists "/SEMP/v2/monitor/msgVpns/$vpn"; then
            log_semp_success "VPN exists: $vpn"
        else
            log_semp_error "VPN missing: $vpn"
            ((errors++))
        fi
    done
    
    # Check key queues
    local queues=("${TRADING_VPN}:equity_order_queue" "${TRADING_VPN}:baseline_queue" "${MARKET_DATA_VPN}:cross_market_data_queue")
    for queue_spec in "${queues[@]}"; do
        IFS=':' read -r vpn queue <<< "$queue_spec"
        if check_resource_exists "/SEMP/v2/monitor/msgVpns/$vpn/queues/$queue"; then
            log_semp_success "Queue exists: $vpn/$queue"
        else
            log_semp_error "Queue missing: $vpn/$queue"
            ((errors++))
        fi
    done
    
    echo ""
    if [ $errors -eq 0 ]; then
        log_semp_success "✅ All resources verified!"
        return 0
    else
        log_semp_error "❌ Verification failed with $errors errors"
        return 1
    fi
}

# ============================================================================
# USAGE
# ============================================================================

usage() {
    echo "Usage: $0 {create|delete|verify} [options]"
    echo ""
    echo "Commands:"
    echo "  create   - Create all Solace resources via SEMP API"
    echo "  delete   - Delete all Solace resources via SEMP API"
    echo "  verify   - Verify that all resources exist"
    echo ""
    echo "Options:"
    echo "  --force  - Skip confirmation prompts (for delete command)"
    echo ""
    echo "Examples:"
    echo "  $0 create"
    echo "  $0 delete --force"
    echo "  $0 verify"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local command="${1:-}"
    shift || true
    
    case "$command" in
        create)
            provision_create "$@"
            ;;
        delete)
            provision_delete "$@"
            ;;
        verify)
            provision_verify "$@"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Disable rollback trap for normal execution
trap - ERR

main "$@"
