#!/bin/bash
# Initial setup script for multicloud Terraform infrastructure

set -e

echo "🚀 Multicloud DevOps Infrastructure Setup"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for required tools
check_tool() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}✗ $1 is not installed${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $1 is installed${NC}"
        return 0
    fi
}

echo "Checking required tools..."
echo "------------------------"

MISSING_TOOLS=0

check_tool terraform || MISSING_TOOLS=1
check_tool terragrunt || MISSING_TOOLS=1
check_tool aws || MISSING_TOOLS=1
check_tool gcloud || MISSING_TOOLS=1
check_tool az || MISSING_TOOLS=1

if [ $MISSING_TOOLS -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}Some tools are missing. Run 'make install-tools' to install them.${NC}"
    exit 1
fi

echo ""
echo "Checking cloud authentication..."
echo "------------------------------"

# Check AWS
if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✓ AWS authenticated${NC}"
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    echo "  Account: $AWS_ACCOUNT"
else
    echo -e "${RED}✗ AWS not authenticated. Run 'aws configure'${NC}"
fi

# Check GCP
if gcloud config get-value account &> /dev/null; then
    echo -e "${GREEN}✓ GCP authenticated${NC}"
    GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "Not set")
    echo "  Project: $GCP_PROJECT"
else
    echo -e "${RED}✗ GCP not authenticated. Run 'gcloud auth application-default login'${NC}"
fi

# Check Azure
if az account show &> /dev/null; then
    echo -e "${GREEN}✓ Azure authenticated${NC}"
    AZURE_SUB=$(az account show --query name -o tsv)
    echo "  Subscription: $AZURE_SUB"
else
    echo -e "${RED}✗ Azure not authenticated. Run 'az login'${NC}"
fi

echo ""
echo "Next steps:"
echo "-----------"
echo "1. Update terraform/terragrunt.hcl with your Terraform Cloud organization"
echo "2. Update envs/dev/us-east-1/terragrunt.hcl with your cloud project IDs"
echo "3. Run 'terraform login' to authenticate with Terraform Cloud"
echo "4. Run 'make init ENV=dev REGION=us-east-1' to initialize"
echo "5. Run 'make plan ENV=dev REGION=us-east-1' to review changes"
echo "6. Run 'make apply ENV=dev REGION=us-east-1' to deploy"

echo ""
echo "✅ Setup check complete!"