#!/bin/bash
# Initialize script for AWS and GCP infrastructure

set -e

echo "🚀 Initializing AWS and GCP Infrastructure"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check authentication
echo "Checking cloud authentication..."
echo "------------------------------"

# Check AWS
if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✓ AWS authenticated${NC}"
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)
    echo "  Account: $AWS_ACCOUNT"
    echo "  User/Role: $AWS_USER"
else
    echo -e "${RED}✗ AWS not authenticated${NC}"
    echo "  Run: aws configure"
    exit 1
fi

echo ""

# Check GCP
if gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo -e "${GREEN}✓ GCP authenticated${NC}"
    GCP_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    GCP_PROJECT=$(gcloud config get-value project 2>/dev/null)
    echo "  Account: $GCP_ACCOUNT"
    echo "  Project: $GCP_PROJECT"
    
    # Verify the project matches what's in terragrunt.hcl
    if [ "$GCP_PROJECT" != "forge-demo-463617" ]; then
        echo -e "${YELLOW}  ⚠️  Warning: Active project ($GCP_PROJECT) doesn't match configured project (forge-demo-463617)${NC}"
        echo "  Run: gcloud config set project forge-demo-463617"
    fi
else
    echo -e "${RED}✗ GCP not authenticated${NC}"
    echo "  Run: gcloud auth application-default login"
    exit 1
fi

echo ""
echo "Terraform Cloud Configuration"
echo "----------------------------"

# Check if terraform is logged in
if terraform version -json 2>/dev/null | grep -q '"provider_selections"'; then
    echo -e "${GREEN}✓ Terraform Cloud authenticated${NC}"
else
    echo -e "${YELLOW}⚠️  Terraform Cloud not configured${NC}"
    echo "  Run: terraform login"
fi

echo ""
echo -e "${GREEN}✅ Ready to deploy AWS and GCP infrastructure!${NC}"
echo ""
echo "Next steps:"
echo "1. Update terraform/terragrunt.hcl with your Terraform Cloud organization"
echo "2. Run: cd terraform && make init ENV=dev REGION=us-east-1"
echo "3. Run: make plan ENV=dev REGION=us-east-1"
echo "4. Run: make apply ENV=dev REGION=us-east-1"