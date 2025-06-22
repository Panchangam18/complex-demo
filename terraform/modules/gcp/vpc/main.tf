# GCP VPC Module
# Creates a VPC with public, private, and internal subnets

locals {
  # GCP uses different terminology but similar concepts
  # We'll create subnets in multiple zones within the region
  # Limit to 3 zones to ensure we have enough IP space
  max_zones = min(3, length(data.google_compute_zones.available.names))
  zones = slice(data.google_compute_zones.available.names, 0, local.max_zones)
  
  # Calculate subnet ranges
  # Using /20 for each subnet type (4096 IPs each)
  public_subnet_cidrs   = [for i in range(length(local.zones)) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs  = [for i in range(length(local.zones)) : cidrsubnet(var.vpc_cidr, 4, i + length(local.zones))]
  internal_subnet_cidrs = [for i in range(length(local.zones)) : cidrsubnet(var.vpc_cidr, 4, i + 2 * length(local.zones))]
}

data "google_compute_zones" "available" {
  region = var.gcp_region
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC for ${var.environment} environment"
  
  # Delete default routes to have more control
  delete_default_routes_on_create = false
}

# Public Subnets (for resources that need external IPs)
resource "google_compute_subnetwork" "public" {
  count = length(local.zones)
  
  name          = "${var.environment}-public-${local.zones[count.index]}"
  ip_cidr_range = local.public_subnet_cidrs[count.index]
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  
  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private Subnets (for resources behind Cloud NAT)
resource "google_compute_subnetwork" "private" {
  count = length(local.zones)
  
  name          = "${var.environment}-private-${local.zones[count.index]}"
  ip_cidr_range = local.private_subnet_cidrs[count.index]
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  
  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Internal Subnets (for databases and internal services)
resource "google_compute_subnetwork" "internal" {
  count = length(local.zones)
  
  name          = "${var.environment}-internal-${local.zones[count.index]}"
  ip_cidr_range = local.internal_subnet_cidrs[count.index]
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  
  private_ip_google_access = true
  
  # Secondary ranges for GKE pods and services
  # Each zone gets its own non-overlapping secondary ranges
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(var.vpc_cidr, 6, 48 + count.index * 4)  # /22 for pods
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(var.vpc_cidr, 6, 50 + count.index * 4) # /22 for services
  }
  
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  count = var.enable_nat_gateway ? 1 : 0
  
  name    = "${var.environment}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
  
  bgp {
    asn = 64514
  }
}

# Cloud NAT (equivalent to AWS NAT Gateway)
resource "google_compute_router_nat" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
  
  name                               = "${var.environment}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  
  # Apply NAT to private subnets
  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.private
    content {
      name                    = subnetwork.value.id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall Rules
# Allow internal communication
resource "google_compute_firewall" "internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "icmp"
  }
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  source_ranges = [var.vpc_cidr]
  priority      = 1000
}

# Allow SSH from specific IPs (customize as needed)
resource "google_compute_firewall" "ssh" {
  name    = "${var.environment}-allow-ssh"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = var.ssh_source_ranges
  target_tags   = ["allow-ssh"]
  priority      = 1000
}

# Allow health checks from Google LBs
resource "google_compute_firewall" "health_checks" {
  name    = "${var.environment}-allow-health-checks"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
  }
  
  source_ranges = [
    "35.191.0.0/16",   # Google health check ranges
    "130.211.0.0/22"
  ]
  
  target_tags = ["allow-health-checks"]
  priority    = 1000
}

# VPC Flow Logs are configured at the subnet level in GCP (see subnet resources above)

# Private Google Access for services
resource "google_compute_global_address" "private_ip_address" {
  count = var.enable_private_google_access ? 1 : 0
  
  name          = "${var.environment}-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count = var.enable_private_google_access ? 1 : 0
  
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[0].name]
}