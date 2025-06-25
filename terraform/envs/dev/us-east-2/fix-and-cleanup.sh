#!/bin/bash

echo "=== Fixing Terraform State and Resource Issues ==="

# Check and import Internet Gateway
echo "Checking for existing Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways --region us-east-2 --query 'InternetGateways[?Attachments[0].VpcId==`vpc-06e68b6e652ad6d1a`].InternetGatewayId' --output text)
if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    echo "Found Internet Gateway: $IGW_ID"
    terragrunt import module.aws_vpc.aws_internet_gateway.main "$IGW_ID" 2>/dev/null || echo "IGW already imported"
fi

# Fix S3 bucket imports with correct bucket names
echo "Fixing S3 bucket imports..."

# List actual buckets and their tags
echo "Checking S3 buckets..."
aws s3api list-buckets --query 'Buckets[?contains(Name, `dev`) && contains(Name, `us-east-2`)].Name' --output json > buckets.json

# Check each bucket type
THANOS_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'thanos') && contains(Name,'dev')].Name" --output text | head -1)
APP_ASSETS_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'app-assets') && contains(Name,'dev')].Name" --output text | head -1)
ELASTICSEARCH_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'elasticsearch') && contains(Name,'dev')].Name" --output text | head -1)

echo "Found buckets:"
echo "  Thanos: $THANOS_BUCKET"
echo "  App Assets: $APP_ASSETS_BUCKET"
echo "  Elasticsearch: $ELASTICSEARCH_BUCKET"

# Remove from state if they exist
terragrunt state rm 'module.aws_s3.aws_s3_bucket.buckets["thanos"]' 2>/dev/null || true
terragrunt state rm 'module.aws_s3.aws_s3_bucket.buckets["app_assets"]' 2>/dev/null || true
terragrunt state rm 'module.aws_s3.aws_s3_bucket.buckets["elasticsearch"]' 2>/dev/null || true

# Re-import with correct names
if [ -n "$THANOS_BUCKET" ] && [ "$THANOS_BUCKET" != "None" ]; then
    echo "Re-importing Thanos bucket: $THANOS_BUCKET"
    terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["thanos"]' "$THANOS_BUCKET"
fi

if [ -n "$APP_ASSETS_BUCKET" ] && [ "$APP_ASSETS_BUCKET" != "None" ]; then
    echo "Re-importing App Assets bucket: $APP_ASSETS_BUCKET"
    terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["app_assets"]' "$APP_ASSETS_BUCKET"
fi

if [ -n "$ELASTICSEARCH_BUCKET" ] && [ "$ELASTICSEARCH_BUCKET" != "None" ]; then
    echo "Re-importing Elasticsearch bucket: $ELASTICSEARCH_BUCKET"
    terragrunt import 'module.aws_s3.aws_s3_bucket.buckets["elasticsearch"]' "$ELASTICSEARCH_BUCKET"
fi

echo "Running terraform refresh to sync state..."
terragrunt refresh

echo "Done!"