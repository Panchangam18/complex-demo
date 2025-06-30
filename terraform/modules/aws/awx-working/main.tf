# =============================================
# AWX Task Role
# =============================================

resource "aws_iam_role" "awx_task_role" {
  name               = "${var.cluster_name}-awx-task-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role_policy_document.json

  # necessary to ensure deletion 
  force_detach_policies = true

  tags = var.common_tags
}

data "aws_iam_policy_document" "task_assume_role_policy_document" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Attach EC2 read-only access for dynamic inventory
resource "aws_iam_role_policy_attachment" "awx_task_role_ec2_read_only" {
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
# Note: Service Discovery removed - using localhost communication
# =============================================

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
# ECS - AWX Combined Service (All containers in one task)
# =============================================

resource "aws_ecs_task_definition" "awx_combined" {
  family                   = "${var.cluster_name}"
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.awx_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = 8192  # Total memory for all containers
  cpu                      = 4096  # Total CPU for all containers

  container_definitions = templatefile("${path.module}/templates/awx_combined_service.json", {
    cluster_name            = var.cluster_name
    aws_region             = var.aws_region
    database_username      = var.database_username
    database_host          = var.database_host
    awx_admin_username     = var.awx_admin_username
    database_password_arn  = var.database_password_arn
    awx_secret_key_arn     = var.awx_secret_key_arn
    awx_admin_password_arn = var.awx_admin_password_arn
    dockerhub_secret_arn   = var.dockerhub_secret_arn
  })

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-combined-task-definition"
  })
}

resource "aws_ecs_service" "awx_combined" {
  name            = "${var.cluster_name}"
  cluster         = aws_ecs_cluster.awx.id
  task_definition = aws_ecs_task_definition.awx_combined.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.awx.arn
    container_name   = "awxweb"
    container_port   = 8052
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }

  depends_on = [aws_lb_listener.http]

  tags = var.common_tags
}

# =============================================
# Note: Using combined single-task approach
# All AWX services (web, task, queue, cache) are now in one task definition
# =============================================

# =============================================
# Data Sources
# =============================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

 