# KMS Key for EKS cluster encryption
resource "aws_kms_key" "eks" {
  count                   = var.enable_cluster_encryption ? 1 : 0
  description             = "KMS key for EKS cluster ${var.cluster_name} encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-eks-key"
      Environment = var.environment
    }
  )
}

resource "aws_kms_alias" "eks" {
  count         = var.enable_cluster_encryption ? 1 : 0
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks[0].key_id
}

# CloudWatch Log Group for EKS cluster logs
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-eks-logs"
      Environment = var.environment
    }
  )
}

# IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-eks-cluster-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# Security group for EKS cluster
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.cluster_name}-eks-cluster-"
  description = "Security group for EKS cluster ${var.cluster_name}"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-eks-cluster-sg"
      Environment = var.environment
    }
  )
}

# Additional security group for pods
resource "aws_security_group" "eks_pods" {
  name_prefix = "${var.cluster_name}-eks-pods-"
  description = "Security group for EKS pods in ${var.cluster_name}"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Allow all traffic between pods"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.eks_cluster.id]
    description     = "Allow all traffic from cluster security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-eks-pods-sg"
      Environment = var.environment
    }
  )
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name                          = var.cluster_name
  version                       = var.cluster_version
  role_arn                      = aws_iam_role.eks_cluster.arn
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  encryption_config {
    provider {
      key_arn = var.enable_cluster_encryption ? aws_kms_key.eks[0].arn : null
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = var.cluster_log_types

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks,
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = var.cluster_name
      Environment = var.environment
    }
  )
}

# OIDC Provider for IRSA
data "tls_certificate" "eks" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = concat(["sts.amazonaws.com"], var.oidc_audiences)
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-eks-oidc"
      Environment = var.environment
    }
  )
}

# IAM role for node groups
resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-eks-node-role"

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
      Name = "${var.cluster_name}-eks-node-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "eks_nodes_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_nodes.name
}

# EKS Managed Node Groups
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.subnet_ids
  version         = var.cluster_version

  instance_types = each.value.instance_types
  disk_size      = each.value.disk_size

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = merge(
    each.value.labels,
    {
      Environment = var.environment
      NodeGroup   = each.key
    }
  )

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_policy,
    aws_iam_role_policy_attachment.eks_nodes_cni_policy,
    aws_iam_role_policy_attachment.eks_nodes_container_registry,
    aws_iam_role_policy_attachment.eks_nodes_ssm,
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-node-group-${each.key}"
      Environment = var.environment
      NodeGroup   = each.key
    }
  )
}

# Fargate Profiles
resource "aws_iam_role" "eks_fargate" {
  count = length(var.fargate_profiles) > 0 ? 1 : 0
  name  = "${var.cluster_name}-eks-fargate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-eks-fargate-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "eks_fargate_pod_execution" {
  count      = length(var.fargate_profiles) > 0 ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.eks_fargate[0].name
}

resource "aws_eks_fargate_profile" "main" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = aws_iam_role.eks_fargate[0].arn
  subnet_ids             = var.subnet_ids

  selector {
    namespace = each.value.namespace
    labels    = each.value.labels
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_fargate_pod_execution,
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.cluster_name}-fargate-${each.key}"
      Environment = var.environment
    }
  )
}