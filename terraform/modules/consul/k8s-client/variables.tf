variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Kubernetes cluster CA certificate"
  type        = string
  default     = ""
}

variable "region" {
  description = "Cloud region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider (aws, gcp, azure)"
  type        = string
}

variable "datacenter_name" {
  description = "Consul datacenter name for this K8s cluster"
  type        = string
}

variable "primary_datacenter" {
  description = "Name of the primary Consul datacenter (EC2 cluster)"
  type        = string
}

variable "consul_helm_version" {
  description = "Version of Consul Helm chart"
  type        = string
  default     = "1.7.2"
}

variable "consul_image_tag" {
  description = "Consul Docker image tag"
  type        = string
  default     = "1.21.2"
}

variable "consul_k8s_image_tag" {
  description = "Consul K8s Docker image tag"
  type        = string
  default     = "1.7.2"
}

variable "gossip_key" {
  description = "Consul gossip encryption key"
  type        = string
  sensitive   = true
}

variable "wan_federation_secret" {
  description = "WAN federation secret for connecting to primary datacenter"
  type        = string
  sensitive   = true
}

variable "primary_consul_servers" {
  description = "List of primary Consul server IP addresses"
  type        = list(string)
}

variable "mesh_gateway_endpoints" {
  description = "List of mesh gateway endpoints for cross-cloud connectivity (for GKE, use public ALB endpoints)"
  type        = list(string)
  default     = []
}

variable "enable_connect" {
  description = "Enable Consul Connect service mesh"
  type        = bool
  default     = true
}

variable "enable_connect_inject" {
  description = "Enable automatic Connect sidecar injection"
  type        = bool
  default     = true
}

variable "enable_ui" {
  description = "Enable Consul UI"
  type        = bool
  default     = false
}

variable "ui_service_type" {
  description = "Service type for Consul UI (ClusterIP, LoadBalancer, NodePort)"
  type        = string
  default     = "ClusterIP"
}

variable "enable_prometheus_metrics" {
  description = "Enable Prometheus metrics"
  type        = bool
  default     = true
}

variable "enable_sync_catalog" {
  description = "Enable service catalog sync between Consul and Kubernetes"
  type        = bool
  default     = true
}

variable "consul_master_token" {
  description = "Consul master token for ACL authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_acls" {
  description = "Enable Consul ACLs"
  type        = bool
  default     = false
}

variable "aws_profile" {
  description = "AWS profile for authentication (for EKS clusters)"
  type        = string
  default     = "default"
}

variable "mesh_gateway_replicas" {
  description = "Number of mesh gateway replicas for WAN communication"
  type        = number
  default     = 1
}

variable "client_replicas" {
  description = "Number of Consul client replicas"
  type        = number
  default     = 3
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
} 