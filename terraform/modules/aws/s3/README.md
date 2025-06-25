# AWS S3 Buckets Module

This module creates S3 buckets for:
- Thanos metrics storage
- Elasticsearch snapshots
- Application assets

## Features

- Server-side encryption (AES256 or KMS)
- Versioning
- Lifecycle policies for cost optimization
- Public access blocking
- Optional cross-region replication
- Bucket policies for service access

## Usage

```hcl
module "s3_buckets" {
  source = "../../../modules/aws/s3"

  environment = "dev"
  region      = "us-east-2"
  
  # Optional: Custom bucket names
  # thanos_bucket_name        = "my-custom-thanos-bucket"
  # elasticsearch_bucket_name = "my-custom-es-bucket"
  # app_assets_bucket_name    = "my-custom-assets-bucket"
  
  enable_versioning = true
  enable_encryption = true
  
  # Optional: Use KMS key for encryption
  # kms_key_arn = aws_kms_key.s3.arn
  
  # Custom lifecycle rules
  lifecycle_rules = {
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
      expiration_days            = 0  # No expiration
    }
  }
  
  # Optional: Enable cross-region replication
  # enable_replication = true
  # replication_region = "us-west-2"
  
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
```

## Outputs

- `bucket_ids` - Map of bucket names to IDs
- `bucket_arns` - Map of bucket names to ARNs
- `thanos_bucket_id` - Thanos bucket ID
- `elasticsearch_bucket_id` - Elasticsearch bucket ID
- `app_assets_bucket_id` - App assets bucket ID