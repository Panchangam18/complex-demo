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