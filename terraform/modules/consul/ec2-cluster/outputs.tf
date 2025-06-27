output "server_instances" {
  description = "Consul server instances"
  value       = aws_instance.consul_server
}

output "server_private_ips" {
  description = "Private IP addresses of Consul servers"
  value       = aws_instance.consul_server[*].private_ip
}

output "server_public_ips" {
  description = "Public IP addresses of Consul servers"
  value       = aws_instance.consul_server[*].public_ip
}

output "consul_ui_url" {
  description = "Consul UI URL"
  value       = var.enable_ui ? "http://${aws_lb.consul_ui[0].dns_name}" : ""
}

output "consul_ui_alb_dns" {
  description = "ALB DNS name for Consul UI"
  value       = var.enable_ui ? aws_lb.consul_ui[0].dns_name : ""
}

output "consul_security_group_id" {
  description = "Security group ID for Consul servers"
  value       = aws_security_group.consul.id
}

output "datacenter_name" {
  description = "Consul datacenter name"
  value       = var.datacenter_name
}

output "gossip_key" {
  description = "Consul gossip encryption key"
  value       = var.gossip_key
  sensitive   = true
}

output "wan_federation_secret" {
  description = "WAN federation secret for multi-datacenter setup"
  value       = local.wan_secret
  sensitive   = true
}

output "consul_config_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing Consul configuration"
  value       = aws_secretsmanager_secret.consul_config.arn
}

output "consul_master_token" {
  description = "Consul master token (if ACLs enabled)"
  value       = local.consul_master_token
  sensitive   = true
}

output "ssh_key_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing SSH private key"
  value       = var.key_name == "" ? aws_secretsmanager_secret.consul_ssh_key[0].arn : ""
}

output "consul_connection_info" {
  description = "Connection information for Consul cluster"
  value = {
    ui_url                = var.enable_ui ? "http://${aws_lb.consul_ui[0].dns_name}" : ""
    datacenter           = var.datacenter_name
    server_ips           = aws_instance.consul_server[*].private_ip
    gossip_encrypted     = true
    connect_enabled      = var.enable_connect
    acls_enabled         = var.enable_acls
  }
} 