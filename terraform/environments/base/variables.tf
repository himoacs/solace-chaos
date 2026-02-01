# Input variables for Solace Chaos Testing Environment

variable "solace_broker_url" {
  description = "Solace broker SEMP URL"
  type        = string
}

variable "solace_admin_user" {
  description = "Solace admin username"
  type        = string
}

variable "solace_admin_password" {
  description = "Solace admin password"
  type        = string
  sensitive   = true
}

variable "vpns" {
  description = "VPN configuration"
  type = map(object({
    name               = string
    max_connections    = number
    max_subscriptions  = number
  }))
}

variable "queues" {
  description = "Queue configuration"
  type = map(object({
    vpn                  = string
    quota               = number  # MB
    topic_subscriptions = list(string)
  }))
}

variable "vpn_users" {
  description = "VPN users configuration"
  type = map(object({
    vpn         = string
    username    = string
    password    = string
    acl_profile = string
  }))
}

variable "enable_cross_vpn_bridge" {
  description = "Enable cross-VPN bridge configuration"
  type        = bool
  default     = false
}

variable "bridges" {
  description = "Bridge configuration"
  type = map(object({
    source_vpn = string
    target_vpn = string
    topics     = list(string)
  }))
  default = {}
}