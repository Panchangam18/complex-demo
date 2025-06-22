variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
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

variable "gcp_region" {
  description = "GCP region"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "enable_nat_gateway" {
  description = "Enable Cloud NAT for private subnets"
  type        = bool
  default     = true
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for Google services"
  type        = bool
  default     = true
}

variable "ssh_source_ranges" {
  description = "Source IP ranges allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "common_tags" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}