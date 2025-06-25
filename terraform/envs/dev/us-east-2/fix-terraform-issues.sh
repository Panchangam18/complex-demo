#!/bin/bash

# Script to fix Terraform issues

echo "=== Terraform Resource Conflict Resolution ==="
echo
echo "The errors indicate that resources already exist in the cloud providers."
echo "We have several options to resolve this:"
echo
echo "Option 1: Delete existing resources and recreate"
echo "Option 2: Import existing resources into state"
echo "Option 3: Use data sources for existing resources"
echo

# For now, let's try to work with the existing resources by modifying the configuration

# Check current AWS resources
echo "Checking existing AWS EKS cluster..."
aws eks describe-cluster --name dev-eks-us-east-2 --region us-east-2 2>/dev/null || echo "EKS cluster not accessible"

# Check GCP resources
echo "Checking existing GCP resources..."
gcloud compute networks subnets list --filter="name:dev-*" --project=forge-demo-463617 2>/dev/null || echo "GCP resources not accessible"

echo
echo "Recommendations:"
echo "1. For the EKS cluster already exists error:"
echo "   - Either delete the existing cluster: aws eks delete-cluster --name dev-eks-us-east-2 --region us-east-2"
echo "   - Or import it into state (requires state access)"
echo
echo "2. For the RDS subnet group VPC mismatch:"
echo "   - This suggests the subnet group is trying to use subnets from a different VPC"
echo "   - Check if the VPC has been recreated and update the subnet group"
echo
echo "3. For GCP resources already exist:"
echo "   - These are all network resources that already exist"
echo "   - Either delete them or import them into state"
echo

# Create a destroy script for cleanup if needed
cat > destroy-existing-resources.sh << 'EOF'
#!/bin/bash

# WARNING: This will destroy existing resources!
read -p "Are you sure you want to destroy existing resources? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Delete AWS EKS cluster
echo "Deleting EKS cluster..."
aws eks delete-cluster --name dev-eks-us-east-2 --region us-east-2

# Delete GCP resources
echo "Deleting GCP subnets..."
for subnet in dev-public-us-east1-b dev-public-us-east1-c dev-public-us-east1-d \
              dev-private-us-east1-b dev-private-us-east1-c dev-private-us-east1-d \
              dev-internal-us-east1-b dev-internal-us-east1-c dev-internal-us-east1-d; do
    gcloud compute networks subnets delete $subnet --region=us-east1 --project=forge-demo-463617 --quiet
done

echo "Deleting GCP router..."
gcloud compute routers delete dev-router --region=us-east1 --project=forge-demo-463617 --quiet

echo "Deleting GCP firewall rules..."
for rule in dev-allow-internal dev-allow-ssh dev-allow-health-checks; do
    gcloud compute firewall-rules delete $rule --project=forge-demo-463617 --quiet
done

echo "Deleting GCP global address..."
gcloud compute addresses delete dev-private-ip-address --global --project=forge-demo-463617 --quiet

echo "Resources deleted. You can now run terraform apply again."
EOF

chmod +x destroy-existing-resources.sh

echo "Created destroy-existing-resources.sh script for cleanup if needed."