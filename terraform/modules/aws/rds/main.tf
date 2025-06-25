locals {
  port = var.port == null ? (
    var.engine == "postgres" ? 5432 :
    var.engine == "mysql" ? 3306 :
    var.engine == "mariadb" ? 3306 :
    var.engine == "oracle-ee" ? 1521 :
    var.engine == "sqlserver-ex" ? 1433 :
    5432
  ) : var.port

  monitoring_role_name = var.monitoring_role_name != null ? var.monitoring_role_name : "${var.identifier}-rds-monitoring-role"
}

################################################################################
# DB Subnet Group
################################################################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    var.db_subnet_group_tags,
    {
      Name = "${var.identifier}-subnet-group"
    }
  )

  # The existing subnet group may reference different VPC subnets that cannot
  # be changed without replacement. Ignore changes so apply doesn\'t fail when
  # the live subnets differ from the desired list.
  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "this" {
  name_prefix = "${var.identifier}-rds-"
  vpc_id      = var.vpc_id
  description = "Security group for RDS instance ${var.identifier}"

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-rds-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ingress_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = local.port
  to_port           = local.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.this.id
  description       = "Allow inbound traffic from CIDR blocks"
}

resource "aws_security_group_rule" "ingress_security_groups" {
  count = length(var.allowed_security_groups)

  type                     = "ingress"
  from_port                = local.port
  to_port                  = local.port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_groups[count.index]
  security_group_id        = aws_security_group.this.id
  description              = "Allow inbound traffic from security group"
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"
}

################################################################################
# Enhanced Monitoring IAM Role
################################################################################

data "aws_iam_policy_document" "monitoring_assume_role" {
  count = var.create_monitoring_role && var.monitoring_interval > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.create_monitoring_role && var.monitoring_interval > 0 ? 1 : 0

  name               = local.monitoring_role_name
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.create_monitoring_role && var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# DB Parameter Group
################################################################################

resource "aws_db_parameter_group" "this" {
  count = length(var.parameters) > 0 ? 1 : 0

  name_prefix = "${var.identifier}-"
  family      = var.parameter_group_family

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = contains([
        "shared_preload_libraries",
        "max_connections",
        "shared_buffers",
        "effective_cache_size",
        "wal_level",
        "max_wal_senders",
        "wal_keep_segments",
        "archive_mode"
      ], parameter.key) ? "pending-reboot" : "immediate"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-parameter-group"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# RDS Instance
################################################################################

resource "aws_db_instance" "this" {
  identifier = var.identifier

  # Engine options
  engine         = var.engine
  engine_version = var.engine_version

  # Settings
  db_name  = var.database_name
  username = var.username
  password = var.manage_master_user_password ? null : var.password
  port     = local.port

  # Instance configuration
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az

  # Database authentication
  manage_master_user_password = var.manage_master_user_password

  # Backup
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # Monitoring
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? (var.create_monitoring_role ? aws_iam_role.monitoring[0].arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.monitoring_role_name}") : null

  # Parameter group
  parameter_group_name = length(var.parameters) > 0 ? aws_db_parameter_group.this[0].name : null

  # Deletion protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier != null ? var.final_snapshot_identifier : "${var.identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = var.tags

  # Ignore changes to final_snapshot_identifier since timestamp() always changes
  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }

  timeouts {
    create = "40m"
    update = "40m"
    delete = "40m"
  }
}

################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}