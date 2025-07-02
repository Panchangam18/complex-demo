variable "vnet_cidr" {
  description = "CIDR block for the VNet"
  type        = string
  
  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "VNet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "azure_location" {
  description = "Azure location (region)"
  type        = string
}



variable "availability_zones_enabled" {
  description = "Whether to use availability zones (not all regions support this)"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for outbound connectivity"
  type        = bool
  default     = true
}

variable "enable_gateway_subnet" {
  description = "Create gateway subnet for VPN/ExpressRoute"
  type        = bool
  default     = true
}

variable "enable_azure_firewall" {
  description = "Enable Azure Firewall subnet"
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Enable Azure Bastion subnet"
  type        = bool
  default     = false
}

variable "enable_network_watcher" {
  description = "Enable Network Watcher"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable NSG Flow Logs"
  type        = bool
  default     = true
}

variable "enable_postgresql_delegation" {
  description = "Enable subnet delegation for Azure Database for PostgreSQL"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for flow logs"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_resource_id" {
  description = "Log Analytics workspace resource ID for flow logs"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}