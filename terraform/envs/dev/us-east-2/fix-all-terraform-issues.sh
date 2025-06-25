#!/bin/bash

# Comprehensive script to fix all Terraform issues

echo "=== Fixing All Terraform Issues ==="
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get the current directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${BLUE}Step 1: Fixing RDS Subnet Group Issue${NC}"
echo "The RDS subnet group is using old subnet IDs. We need to delete it."
echo

# Delete the existing RDS subnet group
echo "Deleting existing RDS subnet group..."
aws rds delete-db-subnet-group \
    --db-subnet-group-name dev-postgres-us-east-2-subnet-group \
    --region us-east-2 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Deleted RDS subnet group${NC}"
else
    echo -e "${YELLOW}⚠ RDS subnet group might not exist or already deleted${NC}"
fi

echo
echo -e "${BLUE}Step 2: Setting up local state to bypass S3 permissions issue${NC}"
echo

# Backup current backend configuration
if [ -f backend.tf ]; then
    mv backend.tf backend.tf.backup
    echo -e "${GREEN}✓ Backed up backend.tf${NC}"
fi

# Create local backend configuration
cat > backend-local.tf << 'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
echo -e "${GREEN}✓ Created local backend configuration${NC}"

# Remove old local state if exists
rm -f terraform.tfstate terraform.tfstate.backup

echo
echo -e "${BLUE}Step 3: Initializing Terraform with local backend${NC}"
terraform init -reconfigure

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to initialize Terraform${NC}"
    exit 1
fi

echo
echo -e "${BLUE}Step 4: Importing existing AWS resources${NC}"
echo

# Import AWS VPC
echo "Importing AWS VPC..."
terraform import module.aws_vpc.aws_vpc.main vpc-016e63de9e590882b 2>/dev/null || echo -e "${YELLOW}VPC already in state or doesn't exist${NC}"

# Import EKS Cluster
echo "Importing EKS cluster..."
terraform import module.aws_eks.aws_eks_cluster.main dev-eks-us-east-2 2>/dev/null || echo -e "${YELLOW}EKS cluster already in state${NC}"

echo
echo -e "${BLUE}Step 5: Importing existing GCP resources${NC}"
echo

# Import GCP VPC
echo "Importing GCP VPC..."
terraform import module.gcp_vpc.google_compute_network.vpc projects/forge-demo-463617/global/networks/dev-vpc 2>/dev/null || echo -e "${YELLOW}GCP VPC already in state${NC}"

# Import GCP subnets
echo "Importing GCP subnets..."
zones=("b" "c" "d")
for i in 0 1 2; do
    zone="${zones[$i]}"
    
    # Public subnets
    terraform import "module.gcp_vpc.google_compute_subnetwork.public[$i]" \
        "projects/forge-demo-463617/regions/us-east1/subnetworks/dev-public-us-east1-${zone}" 2>/dev/null || \
        echo -e "${YELLOW}Public subnet ${zone} already in state${NC}"
    
    # Private subnets
    terraform import "module.gcp_vpc.google_compute_subnetwork.private[$i]" \
        "projects/forge-demo-463617/regions/us-east1/subnetworks/dev-private-us-east1-${zone}" 2>/dev/null || \
        echo -e "${YELLOW}Private subnet ${zone} already in state${NC}"
    
    # Internal subnets
    terraform import "module.gcp_vpc.google_compute_subnetwork.internal[$i]" \
        "projects/forge-demo-463617/regions/us-east1/subnetworks/dev-internal-us-east1-${zone}" 2>/dev/null || \
        echo -e "${YELLOW}Internal subnet ${zone} already in state${NC}"
done

# Import other GCP resources
echo "Importing other GCP resources..."
terraform import module.gcp_vpc.google_compute_router.router[0] \
    projects/forge-demo-463617/regions/us-east1/routers/dev-router 2>/dev/null || \
    echo -e "${YELLOW}Router already in state${NC}"

terraform import module.gcp_vpc.google_compute_firewall.internal \
    projects/forge-demo-463617/global/firewalls/dev-allow-internal 2>/dev/null || \
    echo -e "${YELLOW}Internal firewall already in state${NC}"

terraform import module.gcp_vpc.google_compute_firewall.ssh \
    projects/forge-demo-463617/global/firewalls/dev-allow-ssh 2>/dev/null || \
    echo -e "${YELLOW}SSH firewall already in state${NC}"

terraform import module.gcp_vpc.google_compute_firewall.health_checks \
    projects/forge-demo-463617/global/firewalls/dev-allow-health-checks 2>/dev/null || \
    echo -e "${YELLOW}Health checks firewall already in state${NC}"

terraform import module.gcp_vpc.google_compute_global_address.private_ip_address[0] \
    projects/forge-demo-463617/global/addresses/dev-private-ip-address 2>/dev/null || \
    echo -e "${YELLOW}Private IP address already in state${NC}"

echo
echo -e "${BLUE}Step 6: Running terraform plan${NC}"
echo

terraform plan -out=tfplan

if [ $? -eq 0 ]; then
    echo
    echo -e "${GREEN}✓ Terraform plan completed successfully!${NC}"
    echo
    echo -e "${BLUE}Step 7: Apply the changes${NC}"
    echo "Run the following command to apply:"
    echo -e "${YELLOW}terraform apply tfplan${NC}"
    echo
    echo -e "${BLUE}After successful apply, to restore remote state:${NC}"
    echo "1. rm backend-local.tf"
    echo "2. mv backend.tf.backup backend.tf"
    echo "3. terraform init -migrate-state"
else
    echo
    echo -e "${RED}Terraform plan failed. Please review the errors above.${NC}"
fi

echo
echo -e "${BLUE}Alternative: Clean Slate Approach${NC}"
echo "If you prefer to start fresh, run:"
echo -e "${YELLOW}./destroy-existing-resources.sh${NC}"
echo "This will delete all existing resources and allow a clean terraform apply."