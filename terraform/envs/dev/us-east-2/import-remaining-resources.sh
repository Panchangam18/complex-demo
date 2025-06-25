#!/bin/bash

# Import remaining AWS resources that are causing conflicts

echo "Importing remaining AWS resources..."

# Import RDS monitoring role
echo "Importing RDS monitoring IAM role..."
terragrunt import 'module.aws_rds.aws_iam_role.monitoring[0]' dev-postgres-us-east-2-rds-monitoring-role 2>/dev/null || echo "RDS monitoring role already imported"

# Import S3 buckets with the actual bucket names
echo "Importing S3 buckets..."

# Get the actual bucket names
THANOS_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'thanos-metrics-dev')].Name" --output text | head -1)
APP_ASSETS_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'app-assets-dev')].Name" --output text | head -1)
ELASTICSEARCH_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'elasticsearch-snapshots-dev')].Name" --output text | head -1)

if [ -n "$THANOS_BUCKET" ]; then
    echo "Importing Thanos bucket: $THANOS_BUCKET"
    terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["thanos"]' "$THANOS_BUCKET" 2>/dev/null || echo "Thanos bucket already imported"
fi

if [ -n "$APP_ASSETS_BUCKET" ]; then
    echo "Importing App Assets bucket: $APP_ASSETS_BUCKET"
    terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["app_assets"]' "$APP_ASSETS_BUCKET" 2>/dev/null || echo "App assets bucket already imported"
fi

if [ -n "$ELASTICSEARCH_BUCKET" ]; then
    echo "Importing Elasticsearch bucket: $ELASTICSEARCH_BUCKET"
    terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["elasticsearch"]' "$ELASTICSEARCH_BUCKET" 2>/dev/null || echo "Elasticsearch bucket already imported"
fi

echo "Import completed!"