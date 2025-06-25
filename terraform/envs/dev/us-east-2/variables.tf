# Variables for the development environment

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the AWS VPC"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
}

variable "gcp_vpc_cidr" {
  description = "CIDR block for the GCP VPC"
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_location" {
  description = "Azure location"
  type        = string
}

variable "azure_vnet_cidr" {
  description = "CIDR block for the Azure VNet"
  type        = string
}

variable "common_tags" {
  description = "Common tags from root"
  type        = map(string)
  default     = {}
}

variable "environment_tags" {
  description = "Environment-specific tags"
  type        = map(string)
  default     = {}
}

variable "gcp_labels" {
  description = "GCP-specific labels (must be lowercase)"
  type        = map(string)
  default     = {}
}

# EKS Variables
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the EKS API server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# GKE Variables
variable "gke_cluster_version" {
  description = "Kubernetes version for GKE cluster"
  type        = string
  default     = "1.32"
}

# RDS Variables
variable "rds_instance_class" {
  description = "Instance class for RDS"
  type        = string
  default     = "db.t3.small"
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum allocated storage for RDS autoscaling in GB"
  type        = number
  default     = 100
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = true
}

variable "rds_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
}

variable "aws_profile" {
  description = "AWS profile to use for authentication"
  type        = string
  default     = "default"
}