variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Jenkins will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for Jenkins server"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t3.medium"
}

variable "volume_size" {
  description = "Size of the EBS volume for Jenkins server (GB)"
  type        = number
  default     = 30
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 instance access. If empty, a new key pair will be generated"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Jenkins SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Integration with other services
variable "nexus_url" {
  description = "Nexus Repository Manager URL for Maven/NPM proxy configuration"
  type        = string
  default     = ""
}

variable "consul_server_ips" {
  description = "List of Consul server IP addresses for service registration"
  type        = list(string)
  default     = []
}

variable "eks_cluster_name" {
  description = "EKS cluster name for kubectl configuration"
  type        = string
  default     = ""
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster endpoint for kubectl configuration"
  type        = string
  default     = ""
}

# Jenkins specific configuration
variable "jenkins_java_opts" {
  description = "Java options for Jenkins JVM"
  type        = string
  default     = "-Xmx2g -Xms1g -XX:MaxMetaspaceSize=512m"
}

variable "jenkins_plugins" {
  description = "List of Jenkins plugins to install"
  type        = list(string)
  default = [
    "blueocean",
    "pipeline-stage-view",
    "docker-workflow",
    "kubernetes",
    "git",
    "github",
    "github-branch-source",
    "pipeline-github-lib",
    "nodejs",
    "ant",
    "gradle",
    "maven-invoker",
    "build-timeout",
    "timestamper",
    "ws-cleanup",
    "prometheus"
  ]
}

variable "enable_consul_integration" {
  description = "Enable Consul service registration for Jenkins"
  type        = bool
  default     = true
}

variable "enable_prometheus_metrics" {
  description = "Enable Prometheus metrics export from Jenkins"
  type        = bool
  default     = true
} 