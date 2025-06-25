#!/bin/bash

# Import GCP resources with terragrunt

echo "Importing GCP resources..."

# Import GCP VPC subnets
for i in 0 1 2; do
    case $i in
        0) zone="b" ;;
        1) zone="c" ;;
        2) zone="d" ;;
    esac
    
    # Import subnets
    terragrunt import "module.gcp_vpc.google_compute_subnetwork.public[$i]" "projects/forge-demo-463617/regions/us-east1/subnetworks/dev-public-us-east1-${zone}"
    terragrunt import "module.gcp_vpc.google_compute_subnetwork.private[$i]" "projects/forge-demo-463617/regions/us-east1/subnetworks/dev-private-us-east1-${zone}"
    terragrunt import "module.gcp_vpc.google_compute_subnetwork.internal[$i]" "projects/forge-demo-463617/regions/us-east1/subnetworks/dev-internal-us-east1-${zone}"
done

# Import other GCP resources
terragrunt import module.gcp_vpc.google_compute_router.router[0] projects/forge-demo-463617/regions/us-east1/routers/dev-router
terragrunt import module.gcp_vpc.google_compute_firewall.internal projects/forge-demo-463617/global/firewalls/dev-allow-internal
terragrunt import module.gcp_vpc.google_compute_firewall.ssh projects/forge-demo-463617/global/firewalls/dev-allow-ssh
terragrunt import module.gcp_vpc.google_compute_firewall.health_checks projects/forge-demo-463617/global/firewalls/dev-allow-health-checks
terragrunt import module.gcp_vpc.google_compute_global_address.private_ip_address[0] projects/forge-demo-463617/global/addresses/dev-private-ip-address

echo "GCP import completed!"