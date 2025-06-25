variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.cluster_name))
    error_message = "Cluster name must start with a lowercase letter and can only contain lowercase letters, numbers, and hyphens."
  }
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the cluster"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet for the cluster"
  type        = string
}

variable "pods_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary range for services"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.29"
}

variable "release_channel" {
  description = "Release channel for GKE cluster"
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["UNSPECIFIED", "RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "Release channel must be UNSPECIFIED, RAPID, REGULAR, or STABLE."
  }
}

variable "node_pools" {
  description = "Map of node pool configurations"
  type = map(object({
    machine_type       = string
    min_count         = number
    max_count         = number
    initial_node_count = number
    disk_size_gb      = number
    disk_type         = string
    preemptible       = bool
    spot              = bool
    labels            = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    oauth_scopes = list(string)
  }))
  default = {
    general = {
      machine_type       = "e2-standard-4"
      min_count         = 1
      max_count         = 4
      initial_node_count = 2
      disk_size_gb      = 100
      disk_type         = "pd-standard"
      preemptible       = false
      spot              = false
      labels            = {}
      taints            = []
      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }
}

variable "enable_private_cluster" {
  description = "Enable private cluster (nodes have no public IP)"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint (master has no public IP)"
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for master network"
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "List of networks authorized to access the master endpoint"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for the cluster"
  type        = bool
  default     = true
}

variable "enable_autopilot" {
  description = "Enable Autopilot mode for the cluster"
  type        = bool
  default     = false
}

variable "enable_network_policy" {
  description = "Enable network policy addon"
  type        = bool
  default     = true
}

variable "enable_dataplane_v2" {
  description = "Enable Dataplane V2 (eBPF dataplane)"
  type        = bool
  default     = true
}

variable "enable_dns_cache" {
  description = "Enable NodeLocal DNSCache addon"
  type        = bool
  default     = true
}

variable "enable_gke_hub" {
  description = "Enable GKE Hub registration"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization"
  type        = bool
  default     = false
}


variable "logging_service" {
  description = "Logging service to use"
  type        = string
  default     = "logging.googleapis.com/kubernetes"
}

variable "monitoring_service" {
  description = "Monitoring service to use"
  type        = string
  default     = "monitoring.googleapis.com/kubernetes"
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaling"
  type        = bool
  default     = true
}

variable "enable_horizontal_pod_autoscaling" {
  description = "Enable Horizontal Pod Autoscaling"
  type        = bool
  default     = true
}

variable "enable_http_load_balancing" {
  description = "Enable HTTP Load Balancing addon"
  type        = bool
  default     = true
}

variable "enable_gce_persistent_disk_csi_driver" {
  description = "Enable GCE Persistent Disk CSI Driver"
  type        = bool
  default     = true
}

variable "enable_filestore_csi_driver" {
  description = "Enable Filestore CSI Driver"
  type        = bool
  default     = false
}

variable "maintenance_start_time" {
  description = "Start time for maintenance window (UTC)"
  type        = string
  default     = "03:00"
}

variable "maintenance_end_time" {
  description = "End time for maintenance window (UTC)"
  type        = string
  default     = "05:00"
}

variable "maintenance_recurrence" {
  description = "Maintenance window recurrence in RFC5545 format"
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SU"
}

variable "common_tags" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "gcp_labels" {
  description = "GCP-specific labels (must be lowercase) to apply to GCP resources"
  type        = map(string)
  default     = {}
}

variable "database_encryption" {
  description = "Database encryption configuration"
  type = object({
    state    = string
    key_name = string
  })
  default = {
    state    = "DECRYPTED"
    key_name = ""
  }
}