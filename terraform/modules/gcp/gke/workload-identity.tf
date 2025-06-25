# Workload Identity configuration for common GCP services

locals {
  workload_identity_enabled = var.enable_workload_identity && !var.enable_autopilot
}

# Service account for GCS access (Thanos, backups, etc.)
resource "google_service_account" "gcs_access" {
  count = local.workload_identity_enabled ? 1 : 0

  account_id   = "${var.cluster_name}-gcs-access"
  display_name = "GCS access for ${var.cluster_name}"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "gcs_access" {
  count = local.workload_identity_enabled ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.gcs_access[0].email}"
}

resource "google_service_account_iam_member" "gcs_access_workload_identity" {
  count = local.workload_identity_enabled ? 1 : 0

  service_account_id = google_service_account.gcs_access[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[kube-system/gcs-access]"
}

# Service account for External DNS
resource "google_service_account" "external_dns" {
  count = local.workload_identity_enabled ? 1 : 0

  account_id   = "${var.cluster_name}-external-dns"
  display_name = "External DNS for ${var.cluster_name}"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "external_dns" {
  count = local.workload_identity_enabled ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns[0].email}"
}

resource "google_service_account_iam_member" "external_dns_workload_identity" {
  count = local.workload_identity_enabled ? 1 : 0

  service_account_id = google_service_account.external_dns[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[kube-system/external-dns]"
}

# Service account for Cert Manager
resource "google_service_account" "cert_manager" {
  count = local.workload_identity_enabled ? 1 : 0

  account_id   = "${var.cluster_name}-cert-manager"
  display_name = "Cert Manager for ${var.cluster_name}"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "cert_manager" {
  count = local.workload_identity_enabled ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager[0].email}"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  count = local.workload_identity_enabled ? 1 : 0

  service_account_id = google_service_account.cert_manager[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[cert-manager/cert-manager]"
}

# Service account for Fluent Bit
resource "google_service_account" "fluent_bit" {
  count = local.workload_identity_enabled ? 1 : 0

  account_id   = "${var.cluster_name}-fluent-bit"
  display_name = "Fluent Bit for ${var.cluster_name}"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "fluent_bit_logging" {
  count = local.workload_identity_enabled ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.fluent_bit[0].email}"
}

resource "google_project_iam_member" "fluent_bit_monitoring" {
  count = local.workload_identity_enabled ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.fluent_bit[0].email}"
}

resource "google_service_account_iam_member" "fluent_bit_workload_identity" {
  count = local.workload_identity_enabled ? 1 : 0

  service_account_id = google_service_account.fluent_bit[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[kube-system/fluent-bit]"
}

# Service account for GKE Metadata Server (required for Workload Identity)
resource "google_project_iam_member" "gke_metadata_server" {
  count = local.workload_identity_enabled ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${var.gcp_project_id}.svc.id.goog[kube-system/metadata-server]"
}