# =============================================
# AWX Task Role
# =============================================

resource "aws_iam_role" "awx_task_role" {
  name               = "${var.cluster_name}-awx-task-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role_policy_document.json

  force_detach_policies = true

  tags = var.common_tags
}

data "aws_iam_policy_document" "task_assume_role_policy_document" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Attach EC2 read-only access for dynamic inventory
resource "aws_iam_role_policy_attachment" "task_role_ec2_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
  role       = aws_iam_role.awx_task_role.name
}

# Attach EKS read access for Kubernetes management
resource "aws_iam_role_policy_attachment" "task_role_eks_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.awx_task_role.name
}

# Custom policy for Ansible automation
resource "aws_iam_role_policy" "awx_automation_policy" {
  name = "${var.cluster_name}-awx-automation-policy"
  role = aws_iam_role.awx_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "autoscaling:DescribeAutoScalingGroups",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "eks:DescribeCluster",
          "eks:ListClusters",
          "secretsmanager:GetSecretValue",
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================
# CloudWatch Logs
# =============================================

resource "aws_cloudwatch_log_group" "awx" {
  name              = "/ecs/${var.cluster_name}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}

# =============================================
# ECS Cluster
# =============================================

resource "aws_ecs_cluster" "awx" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.common_tags
}

# =============================================
# AWX Single Task Definition (All Containers)
# =============================================

resource "aws_ecs_task_definition" "awx" {
  family                   = var.cluster_name
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.awx_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = 8192  # Total memory for all containers
  cpu                      = 4096  # Total CPU for all containers

  container_definitions = templatefile("${path.module}/templates/awx_combined_service.json.tpl", {
    database_host           = var.database_endpoint != "" ? var.database_endpoint : module.aurora[0].cluster_endpoint
    database_username       = var.db_username
    database_password_arn   = aws_secretsmanager_secret_version.db_password.arn
    awx_secret_key_arn     = aws_secretsmanager_secret_version.awx_secret_key.arn
    awx_admin_password_arn = aws_secretsmanager_secret_version.awx_admin_password.arn
    awx_admin_user         = var.awx_admin_username
    log_group              = aws_cloudwatch_log_group.awx.name
    aws_region             = data.aws_region.current.name
    cluster_name           = var.cluster_name
  })

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-awx-task-definition"
  })
}

# =============================================
# AWX ECS Service (Single Service for All Containers)
# =============================================

resource "aws_ecs_service" "awx" {
  name            = var.cluster_name
  cluster         = aws_ecs_cluster.awx.id
  task_definition = aws_ecs_task_definition.awx.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.awx.arn
    container_name   = "awxweb"
    container_port   = 8052
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  depends_on = [aws_lb_listener.awx]

  tags = var.common_tags
}

# =============================================
# Data Sources
# =============================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {} 