#!/bin/bash

# Script to import existing resources into Terraform state

echo "Starting resource import process..."

# Import AWS EKS Cluster
echo "Importing EKS cluster..."
terraform import module.aws_eks.aws_eks_cluster.main dev-eks-us-east-2

# Import GCP resources
echo "Importing GCP VPC subnets..."
terraform import module.gcp_vpc.google_compute_subnetwork.public[0] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-public-us-east1-b
terraform import module.gcp_vpc.google_compute_subnetwork.public[1] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-public-us-east1-c
terraform import module.gcp_vpc.google_compute_subnetwork.public[2] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-public-us-east1-d

terraform import module.gcp_vpc.google_compute_subnetwork.private[0] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-private-us-east1-b
terraform import module.gcp_vpc.google_compute_subnetwork.private[1] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-private-us-east1-c
terraform import module.gcp_vpc.google_compute_subnetwork.private[2] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-private-us-east1-d

terraform import module.gcp_vpc.google_compute_subnetwork.internal[0] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-internal-us-east1-b
terraform import module.gcp_vpc.google_compute_subnetwork.internal[1] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-internal-us-east1-c
terraform import module.gcp_vpc.google_compute_subnetwork.internal[2] projects/forge-demo-463617/regions/us-east1/subnetworks/dev-internal-us-east1-d

echo "Importing GCP Router..."
terraform import module.gcp_vpc.google_compute_router.router[0] projects/forge-demo-463617/regions/us-east1/routers/dev-router

echo "Importing GCP Firewalls..."
terraform import module.gcp_vpc.google_compute_firewall.internal projects/forge-demo-463617/global/firewalls/dev-allow-internal
terraform import module.gcp_vpc.google_compute_firewall.ssh projects/forge-demo-463617/global/firewalls/dev-allow-ssh
terraform import module.gcp_vpc.google_compute_firewall.health_checks projects/forge-demo-463617/global/firewalls/dev-allow-health-checks

echo "Importing GCP Global Address..."
terraform import module.gcp_vpc.google_compute_global_address.private_ip_address[0] projects/forge-demo-463617/global/addresses/dev-private-ip-address

echo "Import process completed!"
echo "Note: You may need to handle the RDS subnet group separately as it has a VPC mismatch issue."