variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Puppet Enterprise will be deployed"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for internal access"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for Puppet Enterprise server"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for Puppet Enterprise server (minimum t3.xlarge)"
  type        = string
  default     = "t3.2xlarge"
}

variable "data_volume_size" {
  description = "Size of the EBS data volume for Puppet Enterprise (GB)"
  type        = number
  default     = 100
}

variable "generate_ssh_key" {
  description = "Generate SSH key pair for Puppet Enterprise server"
  type        = bool
  default     = true
}

variable "ssh_key_name" {
  description = "Name of existing SSH key pair (if generate_ssh_key is false)"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Puppet Enterprise services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "pe_version" {
  description = "Puppet Enterprise version to install"
  type        = string
  default     = "latest"
}

variable "pe_download_url" {
  description = "Puppet Enterprise download URL"
  type        = string
  default     = "https://pm.puppet.com/cgi-bin/download.cgi?dist=el&rel=7&arch=x86_64&ver=latest"
}

variable "consul_server_ips" {
  description = "List of Consul server IP addresses for integration"
  type        = list(string)
  default     = []
}

variable "consul_datacenter" {
  description = "Consul datacenter name for service registration"
  type        = string
  default     = ""
}

variable "create_dns_record" {
  description = "Create Route53 DNS record for Puppet Enterprise server"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 zone ID for DNS record"
  type        = string
  default     = ""
} 