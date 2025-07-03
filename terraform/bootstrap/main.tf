# Bootstrap Terraform Backend Infrastructure
# This creates S3 bucket and DynamoDB table in AWS, and Cloud Storage bucket in GCP
# for storing Terraform state files

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Generate random suffix for globally unique names (only if not provided)
resource "random_string" "suffix" {
  count   = var.bucket_suffix == "" ? 1 : 0
  length  = 6
  lower   = true
  numeric = true
  upper   = false
  special = false
}

locals {
  project_name = "complex-demo"
  environment  = "shared"
  
  # Use provided suffix or generated random suffix
  bucket_suffix = var.bucket_suffix != "" ? var.bucket_suffix : random_string.suffix[0].result
  
  # AWS resources
  aws_bucket_name = "${local.project_name}-tfstate-${local.bucket_suffix}"
  aws_table_name  = "${local.project_name}-tfstate-locks"
  
  # GCP resources
  gcp_bucket_name = "${local.project_name}-tfstate-${local.bucket_suffix}"
  
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    Purpose     = "Terraform Backend"
    ManagedBy   = "Terraform Bootstrap"
  }
  
  # GCP labels must be lowercase with underscores
  gcp_labels = {
    project     = local.project_name
    environment = local.environment
    purpose     = "terraform-backend"
    managed_by  = "terraform-bootstrap"
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = local.common_tags
  }
}

# GCP Provider Configuration
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# AWS S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.aws_bucket_name
  
  lifecycle {
    prevent_destroy = true
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = local.aws_bucket_name
    }
  )
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.aws_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
  
  lifecycle {
    prevent_destroy = true
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = local.aws_table_name
    }
  )
}

# GCP Storage Bucket for Terraform State
resource "google_storage_bucket" "terraform_state" {
  name     = local.gcp_bucket_name
  location = var.gcp_region
  
  force_destroy = false
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.gcp_labels
}

# Output the backend configurations
output "aws_backend_config" {
  description = "AWS S3 backend configuration for Terraform"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    region         = var.aws_region
    key            = "terraform.tfstate" # This will be overridden per environment
    dynamodb_table = aws_dynamodb_table.terraform_locks.id
    encrypt        = true
  }
}

output "gcp_backend_config" {
  description = "GCP Storage backend configuration for Terraform"
  value = {
    bucket = google_storage_bucket.terraform_state.name
    prefix = "terraform/state" # This will be overridden per environment
  }
}

# Generate backend configuration files
resource "local_file" "aws_backend_config" {
  filename = "${path.module}/generated/backend-aws.tf"
  content  = templatefile("${path.module}/templates/backend-aws.tf.tpl", {
    bucket         = aws_s3_bucket.terraform_state.id
    region         = var.aws_region
    dynamodb_table = aws_dynamodb_table.terraform_locks.id
  })
}

resource "local_file" "gcp_backend_config" {
  filename = "${path.module}/generated/backend-gcp.tf"
  content  = templatefile("${path.module}/templates/backend-gcp.tf.tpl", {
    bucket = google_storage_bucket.terraform_state.name
  })
}