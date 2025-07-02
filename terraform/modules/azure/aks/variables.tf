# =============================================
# Azure AKS Module Variables
# =============================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "azure_location" {
  description = "Azure region for deployment"
  type        = string
  default     = "East US"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.30.12"
}

# Networking
variable "vnet_id" {
  description = "ID of the VNet where AKS will be deployed"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the private subnet for AKS nodes"
  type        = string
}

# System node pool configuration
variable "system_node_count" {
  description = "Number of nodes in the system node pool"
  type        = number
  default     = 2
}

variable "system_vm_size" {
  description = "VM size for system nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_min_nodes" {
  description = "Minimum number of system nodes for auto-scaling"
  type        = number
  default     = 1
}

variable "system_max_nodes" {
  description = "Maximum number of system nodes for auto-scaling"
  type        = number
  default     = 5
}

# Workload node pool configuration
variable "enable_workload_nodepool" {
  description = "Enable additional workload node pool"
  type        = bool
  default     = true
}

variable "workload_node_count" {
  description = "Number of nodes in the workload node pool"
  type        = number
  default     = 2
}

variable "workload_vm_size" {
  description = "VM size for workload nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "workload_min_nodes" {
  description = "Minimum number of workload nodes for auto-scaling"
  type        = number
  default     = 1
}

variable "workload_max_nodes" {
  description = "Maximum number of workload nodes for auto-scaling"
  type        = number
  default     = 10
}

variable "workload_node_taints" {
  description = "Taints for workload nodes"
  type        = list(string)
  default     = []
}

variable "workload_node_labels" {
  description = "Labels for workload nodes"
  type        = map(string)
  default     = {}
}

# Monitoring and logging
variable "enable_monitoring" {
  description = "Enable Azure Monitor for AKS"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log Analytics workspace retention days"
  type        = number
  default     = 30
}

# Container Registry
variable "enable_acr" {
  description = "Enable Azure Container Registry"
  type        = bool
  default     = true
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Standard"
}

# Load Balancer
variable "create_public_lb" {
  description = "Create public IP for load balancer"
  type        = bool
  default     = false
}

# Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
} 