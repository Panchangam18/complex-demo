#!/bin/bash

# Script to fix Terraform issues with Terragrunt

echo "=== Fixing Terraform Issues with Terragrunt ==="
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd /Users/madhavan/GitHub/complex-demo/terraform

echo -e "${BLUE}Step 1: Temporarily disabling remote state in Terragrunt${NC}"
# Create a backup of terragrunt.hcl
cp terragrunt.hcl terragrunt.hcl.backup

# Comment out the remote_state block
sed -i.bak '/^remote_state {/,/^}$/s/^/#/' terragrunt.hcl

echo -e "${GREEN}✓ Disabled remote state configuration${NC}"

echo
echo -e "${BLUE}Step 2: Deleting RDS subnet group${NC}"
aws rds delete-db-subnet-group \
    --db-subnet-group-name dev-postgres-us-east-2-subnet-group \
    --region us-east-2 2>/dev/null || echo -e "${YELLOW}⚠ RDS subnet group might not exist${NC}"

echo
echo -e "${BLUE}Step 3: Running terragrunt init${NC}"
cd envs/dev/us-east-2
terragrunt init -reconfigure

echo
echo -e "${BLUE}Step 4: Importing existing resources${NC}"

# Import EKS
echo "Importing EKS cluster..."
terragrunt import module.aws_eks.aws_eks_cluster.main dev-eks-us-east-2 2>/dev/null || echo -e "${YELLOW}⚠ EKS already in state${NC}"

# Import GCP resources
echo "Importing GCP VPC..."
terragrunt import module.gcp_vpc.google_compute_network.vpc projects/forge-demo-463617/global/networks/dev-vpc 2>/dev/null || echo -e "${YELLOW}⚠ VPC already in state${NC}"

# Import GCP subnets
zones=("b" "c" "d")
for i in 0 1 2; do
    zone="${zones[$i]}"
    
    for type in public private internal; do
        terragrunt import "module.gcp_vpc.google_compute_subnetwork.${type}[$i]" \
            "projects/forge-demo-463617/regions/us-east1/subnetworks/dev-${type}-us-east1-${zone}" 2>/dev/null || \
            echo -e "${YELLOW}⚠ ${type} subnet ${zone} already in state${NC}"
    done
done

# Import other GCP resources
terragrunt import module.gcp_vpc.google_compute_router.router[0] \
    projects/forge-demo-463617/regions/us-east1/routers/dev-router 2>/dev/null || \
    echo -e "${YELLOW}⚠ Router already in state${NC}"

terragrunt import module.gcp_vpc.google_compute_firewall.internal \
    projects/forge-demo-463617/global/firewalls/dev-allow-internal 2>/dev/null || \
    echo -e "${YELLOW}⚠ Internal firewall already in state${NC}"

terragrunt import module.gcp_vpc.google_compute_firewall.ssh \
    projects/forge-demo-463617/global/firewalls/dev-allow-ssh 2>/dev/null || \
    echo -e "${YELLOW}⚠ SSH firewall already in state${NC}"

terragrunt import module.gcp_vpc.google_compute_firewall.health_checks \
    projects/forge-demo-463617/global/firewalls/dev-allow-health-checks 2>/dev/null || \
    echo -e "${YELLOW}⚠ Health checks firewall already in state${NC}"

terragrunt import module.gcp_vpc.google_compute_global_address.private_ip_address[0] \
    projects/forge-demo-463617/global/addresses/dev-private-ip-address 2>/dev/null || \
    echo -e "${YELLOW}⚠ Private IP address already in state${NC}"

echo
echo -e "${BLUE}Step 5: Running terragrunt plan${NC}"
terragrunt plan -out=tfplan

if [ $? -eq 0 ]; then
    echo
    echo -e "${GREEN}✓ Plan completed successfully!${NC}"
    echo
    echo "To apply the changes, run:"
    echo -e "${YELLOW}cd /Users/madhavan/GitHub/complex-demo/terraform/envs/dev/us-east-2 && terragrunt apply tfplan${NC}"
    echo
    echo "After successful apply, restore remote state:"
    echo "1. cd /Users/madhavan/GitHub/complex-demo/terraform"
    echo "2. mv terragrunt.hcl.backup terragrunt.hcl"
    echo "3. cd envs/dev/us-east-2"
    echo "4. terragrunt init -migrate-state"
else
    echo -e "${RED}Plan failed. Check the errors above.${NC}"
fi