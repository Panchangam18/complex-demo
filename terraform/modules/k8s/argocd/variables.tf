variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
  default     = "sandbox-permanent"
}

variable "k8s_manifests_path" {
  description = "Path to the k8s manifests directory"
  type        = string
  default     = "../../../../k8s"
} 