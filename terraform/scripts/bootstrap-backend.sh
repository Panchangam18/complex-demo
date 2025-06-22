#!/bin/bash
# Bootstrap script to create Terraform backend infrastructure

set -e

echo "🚀 Terraform Backend Bootstrap"
echo "=============================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Change to bootstrap directory
cd "$(dirname "$0")/../bootstrap"

echo -e "${BLUE}This script will create:${NC}"
echo "  • S3 bucket in AWS for Terraform state"
echo "  • DynamoDB table in AWS for state locking"
echo "  • Cloud Storage bucket in GCP for Terraform state"
echo ""

# Check for existing state
if [ -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}⚠️  Warning: Bootstrap state already exists${NC}"
    echo "Backend infrastructure may already be created."
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 0
    fi
fi

# Initialize Terraform
echo -e "${BLUE}Initializing Terraform...${NC}"
terraform init

# Plan
echo ""
echo -e "${BLUE}Planning infrastructure...${NC}"
terraform plan -out=tfplan

# Confirm before applying
echo ""
echo -e "${YELLOW}Please review the plan above.${NC}"
read -p "Do you want to create this infrastructure? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    rm -f tfplan
    exit 0
fi

# Apply
echo ""
echo -e "${BLUE}Creating backend infrastructure...${NC}"
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# Display outputs
echo ""
echo -e "${GREEN}✅ Backend infrastructure created successfully!${NC}"
echo ""
echo -e "${BLUE}Backend Configuration:${NC}"
terraform output -json | jq '.'

# Save outputs to file
echo ""
echo -e "${BLUE}Saving configuration...${NC}"
terraform output -json > generated/backend-config.json

echo ""
echo -e "${GREEN}✅ Bootstrap complete!${NC}"
echo ""
echo "The backend configuration has been saved to:"
echo "  bootstrap/generated/backend-config.json"
echo ""
echo "Next steps:"
echo "1. Update terragrunt.hcl with the backend configuration"
echo "2. Run 'make init' in your environment directories"