# Development Environment - US East 2
# This file demonstrates how to use the VPC, EKS, GKE, and ECR modules for multi-cloud infrastructure

locals {
  environment = var.environment
  region      = var.aws_region
  
  # Merge common tags with environment-specific tags
  tags = merge(
    var.common_tags,
    var.environment_tags,
    {
      terragrunt = "true"
      module     = "infrastructure"
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

# AWS EKS Cluster
module "aws_eks" {
  source = "../../../modules/aws/eks"
  
  cluster_name    = "${local.environment}-eks-${local.region}"
  cluster_version = var.eks_cluster_version
  vpc_id          = module.aws_vpc.vpc_id
  subnet_ids      = module.aws_vpc.private_subnet_ids
  environment     = local.environment
  
  # Node groups configuration
  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
      disk_size      = 50
      labels = {
        workload = "general"
      }
      taints = []
    }
  }
  
  # Enable IRSA and add-ons
  enable_irsa                         = true
  enable_cluster_autoscaler           = true
  enable_metrics_server               = true
  enable_aws_load_balancer_controller = true
  enable_ebs_csi_driver               = true
  enable_efs_csi_driver               = false
  
  # Security
  enable_cluster_encryption            = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidr_blocks
  
  common_tags = local.tags
}

# GCP GKE Cluster
module "gcp_gke" {
  source = "../../../modules/gcp/gke"
  
  cluster_name        = "${local.environment}-gke-${var.gcp_region}"
  gcp_project_id      = var.gcp_project_id
  gcp_region          = var.gcp_region
  network_name        = module.gcp_vpc.vpc_name
  subnet_name         = module.gcp_vpc.internal_subnet_names[0]
  pods_range_name     = "pods"
  services_range_name = "services"
  environment         = local.environment
  kubernetes_version  = var.gke_cluster_version
  
  # Node pools configuration
  node_pools = {
    general = {
      machine_type       = "e2-standard-4"
      min_count         = 1
      max_count         = 4
      initial_node_count = 2
      disk_size_gb      = 100
      disk_type         = "pd-standard"
      preemptible       = false
      spot              = false
      labels = {
        workload = "general"
      }
      taints = []
      oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }
  
  # Cluster configuration
  enable_private_cluster              = true
  enable_private_endpoint             = false
  enable_workload_identity            = true
  enable_autopilot                    = true
  enable_network_policy               = true
  enable_dataplane_v2                 = true
  enable_dns_cache                    = true
  enable_gke_hub                      = true
  enable_vertical_pod_autoscaling     = true
  enable_horizontal_pod_autoscaling   = true
  enable_gce_persistent_disk_csi_driver = true
  
  # Authorized networks
  master_authorized_networks = [
    {
      cidr_block   = "10.0.0.0/8"
      display_name = "internal-network"
    }
  ]
  
  common_tags = local.tags
}

# AWS ECR Repositories
module "aws_ecr" {
  source = "../../../modules/aws/ecr"
  
  environment = local.environment
  
  repositories = {
    "${local.environment}-frontend" = {
      image_tag_mutability = "MUTABLE"
      scan_on_push        = true
      lifecycle_policy    = null
    }
    "${local.environment}-backend" = {
      image_tag_mutability = "MUTABLE"
      scan_on_push        = true
      lifecycle_policy    = null
    }
  }
  
  enable_image_scanning = true
  encryption_type      = "AES256"
  
  common_tags = local.tags
}

# AWS RDS PostgreSQL Instance
module "aws_rds" {
  source = "../../../modules/aws/rds"
  
  identifier = "${local.environment}-postgres-${local.region}"
  
  # Database configuration
  engine         = "postgres"
  engine_version = "15.7"
  database_name  = "${replace(local.environment, "-", "_")}_db"
  
  # Instance configuration
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  
  # Network configuration
  vpc_id     = module.aws_vpc.vpc_id
  subnet_ids = module.aws_vpc.intra_subnet_ids  # Using intra subnets for databases
  
  # Security - Allow access from EKS cluster
  allowed_security_groups = [module.aws_eks.cluster_security_group_id]
  
  # High availability
  multi_az = var.rds_multi_az
  
  # Backup configuration
  backup_retention_period = var.rds_backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  enabled_cloudwatch_logs_exports       = ["postgresql"]
  
  # Deletion protection
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true
  
  # Parameters for PostgreSQL tuning
  parameters = {
    log_statement            = "all"
    log_min_duration_statement = "1000"  # Log queries taking more than 1 second
    shared_preload_libraries   = "pg_stat_statements"
  }
  
  tags = local.tags
}

# AWS S3 Buckets for observability and assets
# Temporarily commenting out S3 module to fix state issues
# module "aws_s3" {
#   source = "../../../modules/aws/s3"
#   
#   environment = local.environment
#   region      = local.region
#   
#   # Use default bucket names based on environment and region
#   # thanos_bucket_name        = "thanos-metrics-${local.environment}-${local.region}"
#   # elasticsearch_bucket_name = "elasticsearch-snapshots-${local.environment}"
#   # app_assets_bucket_name    = "app-assets-${local.environment}-${local.region}"
#   
#   enable_versioning = true
#   enable_encryption = true
#   
#   # Lifecycle rules for cost optimization
#   lifecycle_rules = {
#     thanos = {
#       transition_to_ia_days      = 30   # Move to Infrequent Access after 30 days
#       transition_to_glacier_days = 90   # Move to Glacier after 90 days
#       expiration_days            = 365  # Delete after 1 year
#     }
#     elasticsearch = {
#       transition_to_ia_days      = 30   # Move to IA after 30 days (minimum for IA)
#       transition_to_glacier_days = 60   # Archive older snapshots
#       expiration_days            = 90   # Keep snapshots for 3 months
#     }
#     app_assets = {
#       transition_to_ia_days      = 90   # Keep assets in standard for 3 months
#       transition_to_glacier_days = 180  # Archive after 6 months
#       expiration_days            = 0    # Never expire app assets
#     }
#   }
#   
#   # Enable cross-region replication for production
#   enable_replication = var.environment == "prod" ? true : false
#   replication_region = var.environment == "prod" ? "us-west-2" : ""
#   
#   tags = local.tags
# }

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

# Outputs for AWS VPC
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

# Outputs for AWS EKS
output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.aws_eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.aws_eks.cluster_endpoint
  sensitive   = true
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.aws_eks.cluster_security_group_id
}

output "eks_oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.aws_eks.oidc_provider_arn
}

output "eks_update_kubeconfig_command" {
  description = "Command to update kubeconfig for EKS"
  value       = module.aws_eks.update_kubeconfig_command
}

# Outputs for AWS ECR
output "ecr_repository_urls" {
  description = "Map of ECR repository names to URLs"
  value       = module.aws_ecr.repository_urls
}

# Outputs for AWS RDS
output "rds_instance_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = module.aws_rds.db_instance_endpoint
}

output "rds_instance_address" {
  description = "The address of the RDS instance"
  value       = module.aws_rds.db_instance_address
}

output "rds_database_name" {
  description = "The name of the database"
  value       = module.aws_rds.db_instance_name
}

output "rds_master_password_secret_arn" {
  description = "The ARN of the master password secret in AWS Secrets Manager"
  value       = module.aws_rds.db_master_password_secret_arn
  sensitive   = true
}

# Outputs for AWS S3 Buckets
# Temporarily commented out due to S3 module being disabled
# output "s3_bucket_ids" {
#   description = "Map of S3 bucket names to their IDs"
#   value       = module.aws_s3.bucket_ids
# }

# output "thanos_bucket_id" {
#   description = "The ID of the Thanos metrics bucket"
#   value       = module.aws_s3.thanos_bucket_id
# }

# output "elasticsearch_bucket_id" {
#   description = "The ID of the Elasticsearch snapshots bucket"
#   value       = module.aws_s3.elasticsearch_bucket_id
# }

# output "app_assets_bucket_id" {
#   description = "The ID of the application assets bucket"
#   value       = module.aws_s3.app_assets_bucket_id
# }

# Outputs for GCP VPC
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

# Outputs for GCP GKE
output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gcp_gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "Endpoint for GKE control plane"
  value       = module.gcp_gke.cluster_endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = module.gcp_gke.cluster_ca_certificate
  sensitive   = true
}

output "gke_workload_identity_pool" {
  description = "Workload Identity Pool for the cluster"
  value       = module.gcp_gke.workload_identity_pool
}

output "gke_get_credentials_command" {
  description = "gcloud command to get credentials for the cluster"
  value       = module.gcp_gke.get_credentials_command
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