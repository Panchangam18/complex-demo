output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.main.id
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for GKE control plane"
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64 encoded)"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location (region or zone)"
  value       = google_container_cluster.main.location
}

output "cluster_region" {
  description = "GKE cluster region"
  value       = var.gcp_region
}

output "cluster_zones" {
  description = "List of zones in which the cluster resides"
  value       = google_container_cluster.main.node_locations
}

output "master_version" {
  description = "Current master version"
  value       = google_container_cluster.main.master_version
}

output "node_pools" {
  description = "Map of node pool attributes"
  value       = google_container_node_pool.main
}

output "service_account_gcs_access_email" {
  description = "Email of the GCS access service account"
  value       = local.workload_identity_enabled ? google_service_account.gcs_access[0].email : null
}

output "service_account_external_dns_email" {
  description = "Email of the External DNS service account"
  value       = local.workload_identity_enabled ? google_service_account.external_dns[0].email : null
}

output "service_account_cert_manager_email" {
  description = "Email of the Cert Manager service account"
  value       = local.workload_identity_enabled ? google_service_account.cert_manager[0].email : null
}

output "service_account_fluent_bit_email" {
  description = "Email of the Fluent Bit service account"
  value       = local.workload_identity_enabled ? google_service_account.fluent_bit[0].email : null
}

output "workload_identity_pool" {
  description = "Workload Identity Pool for the cluster"
  value       = var.enable_workload_identity ? "${var.gcp_project_id}.svc.id.goog" : null
}

output "cluster_network" {
  description = "Network the cluster is connected to"
  value       = google_container_cluster.main.network
}

output "cluster_subnetwork" {
  description = "Subnetwork the cluster is connected to"
  value       = google_container_cluster.main.subnetwork
}

output "cluster_ipv4_cidr" {
  description = "The IP range in CIDR notation used for the cluster"
  value       = google_container_cluster.main.cluster_ipv4_cidr
}

output "pods_ipv4_cidr_range" {
  description = "The IP range in CIDR notation used for pods"
  value       = google_container_cluster.main.ip_allocation_policy[0].cluster_ipv4_cidr_block
}

output "services_ipv4_cidr_range" {
  description = "The IP range in CIDR notation used for services"
  value       = google_container_cluster.main.ip_allocation_policy[0].services_ipv4_cidr_block
}

output "get_credentials_command" {
  description = "gcloud command to get credentials for the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --region ${google_container_cluster.main.location} --project ${var.gcp_project_id}"
}

# Temporarily disabled due to GKE hub membership being commented out
# output "hub_membership_id" {
#   description = "GKE Hub membership ID"
#   value       = var.enable_gke_hub ? google_gke_hub_membership.main[0].membership_id : null
# }