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

# Security group rules for cluster-to-node communication
# NOTE: Removed cluster_to_nodes rule as it's redundant with the inline rule above
# that already allows ALL traffic from cluster to pods (0-0/-1 covers 443/tcp)

resource "aws_security_group_rule" "nodes_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_pods.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "Allow nodes to communicate with cluster API server"
}

# Allow NodePort traffic from external load balancers (e.g., Classic/ALB) to the worker nodes
resource "aws_security_group_rule" "nodes_nodeport_ingress" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_pods.id
  description       = "Allow Kubernetes NodePorts from anywhere"
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

# Get the latest EKS-optimized AMI
data "aws_ami" "eks_worker" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Launch template for node groups
resource "aws_launch_template" "eks_nodes" {
  for_each = var.node_groups

  name_prefix = "${var.cluster_name}-${each.key}-"
  
  # Specify the EKS-optimized AMI
  image_id = data.aws_ami.eks_worker.image_id
  
  # User data to bootstrap nodes into the EKS cluster
  user_data = base64encode(<<-EOF
#!/bin/bash
/etc/eks/bootstrap.sh ${aws_eks_cluster.main.name}
EOF
  )
  
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    
    ebs {
      volume_size = each.value.disk_size
      volume_type = "gp3"
      iops        = 3000
      encrypted   = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      {
        Name        = "${var.cluster_name}-node-${each.key}"
        Environment = var.environment
        NodeGroup   = each.key
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EKS Managed Node Groups
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.subnet_ids

  instance_types = each.value.instance_types

  launch_template {
    id      = aws_launch_template.eks_nodes[each.key].id
    version = aws_launch_template.eks_nodes[each.key].latest_version
  }

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

# EKS Add-ons
resource "aws_eks_addon" "vpc_cni" {
  count = var.enable_vpc_cni_addon ? 1 : 0
  
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  
  resolve_conflicts_on_create = "OVERWRITE"
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-vpc-cni"
    }
  )
}

resource "aws_eks_addon" "kube_proxy" {
  count = var.enable_kube_proxy_addon ? 1 : 0
  
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  
  resolve_conflicts_on_create = "OVERWRITE"
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-kube-proxy"
    }
  )
}

resource "aws_eks_addon" "coredns" {
  count = var.enable_coredns_addon ? 1 : 0
  
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  
  resolve_conflicts_on_create = "OVERWRITE"
  
  depends_on = [
    aws_eks_node_group.main
  ]
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-coredns"
    }
  )
}

resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0
  
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
  
  resolve_conflicts_on_create = "OVERWRITE"
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-ebs-csi-driver"
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