# IRSA roles for common AWS controllers and add-ons

locals {
  oidc_provider_arn = var.enable_irsa ? aws_iam_openid_connect_provider.eks[0].arn : ""
  oidc_provider_url = var.enable_irsa ? replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "") : ""
}

# Cluster Autoscaler IRSA
resource "aws_iam_role" "cluster_autoscaler" {
  count = var.enable_irsa && var.enable_cluster_autoscaler ? 1 : 0
  name  = "${var.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-cluster-autoscaler"
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "cluster_autoscaler" {
  count = var.enable_irsa && var.enable_cluster_autoscaler ? 1 : 0
  name  = "${var.cluster_name}-cluster-autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.enable_irsa && var.enable_cluster_autoscaler ? 1 : 0
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
  role       = aws_iam_role.cluster_autoscaler[0].name
}

# AWS Load Balancer Controller IRSA
resource "aws_iam_role" "aws_load_balancer_controller" {
  count = var.enable_irsa && var.enable_aws_load_balancer_controller ? 1 : 0
  name  = "${var.cluster_name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-aws-load-balancer-controller"
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  count = var.enable_irsa && var.enable_aws_load_balancer_controller ? 1 : 0
  name  = "${var.cluster_name}-aws-load-balancer-controller"

  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  count      = var.enable_irsa && var.enable_aws_load_balancer_controller ? 1 : 0
  policy_arn = aws_iam_policy.aws_load_balancer_controller[0].arn
  role       = aws_iam_role.aws_load_balancer_controller[0].name
}

# EBS CSI Driver IRSA
resource "aws_iam_role" "ebs_csi_driver" {
  count = var.enable_irsa && var.enable_ebs_csi_driver ? 1 : 0
  name  = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-ebs-csi-driver"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count      = var.enable_irsa && var.enable_ebs_csi_driver ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver[0].name
}

# EFS CSI Driver IRSA
resource "aws_iam_role" "efs_csi_driver" {
  count = var.enable_irsa && var.enable_efs_csi_driver ? 1 : 0
  name  = "${var.cluster_name}-efs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
        }
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-efs-csi-driver"
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "efs_csi_driver" {
  count = var.enable_irsa && var.enable_efs_csi_driver ? 1 : 0
  name  = "${var.cluster_name}-efs-csi-driver"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:TagResource"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi_driver" {
  count      = var.enable_irsa && var.enable_efs_csi_driver ? 1 : 0
  policy_arn = aws_iam_policy.efs_csi_driver[0].arn
  role       = aws_iam_role.efs_csi_driver[0].name
}

# External DNS IRSA
resource "aws_iam_role" "external_dns" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.cluster_name}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:external-dns"
        }
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-external-dns"
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "external_dns" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.cluster_name}-external-dns"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = var.enable_irsa ? 1 : 0
  policy_arn = aws_iam_policy.external_dns[0].arn
  role       = aws_iam_role.external_dns[0].name
}

# Fluent Bit IRSA
resource "aws_iam_role" "fluent_bit" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.cluster_name}-fluent-bit"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:fluent-bit"
        }
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-fluent-bit"
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "fluent_bit" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.cluster_name}-fluent-bit"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fluent_bit" {
  count      = var.enable_irsa ? 1 : 0
  policy_arn = aws_iam_policy.fluent_bit[0].arn
  role       = aws_iam_role.fluent_bit[0].name
}