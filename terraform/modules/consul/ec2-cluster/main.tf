# Generate random password for Consul if ACLs are enabled
resource "random_password" "consul_master_token" {
  count   = var.enable_acls ? 1 : 0
  length  = 32
  special = true
}

# NOTE: WAN federation secret is now passed as a variable from root module
# No need to create it conditionally here since it's already created at root level

locals {
  consul_master_token = var.enable_acls ? random_password.consul_master_token[0].result : ""
  wan_secret = var.wan_federation_secret
}

# Get Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create security group for Consul
resource "aws_security_group" "consul" {
  name_prefix = "${var.environment}-consul-"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allow_consul_from_cidrs
    description = "SSH access"
  }

  # Consul UI and API
  ingress {
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = var.allow_consul_from_cidrs
    description = "Consul UI and HTTP API"
  }

  # Consul RPC
  ingress {
    from_port = 8300
    to_port   = 8300
    protocol  = "tcp"
    self      = true
    description = "Consul RPC"
  }

  # Consul Serf LAN
  ingress {
    from_port = 8301
    to_port   = 8301
    protocol  = "tcp"
    self      = true
    description = "Consul Serf LAN TCP"
  }

  ingress {
    from_port = 8301
    to_port   = 8301
    protocol  = "udp"
    self      = true
    description = "Consul Serf LAN UDP"
  }

  # Consul Serf WAN (for multi-datacenter)
  ingress {
    from_port   = 8302
    to_port     = 8302
    protocol    = "tcp"
    cidr_blocks = var.allow_consul_from_cidrs
    description = "Consul Serf WAN TCP"
  }

  ingress {
    from_port   = 8302
    to_port     = 8302
    protocol    = "udp"
    cidr_blocks = var.allow_consul_from_cidrs
    description = "Consul Serf WAN UDP"
  }

  # Consul gRPC (for Connect)
  ingress {
    from_port   = 8502
    to_port     = 8502
    protocol    = "tcp"
    cidr_blocks = var.allow_consul_from_cidrs
    description = "Consul gRPC for Connect"
  }

  # Connect sidecar proxy ports
  ingress {
    from_port   = 21000
    to_port     = 21255
    protocol    = "tcp"
    cidr_blocks = var.allow_consul_from_cidrs
    description = "Connect sidecar proxy ports"
  }

  # Mesh gateway
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.allow_consul_from_cidrs
    description = "Mesh gateway"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-consul-sg"
      Environment = var.environment
    }
  )
}

# IAM role for Consul auto-join
resource "aws_iam_role" "consul_auto_join" {
  name = "${var.environment}-consul-auto-join"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "consul_auto_join" {
  name = "${var.environment}-consul-auto-join"
  role = aws_iam_role.consul_auto_join.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "consul" {
  name = "${var.environment}-consul-profile"
  role = aws_iam_role.consul_auto_join.name

  tags = var.common_tags
}

# Create SSH key if not provided
resource "aws_key_pair" "consul" {
  count      = var.key_name == "" ? 1 : 0
  key_name   = "${var.environment}-consul-key"
  public_key = tls_private_key.consul[0].public_key_openssh

  tags = var.common_tags
}

resource "tls_private_key" "consul" {
  count     = var.key_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "consul_ssh_key" {
  count       = var.key_name == "" ? 1 : 0
  name        = "${var.environment}-consul-ssh-private-key"
  description = "SSH private key for Consul servers"

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "consul_ssh_key" {
  count     = var.key_name == "" ? 1 : 0
  secret_id = aws_secretsmanager_secret.consul_ssh_key[0].id
  secret_string = tls_private_key.consul[0].private_key_pem
}

# EC2 Instances for Consul servers
resource "aws_instance" "consul_server" {
  count = var.consul_servers

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : aws_key_pair.consul[0].key_name
  subnet_id              = element(var.private_subnet_ids, count.index)
  vpc_security_group_ids = [aws_security_group.consul.id]
  iam_instance_profile   = aws_iam_instance_profile.consul.name

  user_data = templatefile("${path.module}/templates/user-data.sh.tpl", {
    consul_version    = var.consul_version
    node_name         = "consul-${var.environment}-server-${count.index + 1}"
    datacenter        = var.datacenter_name
    total_servers     = var.consul_servers
    gossip_key        = var.gossip_key
    server_index      = count.index
    retry_join_tag    = "consul-${var.environment}"
    aws_region        = var.aws_region
    enable_connect    = var.enable_connect
    enable_ui         = var.enable_ui
    enable_acls       = var.enable_acls
    master_token      = local.consul_master_token
    primary_datacenter = var.primary_datacenter
    wan_federation_secret = local.wan_secret
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    tags = merge(
      var.common_tags,
      {
        Name        = "consul-${var.environment}-server-${count.index + 1}-root"
        Environment = var.environment
      }
    )
  }

  tags = merge(
    var.common_tags,
    {
      Name           = "consul-${var.environment}-server-${count.index + 1}"
      Environment    = var.environment
      ConsulAutoJoin = "consul-${var.environment}"
      ConsulType     = "server"
      ManagedBy      = "terraform"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Create Application Load Balancer for Consul UI
resource "aws_lb" "consul_ui" {
  count              = var.enable_ui ? 1 : 0
  name               = "${var.environment}-consul-ui"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.consul_alb[0].id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-consul-ui-alb"
      Environment = var.environment
    }
  )
}

# Security group for ALB
resource "aws_security_group" "consul_alb" {
  count       = var.enable_ui ? 1 : 0
  name_prefix = "${var.environment}-consul-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access to Consul UI"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access to Consul UI"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-consul-alb-sg"
      Environment = var.environment
    }
  )
}

# Target group for Consul UI
resource "aws_lb_target_group" "consul_ui" {
  count    = var.enable_ui ? 1 : 0
  name     = "${var.environment}-consul-ui"
  port     = 8500
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/v1/agent/self"
    matcher             = "200"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-consul-ui-tg"
      Environment = var.environment
    }
  )
}

# Attach instances to target group
resource "aws_lb_target_group_attachment" "consul_ui" {
  count            = var.enable_ui ? var.consul_servers : 0
  target_group_arn = aws_lb_target_group.consul_ui[0].arn
  target_id        = aws_instance.consul_server[count.index].id
  port             = 8500
}

# ALB listener
resource "aws_lb_listener" "consul_ui" {
  count             = var.enable_ui ? 1 : 0
  load_balancer_arn = aws_lb.consul_ui[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul_ui[0].arn
  }
}

# Store Consul configuration in AWS Secrets Manager
resource "aws_secretsmanager_secret" "consul_config" {
  name        = "${var.environment}-consul-config"
  description = "Consul cluster configuration and secrets"

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "consul_config" {
  secret_id = aws_secretsmanager_secret.consul_config.id
  secret_string = jsonencode({
    datacenter_name       = var.datacenter_name
    gossip_key           = var.gossip_key
    master_token         = local.consul_master_token
    wan_federation_secret = local.wan_secret
    server_ips           = aws_instance.consul_server[*].private_ip
    ui_url              = var.enable_ui ? "http://${aws_lb.consul_ui[0].dns_name}" : ""
  })
} 