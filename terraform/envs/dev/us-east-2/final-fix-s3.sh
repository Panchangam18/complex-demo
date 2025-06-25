#!/bin/bash

echo "=== Final S3 Bucket Fix ==="

# First, let's see what's in the state
echo "Current S3 resources in state:"
terragrunt state list | grep s3_bucket || echo "No S3 buckets in state"

# Get actual bucket names based on the module logic
ACCOUNT_ID="980921723213"
ENVIRONMENT="dev"
REGION="us-east-2"

# Expected bucket names based on the module
THANOS_EXPECTED="thanos-metrics-${ENVIRONMENT}-${REGION}-${ACCOUNT_ID}"
ELASTICSEARCH_EXPECTED="elasticsearch-snapshots-${ENVIRONMENT}-${ACCOUNT_ID}"
APP_ASSETS_EXPECTED="app-assets-${ENVIRONMENT}-${REGION}-${ACCOUNT_ID}"

echo ""
echo "Expected bucket names:"
echo "  Thanos: $THANOS_EXPECTED"
echo "  Elasticsearch: $ELASTICSEARCH_EXPECTED"
echo "  App Assets: $APP_ASSETS_EXPECTED"

# Get actual bucket names
THANOS_ACTUAL=$(aws s3api list-buckets --query "Buckets[?contains(Name,'thanos-metrics-dev')].Name" --output text | head -1)
ELASTICSEARCH_ACTUAL=$(aws s3api list-buckets --query "Buckets[?contains(Name,'elasticsearch-snapshots-dev')].Name" --output text | head -1)
APP_ASSETS_ACTUAL=$(aws s3api list-buckets --query "Buckets[?contains(Name,'app-assets-dev')].Name" --output text | head -1)

echo ""
echo "Actual bucket names found:"
echo "  Thanos: $THANOS_ACTUAL"
echo "  Elasticsearch: $ELASTICSEARCH_ACTUAL"
echo "  App Assets: $APP_ASSETS_ACTUAL"

# If the actual names don't match expected, we need to handle this
if [ "$THANOS_ACTUAL" != "$THANOS_EXPECTED" ] || [ "$ELASTICSEARCH_ACTUAL" != "$ELASTICSEARCH_EXPECTED" ] || [ "$APP_ASSETS_ACTUAL" != "$APP_ASSETS_EXPECTED" ]; then
    echo ""
    echo "Bucket names don't match expected. Cleaning up state and re-importing..."
    
    # Remove all S3 bucket resources from state
    terragrunt state rm 'module.aws_s3.aws_s3_bucket.buckets["thanos"]' 2>/dev/null || true
    terragrunt state rm 'module.aws_s3.aws_s3_bucket.buckets["elasticsearch"]' 2>/dev/null || true
    terragrunt state rm 'module.aws_s3.aws_s3_bucket.buckets["app_assets"]' 2>/dev/null || true
    
    # Import with actual names
    if [ -n "$THANOS_ACTUAL" ] && [ "$THANOS_ACTUAL" != "None" ]; then
        echo "Importing Thanos bucket: $THANOS_ACTUAL"
        terragrunt import -var "thanos_bucket_name=$THANOS_ACTUAL" 'module.aws_s3.aws_s3_bucket.buckets["thanos"]' "$THANOS_ACTUAL"
    fi
    
    if [ -n "$ELASTICSEARCH_ACTUAL" ] && [ "$ELASTICSEARCH_ACTUAL" != "None" ]; then
        echo "Importing Elasticsearch bucket: $ELASTICSEARCH_ACTUAL"
        terragrunt import -var "elasticsearch_bucket_name=$ELASTICSEARCH_ACTUAL" 'module.aws_s3.aws_s3_bucket.buckets["elasticsearch"]' "$ELASTICSEARCH_ACTUAL"
    fi
    
    if [ -n "$APP_ASSETS_ACTUAL" ] && [ "$APP_ASSETS_ACTUAL" != "None" ]; then
        echo "Importing App Assets bucket: $APP_ASSETS_ACTUAL"
        terragrunt import -var "app_assets_bucket_name=$APP_ASSETS_ACTUAL" 'module.aws_s3.aws_s3_bucket.buckets["app_assets"]' "$APP_ASSETS_ACTUAL"
    fi
fi

echo ""
echo "Done!"