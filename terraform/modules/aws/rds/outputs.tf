output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.this.id
}

output "db_instance_resource_id" {
  description = "The RDS Resource ID of this instance"
  value       = aws_db_instance.this.resource_id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.this.arn
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = aws_db_instance.this.address
}

output "db_instance_endpoint" {
  description = "The connection endpoint"
  value       = aws_db_instance.this.endpoint
}

output "db_instance_hosted_zone_id" {
  description = "The canonical hosted zone ID of the DB instance (to be used in a Route 53 Alias record)"
  value       = aws_db_instance.this.hosted_zone_id
}

output "db_instance_name" {
  description = "The database name"
  value       = aws_db_instance.this.db_name
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = aws_db_instance.this.username
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = aws_db_instance.this.port
}

output "db_instance_availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = aws_db_instance.this.availability_zone
}

output "db_instance_multi_az" {
  description = "If the RDS instance is multi-AZ"
  value       = aws_db_instance.this.multi_az
}

output "db_instance_status" {
  description = "The RDS instance status"
  value       = aws_db_instance.this.status
}

output "db_instance_engine" {
  description = "The database engine"
  value       = aws_db_instance.this.engine
}

output "db_instance_engine_version_actual" {
  description = "The running version of the database"
  value       = aws_db_instance.this.engine_version_actual
}

output "db_instance_storage_encrypted" {
  description = "Whether the DB instance is encrypted"
  value       = aws_db_instance.this.storage_encrypted
}

output "db_instance_kms_key_id" {
  description = "The KMS key ID used for encryption"
  value       = aws_db_instance.this.kms_key_id
}

output "db_subnet_group_id" {
  description = "The db subnet group ID"
  value       = aws_db_subnet_group.this.id
}

output "db_subnet_group_arn" {
  description = "The ARN of the db subnet group"
  value       = aws_db_subnet_group.this.arn
}

output "db_parameter_group_id" {
  description = "The db parameter group ID"
  value       = try(aws_db_parameter_group.this[0].id, null)
}

output "db_parameter_group_arn" {
  description = "The ARN of the db parameter group"
  value       = try(aws_db_parameter_group.this[0].arn, null)
}

output "db_security_group_id" {
  description = "The security group ID of the RDS instance"
  value       = aws_security_group.this.id
}

output "db_security_group_arn" {
  description = "The ARN of the security group"
  value       = aws_security_group.this.arn
}

output "db_monitoring_role_arn" {
  description = "The ARN of the monitoring role"
  value       = try(aws_iam_role.monitoring[0].arn, null)
}

output "db_master_password_secret_arn" {
  description = "The ARN of the master password secret in AWS Secrets Manager"
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}