variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "thanos_bucket_name" {
  description = "Name of the S3 bucket for Thanos metrics storage"
  type        = string
  default     = ""
}

variable "elasticsearch_bucket_name" {
  description = "Name of the S3 bucket for Elasticsearch snapshots"
  type        = string
  default     = ""
}

variable "app_assets_bucket_name" {
  description = "Name of the S3 bucket for application assets"
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable versioning for all buckets"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for all buckets"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of KMS key for bucket encryption (if not provided, AES256 will be used)"
  type        = string
  default     = null
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for buckets"
  type = object({
    thanos = object({
      transition_to_ia_days      = number
      transition_to_glacier_days = number
      expiration_days            = number
    })
    elasticsearch = object({
      transition_to_ia_days      = number
      transition_to_glacier_days = number
      expiration_days            = number
    })
    app_assets = object({
      transition_to_ia_days      = number
      transition_to_glacier_days = number
      expiration_days            = number
    })
  })
  default = {
    thanos = {
      transition_to_ia_days      = 30
      transition_to_glacier_days = 90
      expiration_days            = 365
    }
    elasticsearch = {
      transition_to_ia_days      = 7
      transition_to_glacier_days = 30
      expiration_days            = 90
    }
    app_assets = {
      transition_to_ia_days      = 90
      transition_to_glacier_days = 180
      expiration_days            = 0  # No expiration for app assets
    }
  }
}

variable "enable_replication" {
  description = "Enable cross-region replication"
  type        = bool
  default     = false
}

variable "replication_region" {
  description = "Target region for cross-region replication"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}