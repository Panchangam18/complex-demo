# Development Environment - US East 1
# This file demonstrates how to use the VPC modules for all three clouds

locals {
  environment = var.environment
  region      = var.aws_region
  
  # Merge common tags with environment-specific tags
  tags = merge(
    var.common_tags,
    var.environment_tags,
    {
      Terragrunt = "true"
      Module     = "network"
    }
  )
}

# AWS VPC Module
module "aws_vpc" {
  source = "../../../modules/aws/vpc"
  
  vpc_cidr           = var.vpc_cidr
  environment        = local.environment
  enable_nat_gateway = true
  enable_flow_logs   = true
  common_tags        = local.tags
}

# GCP VPC Module
module "gcp_vpc" {
  source = "../../../modules/gcp/vpc"
  
  vpc_cidr                     = var.gcp_vpc_cidr
  environment                  = local.environment
  gcp_region                   = var.gcp_region
  gcp_project_id               = var.gcp_project_id
  enable_nat_gateway           = true
  enable_private_google_access = true
  ssh_source_ranges            = ["10.0.0.0/8"]  # Allow SSH from internal network
  common_tags                  = local.tags
}

# Azure VNet Module - Commented out until Azure CLI authentication is configured
# module "azure_vnet" {
#   source = "../../../modules/azure/vnet"
#   
#   vnet_cidr                   = var.azure_vnet_cidr
#   environment                 = local.environment
#   azure_location              = var.azure_location
#   azure_subscription_id       = var.azure_subscription_id
#   availability_zones_enabled  = true
#   enable_nat_gateway          = true
#   enable_gateway_subnet       = true
#   enable_network_watcher      = true
#   enable_flow_logs            = false  # Requires Log Analytics workspace
#   common_tags                 = local.tags
# }

# Outputs for AWS
output "aws_vpc_id" {
  description = "AWS VPC ID for use by other resources"
  value       = module.aws_vpc.vpc_id
}

output "aws_public_subnet_ids" {
  description = "AWS public subnet IDs for load balancers"
  value       = module.aws_vpc.public_subnet_ids
}

output "aws_private_subnet_ids" {
  description = "AWS private subnet IDs for application servers"
  value       = module.aws_vpc.private_subnet_ids
}

output "aws_intra_subnet_ids" {
  description = "AWS intra subnet IDs for databases"
  value       = module.aws_vpc.intra_subnet_ids
}

# Outputs for GCP
output "gcp_vpc_id" {
  description = "GCP VPC ID"
  value       = module.gcp_vpc.vpc_id
}

output "gcp_vpc_name" {
  description = "GCP VPC name"
  value       = module.gcp_vpc.vpc_name
}

output "gcp_public_subnet_ids" {
  description = "GCP public subnet IDs"
  value       = module.gcp_vpc.public_subnet_ids
}

output "gcp_private_subnet_ids" {
  description = "GCP private subnet IDs"
  value       = module.gcp_vpc.private_subnet_ids
}

output "gcp_internal_subnet_ids" {
  description = "GCP internal subnet IDs"
  value       = module.gcp_vpc.internal_subnet_ids
}

# Outputs for Azure - Commented out until Azure module is enabled
# output "azure_vnet_id" {
#   description = "Azure VNet ID"
#   value       = module.azure_vnet.vnet_id
# }

# output "azure_vnet_name" {
#   description = "Azure VNet name"
#   value       = module.azure_vnet.vnet_name
# }

# output "azure_public_subnet_id" {
#   description = "Azure public subnet ID"
#   value       = module.azure_vnet.public_subnet_id
# }

# output "azure_private_subnet_id" {
#   description = "Azure private subnet ID"
#   value       = module.azure_vnet.private_subnet_id
# }

# output "azure_internal_subnet_id" {
#   description = "Azure internal subnet ID"
#   value       = module.azure_vnet.internal_subnet_id
# }