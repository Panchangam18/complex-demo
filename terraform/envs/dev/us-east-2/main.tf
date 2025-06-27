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
  eks_cluster_names  = ["${local.environment}-eks-${local.region}"]
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
  
  cluster_name        = "${local.environment}-gke-public-${var.gcp_region}"
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
  enable_private_cluster              = false
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
  
  gcp_labels = var.gcp_labels
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

# Generate gossip encryption key for Consul
resource "random_password" "consul_gossip_key" {
  length  = 32
  special = false
}

# AWS EC2-based Consul Cluster (Primary Datacenter)
module "consul_primary" {
  source = "../../../modules/consul/ec2-cluster"
  
  environment             = local.environment
  aws_region             = var.aws_region
  vpc_id                 = module.aws_vpc.vpc_id
  public_subnet_ids      = module.aws_vpc.public_subnet_ids
  private_subnet_ids     = module.aws_vpc.private_subnet_ids
  
  datacenter_name        = "aws-${local.environment}-${local.region}"
  gossip_key             = random_password.consul_gossip_key.result
  consul_servers         = var.consul_servers
  instance_type          = var.consul_instance_type
  
  enable_connect         = true
  enable_ui              = true
  enable_acls            = false  # Start with ACLs disabled for simplicity
  primary_datacenter     = true
  
  allow_consul_from_cidrs = [
    var.vpc_cidr,           # AWS VPC
    var.gcp_vpc_cidr,       # GCP VPC  
    var.azure_vnet_cidr     # Azure VNet
  ]
  
  common_tags = local.tags
}

# Provider configuration for EKS cluster
provider "kubernetes" {
  alias = "eks"
  
  host                   = module.aws_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aws_eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_id, "--region", var.aws_region, "--profile", var.aws_profile]
    env = {
      AWS_PROFILE = var.aws_profile
    }
  }
}

provider "helm" {
  alias = "eks"
  
  kubernetes {
    host                   = module.aws_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.aws_eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_id, "--region", var.aws_region, "--profile", var.aws_profile]
      env = {
        AWS_PROFILE = var.aws_profile
      }
    }
  }
}

# EKS Consul Client (Secondary Datacenter) - DISABLED due to storage/timeout issues
# TODO: Re-enable after fixing EBS CSI driver IAM role configuration
# module "consul_eks_client" {
#   source = "../../../modules/consul/k8s-client"
#   
#   cluster_name       = module.aws_eks.cluster_id
#   cluster_endpoint   = module.aws_eks.cluster_endpoint
#   region             = var.aws_region
#   environment        = local.environment
#   cloud_provider     = "aws"
#   
#   datacenter_name    = "eks-${local.environment}-${local.region}"
#   primary_datacenter = "eks-${local.environment}-${local.region}"
#   
#   gossip_key              = random_password.consul_gossip_key.result
#   wan_federation_secret   = ""
#   primary_consul_servers  = []
#   consul_master_token     = ""
#   
#   enable_connect         = true
#   enable_connect_inject  = true
#   enable_ui              = false  # UI runs on primary cluster
#   enable_prometheus_metrics = true
#   enable_sync_catalog    = true
#   enable_acls           = false
#   
#   aws_profile = var.aws_profile
#   
#   providers = {
#     kubernetes = kubernetes.eks
#     helm       = helm.eks
#   }
#   
#   depends_on = [
#     module.aws_eks
#   ]
# }

# Get GCP access token for GKE authentication
data "google_client_config" "default" {}

# Provider configuration for GKE cluster
provider "kubernetes" {
  alias = "gke"
  
  host                   = "https://${module.gcp_gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gcp_gke.cluster_ca_certificate)
}

provider "helm" {
  alias = "gke"
  
  kubernetes {
    host                   = "https://${module.gcp_gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gcp_gke.cluster_ca_certificate)
  }
}

# GKE Consul Client (Secondary Datacenter) - DISABLED due to storage/timeout issues
# TODO: Re-enable after fixing storage and authentication issues
# module "consul_gke_client" {
#   source = "../../../modules/consul/k8s-client"
#   
#   cluster_name           = module.gcp_gke.cluster_name
#   cluster_endpoint       = module.gcp_gke.cluster_endpoint
#   cluster_ca_certificate = module.gcp_gke.cluster_ca_certificate
#   region                 = var.gcp_region
#   environment            = local.environment
#   cloud_provider         = "gcp"
#   
#   datacenter_name    = "gke-${local.environment}-${var.gcp_region}"
#   primary_datacenter = "gke-${local.environment}-${var.gcp_region}"
#   
#   gossip_key              = random_password.consul_gossip_key.result
#   wan_federation_secret   = ""
#   primary_consul_servers  = []
#   consul_master_token     = ""
#   
#   enable_connect         = true
#   enable_connect_inject  = true
#   enable_ui              = false  # UI runs on primary cluster
#   enable_prometheus_metrics = true
#   enable_sync_catalog    = true
#   enable_acls           = false
#   
#   providers = {
#     kubernetes = kubernetes.gke
#     helm       = helm.gke
#   }
#   
#   depends_on = [
#     module.gcp_gke
#   ]
# }

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

# Outputs for Consul
output "consul_ui_url" {
  description = "Consul UI URL"
  value       = module.consul_primary.consul_ui_url
}

output "consul_primary_datacenter" {
  description = "Primary Consul datacenter information"
  value       = module.consul_primary.consul_connection_info
}

# Temporarily disabled outputs for K8s Consul clients
# output "consul_eks_datacenter" {
#   description = "EKS Consul datacenter information"
#   value       = module.consul_eks_client.consul_client_info
# }

# output "consul_gke_datacenter" {
#   description = "GKE Consul datacenter information"
#   value       = module.consul_gke_client.consul_client_info
# }

output "consul_gossip_key" {
  description = "Consul gossip encryption key"
  value       = random_password.consul_gossip_key.result
  sensitive   = true
}

# Consul Service Discovery Summary
output "consul_summary" {
  description = "Complete Consul multi-cloud setup summary"
  value = {
    ui_url              = module.consul_primary.consul_ui_url
    primary_datacenter  = "aws-${local.environment}-${local.region}"
    secondary_datacenters = [
      # "eks-${local.environment}-${local.region}",     # Disabled
      # "gke-${local.environment}-${var.gcp_region}"    # Disabled
    ]
    connect_enabled     = true
    federation_enabled  = false  # Disabled until K8s clients are working
    mesh_gateways      = [
      "AWS EC2 Primary Cluster"
      # "EKS Secondary Cluster",    # Disabled
      # "GKE Secondary Cluster"     # Disabled
    ]
    service_discovery  = "Multi-cloud service catalog sync enabled"
  }
}

# Outputs for ArgoCD and Observability
output "argocd_url" {
  description = "ArgoCD server public URL"
  value       = module.argocd.argocd_url
}

output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = module.argocd.argocd_admin_password
  sensitive   = true
}

output "grafana_url" {
  description = "Grafana public URL"
  value       = module.argocd.grafana_url
}

output "prometheus_url" {
  description = "Prometheus public URL"
  value       = module.argocd.prometheus_url
}

output "observability_summary" {
  description = "Complete observability stack information"
  value       = module.argocd.observability_summary
}