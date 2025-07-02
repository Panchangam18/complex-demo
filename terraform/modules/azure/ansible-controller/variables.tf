variable "resource_group_name" {
  description = "Name of the resource group for Ansible Automation Platform"
  type        = string
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "East US"
}

variable "cluster_name" {
  description = "Name prefix for all Ansible Controller resources"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where VMs will be deployed"
  type        = string
}

variable "controller_count" {
  description = "Number of Ansible Controller VMs"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "Size of the Ansible Controller VMs"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "database_vm_size" {
  description = "Size of the database VM"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Admin username for the VMs"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "ansible-automation-platform"
    ManagedBy   = "terraform"
  }
}

variable "enable_direct_public_ip" {
  description = "Enable direct public IP for controller VMs (for external access)"
  type        = bool
  default     = true
} 