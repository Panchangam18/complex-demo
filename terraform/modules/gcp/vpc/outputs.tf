output "vpc_id" {
  description = "ID of the VPC"
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "Name of the VPC"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "Self link of the VPC"
  value       = google_compute_network.vpc.self_link
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = google_compute_subnetwork.public[*].id
}

output "public_subnet_names" {
  description = "List of public subnet names"
  value       = google_compute_subnetwork.public[*].name
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = google_compute_subnetwork.private[*].id
}

output "private_subnet_names" {
  description = "List of private subnet names"
  value       = google_compute_subnetwork.private[*].name
}

output "internal_subnet_ids" {
  description = "List of internal subnet IDs"
  value       = google_compute_subnetwork.internal[*].id
}

output "internal_subnet_names" {
  description = "List of internal subnet names"
  value       = google_compute_subnetwork.internal[*].name
}

output "zones" {
  description = "List of zones used"
  value       = local.zones
}

output "router_id" {
  description = "ID of the Cloud Router"
  value       = try(google_compute_router.router[0].id, null)
}

output "nat_id" {
  description = "ID of the Cloud NAT"
  value       = try(google_compute_router_nat.nat[0].id, null)
}

output "gke_pod_ranges" {
  description = "Secondary IP ranges for GKE pods"
  value       = { for subnet in google_compute_subnetwork.internal : subnet.name => subnet.secondary_ip_range[0].ip_cidr_range }
}

output "gke_service_ranges" {
  description = "Secondary IP ranges for GKE services"
  value       = { for subnet in google_compute_subnetwork.internal : subnet.name => subnet.secondary_ip_range[1].ip_cidr_range }
}