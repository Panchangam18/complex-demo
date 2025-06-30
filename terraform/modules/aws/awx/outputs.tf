# =============================================
# AWX Service Outputs
# =============================================

output "awx_url" {
  description = "AWX web interface URL"
  value       = var.create_route53_record && var.enable_https ? "https://${aws_route53_record.awx[0].fqdn}" : (
    var.create_route53_record ? "http://${aws_route53_record.awx[0].fqdn}" : (
      var.enable_https ? "https://${aws_lb.awx.dns_name}" : "http://${aws_lb.awx.dns_name}"
    )
  )
}

output "alb_dns_name" {
  description = "DNS name of the AWX Application Load Balancer"
  value       = aws_lb.awx.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the AWX Application Load Balancer"
  value       = aws_lb.awx.zone_id
}

output "alb_arn" {
  description = "ARN of the AWX Application Load Balancer"
  value       = aws_lb.awx.arn
}

# =============================================
# Database Outputs
# =============================================

output "database_endpoint" {
  description = "Aurora PostgreSQL cluster endpoint"
  value       = var.database_endpoint != "" ? var.database_endpoint : (
    var.enable_database ? module.aurora[0].cluster_endpoint : null
  )
}

output "database_reader_endpoint" {
  description = "Aurora PostgreSQL cluster reader endpoint"
  value       = var.enable_database && var.database_endpoint == "" ? module.aurora[0].cluster_reader_endpoint : null
}

output "database_port" {
  description = "Database port"
  value       = 5432
}

output "database_name" {
  description = "Database name"
  value       = "awx"
}

# =============================================
# ECS Cluster Outputs
# =============================================

output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.awx.id
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.awx.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.awx.name
}

# =============================================
# Security Group Outputs
# =============================================

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS services"
  value       = aws_security_group.ecs_services.id
}

output "database_security_group_id" {
  description = "Security group ID for the database"
  value       = var.enable_database && var.database_endpoint == "" ? aws_security_group.database[0].id : null
}

# =============================================
# Secrets Outputs
# =============================================

output "admin_password_secret_arn" {
  description = "ARN of the AWX admin password secret"
  value       = aws_secretsmanager_secret.awx_admin_password.arn
  sensitive   = true
}

output "secret_key_secret_arn" {
  description = "ARN of the AWX secret key secret"
  value       = aws_secretsmanager_secret.awx_secret_key.arn
  sensitive   = true
}

output "database_password_secret_arn" {
  description = "ARN of the database password secret"
  value       = aws_secretsmanager_secret.db_password.arn
  sensitive   = true
}

# =============================================
# AWS Account Information
# =============================================

output "aws_region" {
  description = "AWS region where AWX is deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where AWX is deployed"
  value       = data.aws_caller_identity.current.account_id
}

# =============================================
# AWX Connection Info Summary
# =============================================

output "awx_connection_info" {
  description = "Complete AWX connection information"
  value = {
    url                = var.create_route53_record && var.enable_https ? "https://${aws_route53_record.awx[0].fqdn}" : (
      var.create_route53_record ? "http://${aws_route53_record.awx[0].fqdn}" : (
        var.enable_https ? "https://${aws_lb.awx.dns_name}" : "http://${aws_lb.awx.dns_name}"
      )
    )
    admin_username     = var.awx_admin_username
    database_endpoint  = var.database_endpoint != "" ? var.database_endpoint : (
      var.enable_database ? module.aurora[0].cluster_endpoint : "external"
    )
    cluster_name       = var.cluster_name
    environment        = var.environment
    https_enabled      = var.enable_https
  }
} 