variable "aws_region" {
  description = "AWS region for the S3 bucket"
  type        = string
  default     = "us-east-1"
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = "forge-demo-463617"
}

variable "gcp_region" {
  description = "GCP region for the storage bucket"
  type        = string
  default     = "us-east1"
}