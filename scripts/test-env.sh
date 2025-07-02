#!/bin/bash

# Test Environment Configuration Script
# This script verifies that all authentication and environment variables are working

set -e

echo "🔍 Testing Multi-Cloud Environment Configuration..."

# Load environment variables
if [ -f ".env" ]; then
    source .env
    echo "✅ .env file loaded"
else
    echo "❌ .env file not found in root directory"
    exit 1
fi

echo ""
echo "🔐 Testing Cloud Authentication..."

# Test Azure CLI
echo -n "Azure: "
if az account show --query "name" -o tsv > /dev/null 2>&1; then
    AZURE_SUB=$(az account show --query "name" -o tsv)
    echo "✅ Authenticated as: $AZURE_SUB"
else
    echo "❌ Not authenticated. Run: az login"
fi

# Test AWS CLI
echo -n "AWS: "
if aws sts get-caller-identity --profile "${AWS_PROFILE}" > /dev/null 2>&1; then
    AWS_ACCOUNT=$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --query "Account" --output text)
    echo "✅ Authenticated with profile: ${AWS_PROFILE} (Account: $AWS_ACCOUNT)"
else
    echo "❌ Not authenticated. Check AWS profile: ${AWS_PROFILE}"
fi

# Test GCP CLI
echo -n "GCP: "
if gcloud auth list --filter="status:ACTIVE" --format="value(account)" > /dev/null 2>&1; then
    GCP_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)")
    echo "✅ Authenticated as: $GCP_ACCOUNT"
else
    echo "❌ Not authenticated. Run: gcloud auth login"
fi

echo ""
echo "📋 Environment Variables:"
echo "  Environment: ${ENVIRONMENT}"
echo "  AWS Region: ${AWS_REGION}"
echo "  AWS Profile: ${AWS_PROFILE}"
echo "  GCP Project: ${GCP_PROJECT_ID}"
echo "  Azure Location: eastus"

echo ""
echo "🐳 JFrog Artifactory:"
echo "  URL: ${ARTIFACTORY_URL}"
echo "  Username: ${ARTIFACTORY_USERNAME}"
echo "  Token: ${ARTIFACTORY_TOKEN:0:20}... (truncated)"

echo ""
echo "🎯 Terraform Validation:"
cd terraform/envs/dev/us-east-2
if terraform validate > /dev/null 2>&1; then
    echo "✅ Terraform configuration is valid"
else
    echo "❌ Terraform configuration has errors"
fi

echo ""
echo "🎉 Environment test complete!"
echo ""
echo "🚀 You're ready to deploy! Next steps:"
echo "   1. Deploy AWX: cd terraform/envs/dev/us-east-2 && terraform plan"
echo "   2. Run deployment: source ../../../../.env && terraform apply" 