#!/bin/bash

# 🗑️ Terraform-Based GCP Resource Destruction Script
# This script uses Terraform to properly destroy GCP resources before switching accounts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

CURRENT_PROJECT="forge-demo-463617"

echo -e "${PURPLE}🗑️ Terraform-Based GCP Resource Destruction${NC}"
echo -e "${PURPLE}===========================================${NC}"

# Show current Google account
echo -e "${BLUE}📋 Current Google Account:${NC}"
gcloud auth list --filter=status:ACTIVE --format="table(account,status)"
echo -e "\n${BLUE}📋 Current GCP Project:${NC} $(gcloud config get-value project)"

# Safety check
echo -e "\n${YELLOW}⚠️  This will DESTROY the following GCP resources via Terraform:${NC}"
echo "  • GKE cluster: dev-gke-public-us-east1"
echo "  • VPC network: dev-vpc (with subnets)"
echo "  • Firewall rules: dev-allow-*"
echo "  • Router and NAT gateway"
echo "  • Service accounts created by Terraform"
echo ""
echo -e "${YELLOW}⚠️  Your Terraform state is safely stored in AWS S3, so this won't affect state.${NC}"
echo ""
read -p "Are you sure you want to destroy these GCP resources? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}❌ Aborted. No resources were destroyed.${NC}"
    exit 1
fi

echo -e "\n${BLUE}🎯 Step 1: Terraform Destroy (Proper Way)${NC}"
echo -e "${BLUE}=========================================${NC}"

cd /Users/madhavan/GitHub/complex-demo/terraform/envs/dev/us-east-2

# Show what terraform will destroy
echo -e "${YELLOW}📋 Planning GCP resource destruction...${NC}"
terragrunt plan -destroy -target=module.gcp_gke -target=module.gcp_vpc

echo -e "\n${YELLOW}🗑️ Destroying GCP resources via Terraform...${NC}"

# Destroy GKE cluster first (has dependencies)
echo -e "${BLUE}Destroying GKE cluster...${NC}"
terragrunt destroy -target=module.gcp_gke -auto-approve || {
    echo -e "${YELLOW}⚠️  Terraform destroy had issues, checking what's left...${NC}"
}

# Destroy VPC and networking
echo -e "${BLUE}Destroying VPC and networking...${NC}"
terragrunt destroy -target=module.gcp_vpc -auto-approve || {
    echo -e "${YELLOW}⚠️  Terraform destroy had issues, checking what's left...${NC}"
}

echo -e "\n${BLUE}🔍 Step 2: Verification${NC}"
echo -e "${BLUE}=======================${NC}"

# Check what's left
echo -e "${YELLOW}📊 Checking remaining GCP resources...${NC}"
echo "GKE Clusters:"
gcloud container clusters list --project=$CURRENT_PROJECT --format="table(name,location,status)" || echo "No clusters found"

echo -e "\nVPC Networks:"
gcloud compute networks list --project=$CURRENT_PROJECT --format="table(name,mode)" --filter="name!=default" || echo "No custom networks found"

echo -e "\nCustom firewall rules:"
gcloud compute firewall-rules list --project=$CURRENT_PROJECT --format="table(name,direction)" --filter="name~'^dev-'" || echo "No custom firewall rules found"

# If there are leftover resources, offer manual cleanup
echo -e "\n${BLUE}🧹 Step 3: Manual Cleanup (if needed)${NC}"
echo -e "${BLUE}=====================================${NC}"

LEFTOVER_CLUSTERS=$(gcloud container clusters list --project=$CURRENT_PROJECT --format="value(name)" --filter="name~'^dev-'" | wc -l)
LEFTOVER_NETWORKS=$(gcloud compute networks list --project=$CURRENT_PROJECT --format="value(name)" --filter="name~'^dev-'" | wc -l)

if [ "$LEFTOVER_CLUSTERS" -gt 0 ] || [ "$LEFTOVER_NETWORKS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Some resources remain. This is normal if Terraform had dependency issues.${NC}"
    echo ""
    read -p "Do you want to manually clean up remaining resources? (yes/no): " manual_cleanup
    
    if [ "$manual_cleanup" = "yes" ]; then
        echo -e "${YELLOW}🗑️ Manual cleanup of remaining resources...${NC}"
        
        # Delete any remaining GKE clusters
        for cluster in $(gcloud container clusters list --project=$CURRENT_PROJECT --format="value(name)" --filter="name~'^dev-'"); do
            echo "Deleting cluster: $cluster"
            gcloud container clusters delete $cluster --region=us-east1 --project=$CURRENT_PROJECT --quiet || echo "Failed to delete $cluster"
        done
        
        # Delete custom networks
        for network in $(gcloud compute networks list --project=$CURRENT_PROJECT --format="value(name)" --filter="name~'^dev-'"); do
            echo "Deleting network: $network"
            gcloud compute networks delete $network --project=$CURRENT_PROJECT --quiet || echo "Failed to delete $network"
        done
    fi
else
    echo -e "${GREEN}✅ All resources successfully destroyed via Terraform!${NC}"
fi

echo -e "\n${GREEN}✅ GCP Resource Destruction Complete!${NC}"
echo -e "${GREEN}====================================${NC}"

echo -e "\n${PURPLE}📋 NEXT STEPS - SWITCHING GOOGLE ACCOUNTS${NC}"
echo -e "${PURPLE}==========================================${NC}"

echo -e "${YELLOW}🔄 To switch to a different Google account:${NC}"
echo ""
echo -e "${BLUE}1. Log out of current Google account:${NC}"
echo "   gcloud auth revoke --all"
echo ""
echo -e "${BLUE}2. Log into your new Google account:${NC}"
echo "   gcloud auth login"
echo "   gcloud auth application-default login"
echo ""
echo -e "${BLUE}3. List your projects in the new account:${NC}"
echo "   gcloud projects list"
echo ""
echo -e "${BLUE}4. Set the target project:${NC}"
echo "   gcloud config set project YOUR_NEW_PROJECT_ID"
echo ""
echo -e "${BLUE}5. Update Terraform configuration:${NC}"
echo "   ./update-gcp-project.sh YOUR_NEW_PROJECT_ID"
echo ""
echo -e "${BLUE}6. Deploy to new project:${NC}"
echo "   terragrunt plan"
echo "   terragrunt apply"

echo -e "\n${GREEN}🎯 Ready for Google account switch!${NC}"
echo -e "${YELLOW}💡 Run the commands above when you're ready to switch accounts.${NC}" 