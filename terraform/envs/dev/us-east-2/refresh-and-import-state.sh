#!/bin/bash

# Script to refresh state and handle existing resources

echo "=== Terraform State Refresh and Import Script ==="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to handle errors
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# Function to show success
show_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to show warning
show_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

echo "Attempting to refresh Terraform state..."

# Try to refresh state
terraform refresh 2>/dev/null
if [ $? -ne 0 ]; then
    show_warning "State refresh failed. This might be due to S3 permissions or missing state."
    echo
    echo "Let's try a different approach..."
    echo
    
    # Create a temporary backend configuration to use local state
    cat > backend-local.tf << 'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
    
    echo "Created temporary local backend configuration."
    echo "Initializing with local backend..."
    
    # Remove the remote backend temporarily
    mv backend.tf backend.tf.backup 2>/dev/null
    
    # Initialize with local backend
    terraform init -reconfigure
    
    if [ $? -eq 0 ]; then
        show_success "Initialized with local backend"
        
        echo
        echo "Now let's import the existing resources..."
        echo
        
        # Import AWS EKS Cluster
        echo "Importing AWS EKS cluster..."
        terraform import module.aws_eks.aws_eks_cluster.main dev-eks-us-east-2 2>/dev/null
        if [ $? -eq 0 ]; then
            show_success "Imported EKS cluster"
        else
            show_warning "Failed to import EKS cluster - it might already be in state"
        fi
        
        # Import GCP VPC (if it exists)
        echo "Checking if GCP VPC needs to be imported..."
        terraform state show module.gcp_vpc.google_compute_network.vpc 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Importing GCP VPC..."
            terraform import module.gcp_vpc.google_compute_network.vpc projects/forge-demo-463617/global/networks/dev-vpc 2>/dev/null
        fi
        
        # Import GCP subnets
        echo "Importing GCP subnets..."
        for i in 0 1 2; do
            for type in public private internal; do
                case $i in
                    0) zone="b" ;;
                    1) zone="c" ;;
                    2) zone="d" ;;
                esac
                
                resource="module.gcp_vpc.google_compute_subnetwork.${type}[$i]"
                id="projects/forge-demo-463617/regions/us-east1/subnetworks/dev-${type}-us-east1-${zone}"
                
                terraform state show "$resource" 2>/dev/null
                if [ $? -ne 0 ]; then
                    terraform import "$resource" "$id" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        show_success "Imported $type subnet in zone $zone"
                    fi
                fi
            done
        done
        
        # Import other GCP resources
        echo "Importing other GCP resources..."
        
        # Router
        terraform import module.gcp_vpc.google_compute_router.router[0] projects/forge-demo-463617/regions/us-east1/routers/dev-router 2>/dev/null
        
        # Firewall rules
        terraform import module.gcp_vpc.google_compute_firewall.internal projects/forge-demo-463617/global/firewalls/dev-allow-internal 2>/dev/null
        terraform import module.gcp_vpc.google_compute_firewall.ssh projects/forge-demo-463617/global/firewalls/dev-allow-ssh 2>/dev/null
        terraform import module.gcp_vpc.google_compute_firewall.health_checks projects/forge-demo-463617/global/firewalls/dev-allow-health-checks 2>/dev/null
        
        # Global address
        terraform import module.gcp_vpc.google_compute_global_address.private_ip_address[0] projects/forge-demo-463617/global/addresses/dev-private-ip-address 2>/dev/null
        
        echo
        echo "Import process completed!"
        echo
        
        # Now try to plan
        echo "Running terraform plan to see remaining issues..."
        terraform plan -out=tfplan
        
    else
        handle_error "Failed to initialize with local backend"
    fi
else
    show_success "State refresh successful"
fi

echo
echo "Next steps:"
echo "1. Review the terraform plan output above"
echo "2. If there are still issues with the RDS subnet group:"
echo "   - The subnet group might be associated with a different VPC"
echo "   - You may need to delete it manually: aws rds delete-db-subnet-group --db-subnet-group-name dev-postgres-us-east-2-subnet-group --region us-east-2"
echo "3. Once all issues are resolved, run: terraform apply"
echo
echo "To restore remote backend later:"
echo "   1. mv backend.tf.backup backend.tf"
echo "   2. rm backend-local.tf"
echo "   3. terraform init -migrate-state"