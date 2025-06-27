variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Consul will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for Consul servers"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Consul servers"
  type        = list(string)
}

variable "consul_servers" {
  description = "Number of Consul server nodes"
  type        = number
  default     = 3
  
  validation {
    condition     = var.consul_servers == 3 || var.consul_servers == 5
    error_message = "Consul servers must be 3 or 5 for proper consensus."
  }
}

variable "instance_type" {
  description = "EC2 instance type for Consul servers"
  type        = string
  default     = "t3.small"
}

variable "consul_version" {
  description = "Consul version to install"
  type        = string
  default     = "1.17.0"
}

variable "datacenter_name" {
  description = "Consul datacenter name"
  type        = string
}

variable "gossip_key" {
  description = "Gossip encryption key for Consul"
  type        = string
  sensitive   = true
}

variable "allow_consul_from_cidrs" {
  description = "CIDR blocks allowed to access Consul"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "enable_connect" {
  description = "Enable Consul Connect service mesh"
  type        = bool
  default     = true
}

variable "enable_ui" {
  description = "Enable Consul UI"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "key_name" {
  description = "AWS key pair name for SSH access (optional)"
  type        = string
  default     = ""
}

variable "enable_acls" {
  description = "Enable Consul ACLs"
  type        = bool
  default     = false
}

variable "wan_federation_secret" {
  description = "WAN federation secret for multi-datacenter setup"
  type        = string
  default     = ""
  sensitive   = true
}

variable "primary_datacenter" {
  description = "Whether this is the primary datacenter for ACLs and federation"
  type        = bool
  default     = true
} 