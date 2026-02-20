# Solace Chaos Testing Environment - Terraform Configuration
# Two-VPN Setup: market_data (new) + trading (new)
# Provider: Software Event Broker (Docker, VMs, Software broker)

terraform {
  required_providers {
    solacebroker = {
      source  = "solaceproducts/solacebroker"
      version = "~> 1.3"
    }
  }
}

# Configure the Solace provider
provider "solacebroker" {
  username = var.solace_admin_user
  password = var.solace_admin_password
  url      = var.solace_broker_url
}

# Create VPNs
resource "solacebroker_msg_vpn" "vpns" {
  for_each = var.vpns

  msg_vpn_name                    = each.value.name
  enabled                        = true
  max_connection_count           = each.value.max_connections
  max_subscription_count         = each.value.max_subscriptions
  max_transacted_session_count   = 1000
  max_transaction_count          = 1000

  # Enable authentication
  authentication_basic_enabled = true
  authentication_basic_type    = "internal"
  
  # Message spool configuration - increased for larger queues
  max_msg_spool_usage = 2000  # 2GB per VPN
}

# Create ACL profiles - dynamically based on VPN configuration
resource "solacebroker_msg_vpn_acl_profile" "acl_profiles" {
  for_each = {
    # Market Data VPN profiles
    "market_data_publisher" = {
      vpn = "market_data"
      connect_action = "allow"
      publish_action = "allow"
      subscribe_action = "allow"
    }
    "market_data_subscriber" = {
      vpn = "market_data"
      connect_action = "allow"
      publish_action = "disallow"
      subscribe_action = "allow"
    }
    "risk_management" = {
      vpn = "market_data"
      connect_action = "allow"
      publish_action = "allow"
      subscribe_action = "allow"
    }
    "integration_service" = {
      vpn = "market_data"
      connect_action = "allow"
      publish_action = "allow"
      subscribe_action = "allow"
    }
    "restricted_market_access" = {
      vpn = "market_data"
      connect_action = "allow"
      publish_action = "disallow"
      subscribe_action = "disallow"
    }
    "bridge_access_market_data" = {
      vpn = "market_data"
      connect_action = "allow"
      publish_action = "allow"
      subscribe_action = "allow"
    }
    
    # Trading VPN profiles
    "trade_processor" = {
      vpn = "trading"
      connect_action = "allow"
      publish_action = "allow"
      subscribe_action = "allow"
    }
    "chaos_testing" = {
      vpn = "trading"
      connect_action = "allow"
      publish_action = "allow"
      subscribe_action = "allow"
    }
    "restricted_trade_access" = {
      vpn = "trading"
      connect_action = "allow"
      publish_action = "disallow"
      subscribe_action = "disallow"
    }
    "bridge_access" = {
      vpn = "trading"
      connect_action = "allow"
      publish_action = "allow"
      subscribe_action = "allow"
    }
  }

  msg_vpn_name         = each.value.vpn
  acl_profile_name     = each.key
  
  client_connect_default_action    = each.value.connect_action
  publish_topic_default_action     = each.value.publish_action
  subscribe_topic_default_action   = each.value.subscribe_action

  # Depend on VPNs being created
  depends_on = [solacebroker_msg_vpn.vpns]
}

# Create queues with proper byte conversion
resource "solacebroker_msg_vpn_queue" "queues" {
  for_each = var.queues

  msg_vpn_name    = each.value.vpn
  queue_name      = each.key
  ingress_enabled = true
  egress_enabled  = true
  permission      = "consume"
  access_type     = "exclusive"  # Only one consumer per queue
  
  # Quota values are in MB directly (no conversion needed)
  max_msg_spool_usage = each.value.quota  # Direct MB values
  
  # Enable reject to sender for overflow testing
  reject_msg_to_sender_on_discard_behavior = "when-queue-enabled"

  # Depend on VPNs being created
  depends_on = [solacebroker_msg_vpn.vpns]
}

# Flatten queue subscriptions for proper resource creation
locals {
  queue_subscriptions = flatten([
    for queue_name, queue_config in var.queues : [
      for subscription in queue_config.topic_subscriptions : {
        key   = "${queue_name}-${replace(subscription, "/", "_")}"
        queue = queue_name
        vpn   = queue_config.vpn
        topic = subscription
      }
    ]
  ])
}

resource "solacebroker_msg_vpn_queue_subscription" "all_subscriptions" {
  for_each = {
    for sub in local.queue_subscriptions : sub.key => sub
  }

  msg_vpn_name       = each.value.vpn
  queue_name         = each.value.queue
  subscription_topic = each.value.topic

  depends_on = [solacebroker_msg_vpn_queue.queues]
}

# Create client profiles for bridge connections
resource "solacebroker_msg_vpn_client_profile" "bridge_client_profile_market_data" {
  msg_vpn_name                    = "market_data"
  client_profile_name             = "bridge_client_profile"
  allow_bridge_connections_enabled = true
  allow_guaranteed_endpoint_create_enabled = true
  allow_guaranteed_msg_receive_enabled = true
  allow_guaranteed_msg_send_enabled = true
  
  depends_on = [solacebroker_msg_vpn.vpns, solacebroker_msg_vpn_acl_profile.acl_profiles]
}

resource "solacebroker_msg_vpn_client_profile" "bridge_client_profile_trading" {
  msg_vpn_name                    = "trading"
  client_profile_name             = "bridge_client_profile"
  allow_bridge_connections_enabled = true
  allow_guaranteed_endpoint_create_enabled = true
  allow_guaranteed_msg_receive_enabled = true
  allow_guaranteed_msg_send_enabled = true
  
  depends_on = [solacebroker_msg_vpn.vpns, solacebroker_msg_vpn_acl_profile.acl_profiles]
}

# Create client profile for guaranteed messaging in trading VPN
resource "solacebroker_msg_vpn_client_profile" "guaranteed_messaging_profile" {
  msg_vpn_name                    = "trading"
  client_profile_name             = "guaranteed_messaging"
  allow_bridge_connections_enabled = false
  allow_guaranteed_endpoint_create_enabled = true
  allow_guaranteed_msg_receive_enabled = true
  allow_guaranteed_msg_send_enabled = true
  
  depends_on = [solacebroker_msg_vpn.vpns, solacebroker_msg_vpn_acl_profile.acl_profiles]
}

# Create client usernames
resource "solacebroker_msg_vpn_client_username" "users" {
  for_each = var.vpn_users

  msg_vpn_name          = each.value.vpn
  client_username       = each.value.username
  password              = each.value.password
  acl_profile_name      = each.value.acl_profile
  client_profile_name   = contains(["bridge_user", "bridge_user_market_data"], each.key) ? "bridge_client_profile" : (contains(["order_router", "chaos_generator"], each.key) ? "guaranteed_messaging" : "default")
  enabled               = true

  depends_on = [solacebroker_msg_vpn_acl_profile.acl_profiles, solacebroker_msg_vpn_client_profile.bridge_client_profile_market_data, solacebroker_msg_vpn_client_profile.bridge_client_profile_trading, solacebroker_msg_vpn_client_profile.guaranteed_messaging_profile]
}

# Cross-VPN Bridge Configuration (conditional)
resource "solacebroker_msg_vpn_bridge" "market_data_to_trading_bridge" {
  count = var.enable_cross_vpn_bridge ? 1 : 0

  msg_vpn_name                          = "market_data"
  bridge_name                           = "market_data-to-trading-bridge"
  bridge_virtual_router                 = "primary"
  enabled                               = true
  max_ttl                               = 8
  remote_authentication_basic_client_username = var.bridge_username
  remote_authentication_basic_password         = var.bridge_password
  
  depends_on = [solacebroker_msg_vpn.vpns]
}

# Remote VPN configuration for bridge
resource "solacebroker_msg_vpn_bridge_remote_msg_vpn" "trading_vpn_remote" {
  count = var.enable_cross_vpn_bridge ? 1 : 0

  msg_vpn_name            = "market_data"
  bridge_name             = "market_data-to-trading-bridge"
  bridge_virtual_router   = "primary"
  remote_msg_vpn_name     = "trading"
  remote_msg_vpn_location = "127.0.0.1:55555"
  enabled                 = true
  client_username         = var.bridge_username
  password                = var.bridge_password
  tls_enabled             = false
  queue_binding           = "bridge_receive_queue"
  
  depends_on = [solacebroker_msg_vpn_bridge.market_data_to_trading_bridge, solacebroker_msg_vpn_queue.queues]
}

# Bridge topic subscriptions for market data bridge stress testing
resource "solacebroker_msg_vpn_bridge_remote_subscription" "bridge_stress_subscription" {
  count = var.enable_cross_vpn_bridge ? 1 : 0

  msg_vpn_name              = "market_data"
  bridge_name               = "market_data-to-trading-bridge"
  bridge_virtual_router     = "primary"
  remote_subscription_topic = "market-data/bridge-stress/>"
  deliver_always_enabled    = true
  
  depends_on = [solacebroker_msg_vpn_bridge_remote_msg_vpn.trading_vpn_remote]
}

# Return bridge from trading to market_data (required for bidirectional communication)
resource "solacebroker_msg_vpn_bridge" "trading_to_market_data_bridge" {
  count = var.enable_cross_vpn_bridge ? 1 : 0

  msg_vpn_name                          = "trading"
  bridge_name                           = "trading-to-market_data-bridge"
  bridge_virtual_router                 = "primary"
  enabled                               = true
  max_ttl                               = 8
  remote_authentication_basic_client_username = var.bridge_username
  remote_authentication_basic_password         = var.bridge_password
  
  depends_on = [solacebroker_msg_vpn.vpns]
}

# Remote VPN configuration for return bridge
resource "solacebroker_msg_vpn_bridge_remote_msg_vpn" "market_data_vpn_remote" {
  count = var.enable_cross_vpn_bridge ? 1 : 0

  msg_vpn_name            = "trading"
  bridge_name             = "trading-to-market_data-bridge"
  bridge_virtual_router   = "primary"
  remote_msg_vpn_name     = "market_data"
  remote_msg_vpn_location = "127.0.0.1:55555"
  enabled                 = true
  client_username         = var.bridge_username
  password                = var.bridge_password
  tls_enabled             = false
  queue_binding           = "cross_market_data_queue"
  
  depends_on = [solacebroker_msg_vpn_bridge.trading_to_market_data_bridge, solacebroker_msg_vpn_queue.queues]
}

# Outputs
output "vpn_names" {
  description = "VPN names created/used"
  value = {
    for k, v in var.vpns : k => v.name
  }
}

output "queue_names" {
  description = "Queue names and their configurations"
  value = {
    for k, v in var.queues : k => {
      name     = k
      vpn      = v.vpn
      quota_mb = v.quota
    }
  }
}

output "user_names" {
  description = "User names and their VPN assignments"
  value = {
    for k, v in var.vpn_users : k => {
      username = v.username
      vpn      = v.vpn
    }
  }
}