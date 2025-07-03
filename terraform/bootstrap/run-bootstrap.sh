#!/bin/bash

# Bootstrap script to create Terraform backend infrastructure
# Usage: ./run-bootstrap.sh [bucket_suffix]

set -e

# Default suffix from existing bucket (if not provided)
DEFAULT_SUFFIX="hp9dga"
BUCKET_SUFFIX=${1:-$DEFAULT_SUFFIX}

echo "Creating Terraform backend infrastructure with suffix: $BUCKET_SUFFIX"

# Initialize Terraform
terraform init

# Plan with the specified suffix
terraform plan -var="bucket_suffix=$BUCKET_SUFFIX"

# Apply with the specified suffix
terraform apply -var="bucket_suffix=$BUCKET_SUFFIX" -auto-approve

echo "Bootstrap completed successfully!"
echo "S3 Bucket: $(terraform output -raw aws_s3_bucket_name)"
echo "DynamoDB Table: $(terraform output -raw aws_dynamodb_table_name)"
echo ""

# Automatically update terragrunt.hcl with the correct bucket name
echo "Updating terragrunt.hcl with correct bucket name..."
./update-terragrunt.sh

echo ""
echo "🎉 Bootstrap complete! Your terragrunt.hcl has been updated automatically." 