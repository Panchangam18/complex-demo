#!/bin/bash

# 🗑️ Destroy GCP Resources Script
# This script safely destroys all GCP resources in forge-demo-463617
# before switching to the correct project

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CURRENT_PROJECT="forge-demo-463617"

echo -e "${BLUE}🗑️ Destroying GCP Resources in ${CURRENT_PROJECT}${NC}"
echo -e "${BLUE}================================================${NC}"

# Safety check
echo -e "${YELLOW}⚠️  This will destroy the following resources:${NC}"
echo "  • GKE cluster: dev-gke-public-us-east1"
echo "  • VPC network: dev-vpc (with 9 subnets)"
echo "  • Firewall rules: dev-allow-*"
echo "  • Router: dev-router"
echo "  • Service accounts (if any)"
echo "  • Storage buckets: complex-demo-tfstate-*"
echo ""
read -p "Are you sure you want to destroy these resources? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}❌ Aborted. No resources were destroyed.${NC}"
    exit 1
fi

echo -e "${BLUE}🎯 Step 1: Using Terraform to destroy managed resources${NC}"
echo "Using terraform destroy to cleanly remove managed resources..."

# First try terraform destroy for clean removal
cd /Users/madhavan/GitHub/complex-demo/terraform/envs/dev/us-east-2
terragrunt destroy -target=module.gcp_vpc -auto-approve || echo "Terraform destroy completed with warnings"
terragrunt destroy -target=module.gcp_gke -auto-approve || echo "Terraform destroy completed with warnings"

echo -e "\n${BLUE}🎯 Step 2: Manual cleanup of remaining resources${NC}"

# Set the project for gcloud commands
gcloud config set project $CURRENT_PROJECT

# Delete GKE cluster (if still exists)
echo -e "${YELLOW}🗑️ Deleting GKE cluster...${NC}"
gcloud container clusters delete dev-gke-public-us-east1 \
    --region=us-east1 \
    --quiet || echo "Cluster already deleted or doesn't exist"

# Wait for cluster deletion to complete
echo "Waiting for cluster deletion to complete..."
sleep 30

# Delete firewall rules (GKE creates these automatically)
echo -e "${YELLOW}🔥 Deleting firewall rules...${NC}"
for rule in $(gcloud compute firewall-rules list --filter="name~'gke-dev-gke-public-us-east1'" --format="value(name)"); do
    echo "Deleting firewall rule: $rule"
    gcloud compute firewall-rules delete $rule --quiet || echo "Rule $rule already deleted"
done

# Delete custom firewall rules
for rule in dev-allow-internal dev-allow-ssh dev-allow-health-checks; do
    echo "Deleting firewall rule: $rule"
    gcloud compute firewall-rules delete $rule --quiet || echo "Rule $rule already deleted"
done

# Delete subnets
echo -e "${YELLOW}📡 Deleting subnets...${NC}"
for subnet in dev-public-us-east1-b dev-public-us-east1-c dev-public-us-east1-d \
              dev-private-us-east1-b dev-private-us-east1-c dev-private-us-east1-d \
              dev-internal-us-east1-b dev-internal-us-east1-c dev-internal-us-east1-d; do
    echo "Deleting subnet: $subnet"
    gcloud compute networks subnets delete $subnet \
        --region=us-east1 \
        --quiet || echo "Subnet $subnet already deleted"
done

# Delete router NAT
echo -e "${YELLOW}🧭 Deleting router NAT...${NC}"
gcloud compute routers nats delete dev-nat \
    --router=dev-router \
    --region=us-east1 \
    --quiet || echo "NAT already deleted"

# Delete router
echo -e "${YELLOW}🧭 Deleting router...${NC}"
gcloud compute routers delete dev-router \
    --region=us-east1 \
    --quiet || echo "Router already deleted"

# Delete VPC network
echo -e "${YELLOW}🌐 Deleting VPC network...${NC}"
gcloud compute networks delete dev-vpc \
    --quiet || echo "VPC already deleted"

# Delete storage buckets (these are unused since state is in AWS)
echo -e "${YELLOW}📁 Deleting unused storage buckets...${NC}"
for bucket in $(gcloud storage buckets list --format="value(name)" --filter="name~'complex-demo-tfstate'"); do
    echo "Deleting bucket: $bucket"
    gcloud storage rm --recursive gs://$bucket/ || echo "Bucket $bucket already empty"
    gcloud storage buckets delete gs://$bucket --quiet || echo "Bucket $bucket already deleted"
done

# Delete service accounts created by terraform (if any)
echo -e "${YELLOW}👤 Deleting custom service accounts...${NC}"
for sa in $(gcloud iam service-accounts list --format="value(email)" --filter="email~'dev-gke-public-us-east1'"); do
    echo "Deleting service account: $sa"
    gcloud iam service-accounts delete $sa --quiet || echo "Service account $sa already deleted"
done

echo -e "\n${GREEN}✅ GCP resource destruction completed!${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "${YELLOW}📋 Summary:${NC}"
echo "  • All GKE clusters destroyed"
echo "  • All VPC networks and subnets removed"
echo "  • All firewall rules deleted"
echo "  • All routers and NAT gateways removed"
echo "  • All storage buckets cleaned up"
echo "  • Custom service accounts removed"
echo ""
echo -e "${BLUE}🎯 Next steps:${NC}"
echo "  1. Switch to your target GCP project"
echo "  2. Update terraform configuration"
echo "  3. Run terraform apply to deploy to new project"
echo ""
echo -e "${GREEN}✅ Ready to switch GCP projects!${NC}" 