# AWS RDS Terraform Module

This module creates an RDS instance with the following features:

- Multi-AZ deployment for high availability
- Automated backups with configurable retention
- Encryption at rest using KMS
- Enhanced monitoring and Performance Insights
- Security group with configurable access rules
- AWS Secrets Manager integration for password management
- Storage autoscaling

## Usage

```hcl
module "rds" {
  source = "../../../modules/aws/rds"

  identifier = "myapp-postgres"
  
  # Database
  engine         = "postgres"
  engine_version = "15.4"
  database_name  = "myapp"
  
  # Resources
  instance_class        = "db.t3.small"
  allocated_storage     = 20
  max_allocated_storage = 100
  
  # Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnets
  
  # Security
  allowed_security_groups = [module.eks.cluster_security_group_id]
  
  # Backup
  backup_retention_period = 30
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Monitoring
  performance_insights_enabled = true
  monitoring_interval         = 60
  
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  tags = local.tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Inputs

See `variables.tf` for a complete list of inputs.

## Outputs

| Name | Description |
|------|-------------|
| db_instance_endpoint | The connection endpoint |
| db_instance_address | The address of the RDS instance |
| db_master_password_secret_arn | The ARN of the master password secret in AWS Secrets Manager |