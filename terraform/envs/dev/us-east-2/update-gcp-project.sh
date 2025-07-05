#!/bin/bash

# 🔄 Update GCP Project Configuration Script
# This script updates your Terraform configuration to use a new GCP project

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get the new project ID from user
if [ $# -eq 0 ]; then
    echo -e "${BLUE}📋 Available GCP projects:${NC}"
    gcloud projects list --format="table(projectId,name)"
    echo ""
    read -p "Enter the new GCP project ID: " NEW_PROJECT_ID
else
    NEW_PROJECT_ID=$1
fi

# Validate the project exists and user has access
if ! gcloud projects describe $NEW_PROJECT_ID >/dev/null 2>&1; then
    echo -e "${RED}❌ Project $NEW_PROJECT_ID not found or no access${NC}"
    exit 1
fi

OLD_PROJECT_ID="forge-demo-463617"

echo -e "${BLUE}🔄 Updating GCP project configuration${NC}"
echo -e "${BLUE}====================================${NC}"
echo "Old project: $OLD_PROJECT_ID"
echo "New project: $NEW_PROJECT_ID"
echo ""

# Update terragrunt.hcl
echo -e "${YELLOW}📝 Updating terragrunt.hcl...${NC}"
sed -i.backup "s/$OLD_PROJECT_ID/$NEW_PROJECT_ID/g" terragrunt.hcl

# Update the dev environment terragrunt.hcl
echo -e "${YELLOW}📝 Updating envs/dev/us-east-2/terragrunt.hcl...${NC}"
sed -i.backup "s/$OLD_PROJECT_ID/$NEW_PROJECT_ID/g" envs/dev/us-east-2/terragrunt.hcl

# Update any other terraform files that might have the project ID
echo -e "${YELLOW}📝 Updating other terraform files...${NC}"
find . -name "*.tf" -type f -exec grep -l "$OLD_PROJECT_ID" {} \; | while read file; do
    echo "Updating $file"
    sed -i.backup "s/$OLD_PROJECT_ID/$NEW_PROJECT_ID/g" "$file"
done

# Update the gcloud configuration
echo -e "${YELLOW}🔧 Switching gcloud to new project...${NC}"
gcloud config set project $NEW_PROJECT_ID

# Enable required APIs for the new project
echo -e "${YELLOW}🔌 Enabling required GCP APIs...${NC}"
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable storage-api.googleapis.com
gcloud services enable storage-component.googleapis.com

echo -e "\n${GREEN}✅ GCP project configuration updated!${NC}"
echo -e "${GREEN}====================================${NC}"
echo -e "${YELLOW}📋 Summary:${NC}"
echo "  • Updated project ID from $OLD_PROJECT_ID to $NEW_PROJECT_ID"
echo "  • Updated terragrunt.hcl files"
echo "  • Updated terraform configuration files"
echo "  • Switched gcloud configuration"
echo "  • Enabled required APIs"
echo ""
echo -e "${BLUE}🎯 Next steps:${NC}"
echo "  1. Run: cd envs/dev/us-east-2"
echo "  2. Run: terragrunt plan"
echo "  3. Run: terragrunt apply"
echo ""
echo -e "${GREEN}✅ Ready to deploy to new GCP project!${NC}"
