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
