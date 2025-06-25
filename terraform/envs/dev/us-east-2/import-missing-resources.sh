#!/bin/bash

echo "=== Importing Missing Resources ==="

# Import Internet Gateway
echo "Importing Internet Gateway..."
terragrunt import module.aws_vpc.aws_internet_gateway.main igw-09eccfb47208b73db

# Import S3 Buckets
echo "Importing S3 Buckets..."
terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["thanos"]' thanos-metrics-dev-us-east-2-980921723213
terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["app_assets"]' app-assets-dev-us-east-2-980921723213
terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["elasticsearch"]' elasticsearch-snapshots-dev-980921723213

echo "Done!"