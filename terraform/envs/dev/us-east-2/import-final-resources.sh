#!/bin/bash

echo "=== Importing Final Resources ==="

# Import CloudWatch Log Group
echo "Importing CloudWatch Log Group..."
terragrunt import 'module.aws_vpc.aws_cloudwatch_log_group.flow_logs[0]' /aws/vpc/dev

# Import GKE cluster
echo "Importing GKE cluster..."
terragrunt import module.gcp_gke.google_container_cluster.main projects/forge-demo-463617/locations/us-east1/clusters/dev-gke-us-east1

# Import GCP Router NAT
echo "Importing GCP Router NAT..."
terragrunt import 'module.gcp_vpc.google_compute_router_nat.nat[0]' projects/forge-demo-463617/regions/us-east1/routers/dev-router/dev-nat

echo "Done!"