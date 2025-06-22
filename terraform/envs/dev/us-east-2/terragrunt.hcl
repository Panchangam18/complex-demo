# Development environment - US East 1 region
include "root" {
  path = find_in_parent_folders()
}

# Environment-specific inputs
inputs = {
  environment = "dev"
  aws_region  = "us-east-2"  # Using Ohio region which is empty
  
  # Network configuration per multicloud strategy
  # AWS: 10.0.0.0/16 - 10.15.0.0/16
  # GCP: 10.16.0.0/16 - 10.31.0.0/16  
  # Azure: 10.32.0.0/16 - 10.47.0.0/16
  
  # AWS network configuration
  vpc_cidr = "10.0.0.0/16"  # AWS Dev VPC
  
  # GCP configuration
  gcp_project_id = "forge-demo-463617"
  gcp_region     = "us-east1"
  gcp_vpc_cidr   = "10.16.0.0/16"  # GCP Dev VPC
  
  # Azure configuration
  azure_subscription_id = "487cf884-e778-4c36-92ce-f419b2c18c59"  # TODO: Replace with actual subscription
  azure_location       = "eastus"
  azure_vnet_cidr      = "10.32.0.0/16"  # Azure Dev VNet
  
  # Environment-specific tags
  environment_tags = {
    Environment = "dev"
    Region      = "us-east-2"
  }
}