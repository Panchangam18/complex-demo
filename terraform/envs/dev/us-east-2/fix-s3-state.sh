#!/bin/bash

echo "=== Fixing S3 Bucket State ==="

# Remove all S3 resources from state
echo "Removing S3 resources from state..."
terragrunt state rm module.aws_s3.aws_s3_bucket.buckets 2>/dev/null || true
terragrunt state rm module.aws_s3.aws_s3_bucket_public_access_block.buckets 2>/dev/null || true
terragrunt state rm module.aws_s3.aws_s3_bucket_versioning.buckets 2>/dev/null || true
terragrunt state rm module.aws_s3.aws_s3_bucket_server_side_encryption_configuration.buckets 2>/dev/null || true
terragrunt state rm module.aws_s3.aws_s3_bucket_lifecycle_configuration.buckets 2>/dev/null || true
terragrunt state rm module.aws_s3.aws_s3_bucket_policy.thanos 2>/dev/null || true
terragrunt state rm module.aws_s3.aws_s3_bucket_policy.elasticsearch 2>/dev/null || true

# Import all S3 buckets together
echo "Importing S3 buckets..."
terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["thanos"]' thanos-metrics-dev-us-east-2-980921723213
terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["app_assets"]' app-assets-dev-us-east-2-980921723213
terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["elasticsearch"]' elasticsearch-snapshots-dev-980921723213

echo "Done!"