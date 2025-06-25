# Enable required APIs
resource "google_project_service" "container" {
  project = var.gcp_project_id
  service = "container.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  project = var.gcp_project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

# GKE Cluster
resource "google_container_cluster" "main" {
  provider = google

  name     = var.cluster_name
  location = var.gcp_region
  project  = var.gcp_project_id

  # Autopilot or Standard mode
  enable_autopilot = var.enable_autopilot

  # For Standard clusters, we need to create a default node pool
  # But we'll immediately delete it and use separately managed node pools
  dynamic "node_pool" {
    for_each = var.enable_autopilot ? [] : [1]
    content {
      name       = "default-pool"
      node_count = 1
    }
  }

  # Remove default node pool after cluster creation for Standard clusters
  # Only set these if NOT using autopilot
  remove_default_node_pool = var.enable_autopilot ? null : true
  initial_node_count       = var.enable_autopilot ? null : 1

  # Kubernetes version
  min_master_version = var.kubernetes_version

  # Release channel
  release_channel {
    channel = var.release_channel
  }

  # Network configuration
  network    = var.network_name
  subnetwork = var.subnet_name

  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_cluster
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block = var.master_ipv4_cidr_block
  }

  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Workload Identity
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.gcp_project_id}.svc.id.goog"
    }
  }

  # Network policy - only for standard clusters
  dynamic "network_policy" {
    for_each = var.enable_autopilot ? [] : [1]
    content {
      enabled  = var.enable_network_policy
      provider = var.enable_network_policy ? "CALICO" : "PROVIDER_UNSPECIFIED"
    }
  }

  # Dataplane V2
  datapath_provider = var.enable_dataplane_v2 ? "ADVANCED_DATAPATH" : null

  # DNS cache
  dynamic "dns_config" {
    for_each = var.enable_dns_cache ? [1] : []
    content {
      cluster_dns        = "CLOUD_DNS"
      cluster_dns_scope  = "CLUSTER_SCOPE"
      cluster_dns_domain = ""
    }
  }

  # Binary Authorization
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  # Database encryption
  database_encryption {
    state    = var.database_encryption.state
    key_name = var.database_encryption.key_name
  }

  # Logging and monitoring
  logging_service    = var.logging_service
  monitoring_service = var.monitoring_service

  # Cluster addons - only for standard clusters
  dynamic "addons_config" {
    for_each = var.enable_autopilot ? [] : [1]
    content {
      horizontal_pod_autoscaling {
        disabled = !var.enable_horizontal_pod_autoscaling
      }

      http_load_balancing {
        disabled = !var.enable_http_load_balancing
      }

      network_policy_config {
        disabled = !var.enable_network_policy
      }

      gce_persistent_disk_csi_driver_config {
        enabled = var.enable_gce_persistent_disk_csi_driver
      }

      gcp_filestore_csi_driver_config {
        enabled = var.enable_filestore_csi_driver
      }

      dns_cache_config {
        enabled = var.enable_dns_cache
      }
    }
  }

  # Vertical Pod Autoscaling - only for standard clusters
  dynamic "vertical_pod_autoscaling" {
    for_each = var.enable_autopilot ? [] : [1]
    content {
      enabled = var.enable_vertical_pod_autoscaling
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # Resource labels
  resource_labels = merge(
    var.common_tags,
    {
      environment = var.environment
      cluster     = var.cluster_name
    }
  )

  depends_on = [
    google_project_service.container,
    google_project_service.compute,
  ]

  lifecycle {
    ignore_changes = [node_pool, initial_node_count]
  }
}

# Node pools for Standard clusters
resource "google_container_node_pool" "main" {
  for_each = var.enable_autopilot ? {} : var.node_pools

  name     = each.key
  location = var.gcp_region
  cluster  = google_container_cluster.main.name
  project  = var.gcp_project_id

  initial_node_count = each.value.initial_node_count

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type

    preemptible = each.value.preemptible
    spot        = each.value.spot

    # OAuth scopes
    oauth_scopes = each.value.oauth_scopes

    # Labels
    labels = merge(
      each.value.labels,
      {
        environment = var.environment
        node_pool   = each.key
      }
    )

    # Taints
    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # Workload Identity
    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }

    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Enable GKE Hub registration if requested
resource "google_gke_hub_membership" "main" {
  count = var.enable_gke_hub ? 1 : 0

  membership_id = var.cluster_name
  project       = var.gcp_project_id

  endpoint {
    gke_cluster {
      resource_link = google_container_cluster.main.id
    }
  }

  depends_on = [google_container_cluster.main]
}