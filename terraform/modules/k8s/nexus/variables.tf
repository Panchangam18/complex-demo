variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "storage_provisioner" {
  description = "Kubernetes storage provisioner"
  type        = string
  default     = "ebs.csi.aws.com"
}

variable "storage_size" {
  description = "Size of persistent volume for Nexus data"
  type        = string
  default     = "100Gi"
}

variable "nexus_chart_version" {
  description = "Version of Nexus Helm chart (secure stevehipwell version)"
  type        = string
  default     = "5.11.0"
}

variable "service_type" {
  description = "Kubernetes service type for Nexus"
  type        = string
  default     = "LoadBalancer"
}

variable "ingress_enabled" {
  description = "Enable ingress for Nexus"
  type        = bool
  default     = true
}

variable "ingress_host" {
  description = "Hostname for Nexus ingress"
  type        = string
  default     = "nexus.local"
}

variable "certificate_arn" {
  description = "ARN of SSL certificate for HTTPS"
  type        = string
  default     = ""
}

variable "cpu_request" {
  description = "CPU request for Nexus container"
  type        = string
  default     = "1"
}

variable "memory_request" {
  description = "Memory request for Nexus container"
  type        = string
  default     = "4Gi"
}

variable "cpu_limit" {
  description = "CPU limit for Nexus container"
  type        = string
  default     = "2"
}

variable "memory_limit" {
  description = "Memory limit for Nexus container"
  type        = string
  default     = "8Gi"
}

variable "enable_monitoring" {
  description = "Enable Prometheus monitoring for Nexus"
  type        = bool
  default     = true
} 