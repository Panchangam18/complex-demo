resource "aws_ecr_repository" "main" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push != null ? each.value.scan_on_push : var.enable_image_scanning
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_id : null
  }

  tags = merge(
    var.common_tags,
    {
      Name        = each.key
      Environment = var.environment
    }
  )
}

resource "aws_ecr_lifecycle_policy" "main" {
  for_each = var.repositories

  repository = aws_ecr_repository.main[each.key].name
  policy     = each.value.lifecycle_policy != null ? each.value.lifecycle_policy : var.default_lifecycle_policy
}

resource "aws_ecr_repository_policy" "main" {
  for_each = var.enable_cross_account_access ? var.repositories : {}

  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CrossAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.cross_account_arns
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages"
        ]
      }
    ]
  })
}

# Pull through cache for public registries (Docker Hub, etc.)
resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  count = var.environment == "prod" ? 1 : 0

  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
}

resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  count = var.environment == "prod" ? 1 : 0

  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

resource "aws_ecr_pull_through_cache_rule" "kubernetes" {
  count = var.environment == "prod" ? 1 : 0

  ecr_repository_prefix = "kubernetes"
  upstream_registry_url = "registry.k8s.io"
}

resource "aws_ecr_pull_through_cache_rule" "quay" {
  count = var.environment == "prod" ? 1 : 0

  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}

# Registry scanning configuration
resource "aws_ecr_registry_scanning_configuration" "main" {
  count = var.environment == "prod" ? 1 : 0

  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

# IAM role for ECR pull/push from EKS nodes
resource "aws_iam_role" "ecr_pull" {
  name = "${var.environment}-ecr-pull-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-ecr-pull-role"
    }
  )
}

resource "aws_iam_role_policy" "ecr_pull" {
  name = "${var.environment}-ecr-pull-policy"
  role = aws_iam_role.ecr_pull.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}