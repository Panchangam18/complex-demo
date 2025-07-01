# Puppet Enterprise on AWS EC2 - Integrated with existing infrastructure
# Configuration management server for multi-cloud infrastructure

# Generate random password for PE Console admin
resource "random_password" "pe_console_admin_password" {
  length  = 16
  special = true
}

# Generate SSH key pair for Puppet Enterprise server
resource "tls_private_key" "puppet_key" {
  count     = var.generate_ssh_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store SSH private key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "puppet_ssh_key" {
  count                   = var.generate_ssh_key ? 1 : 0
  name                    = "${var.environment}-puppet-ssh-private-key"
  description             = "SSH private key for Puppet Enterprise server"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "puppet_ssh_key" {
  count     = var.generate_ssh_key ? 1 : 0
  secret_id = aws_secretsmanager_secret.puppet_ssh_key[0].id
  secret_string = jsonencode({
    private_key = tls_private_key.puppet_key[0].private_key_pem
  })
}

# Store PE Console admin password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "pe_console_admin_password" {
  name                    = "${var.environment}-puppet-admin-password"
  description             = "Puppet Enterprise Console admin password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "pe_console_admin_password" {
  secret_id = aws_secretsmanager_secret.pe_console_admin_password.id
  secret_string = jsonencode({
    password = random_password.pe_console_admin_password.result
  })
}

# Create SSH key pair in AWS
resource "aws_key_pair" "puppet_key" {
  count      = var.generate_ssh_key ? 1 : 0
  key_name   = "${var.environment}-puppet-key"
  public_key = tls_private_key.puppet_key[0].public_key_openssh
}

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group for Puppet Enterprise
resource "aws_security_group" "puppet_enterprise_sg" {
  name_prefix = "${var.environment}-puppet-enterprise-"
  vpc_id      = var.vpc_id
  description = "Security group for Puppet Enterprise server"
  
  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # PE Console (HTTPS)
  ingress {
    description = "PE Console HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Puppet Server
  ingress {
    description = "Puppet Server"
    from_port   = 8140
    to_port     = 8140
    protocol    = "tcp"
    cidr_blocks = concat(var.allowed_cidr_blocks, [var.vpc_cidr])
  }
  
  # PuppetDB
  ingress {
    description = "PuppetDB"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # PE Orchestrator
  ingress {
    description = "PE Orchestrator"
    from_port   = 8142
    to_port     = 8142
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # PE Orchestrator/PCP Broker
  ingress {
    description = "PE Orchestrator PCP Broker"
    from_port   = 8143
    to_port     = 8143
    protocol    = "tcp"
    cidr_blocks = concat(var.allowed_cidr_blocks, [var.vpc_cidr])
  }
  
  # Code Manager
  ingress {
    description = "Code Manager"
    from_port   = 8170
    to_port     = 8170
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # RBAC Service
  ingress {
    description = "PE RBAC Service"
    from_port   = 4433
    to_port     = 4433
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-puppet-enterprise-sg"
    Environment = var.environment
    Service     = "puppet-enterprise"
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for Puppet Enterprise server
resource "aws_iam_role" "puppet_enterprise_role" {
  name_prefix = "${var.environment}-puppet-enterprise-"

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

  tags = {
    Environment = var.environment
    Service     = "puppet-enterprise"
  }
}

# IAM policy for Puppet Enterprise server
resource "aws_iam_role_policy" "puppet_enterprise_policy" {
  name_prefix = "${var.environment}-puppet-enterprise-"
  role        = aws_iam_role.puppet_enterprise_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeRegions",
          "ec2:DescribeSnapshots",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.pe_console_admin_password.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "puppet_enterprise_profile" {
  name_prefix = "${var.environment}-puppet-enterprise-"
  role        = aws_iam_role.puppet_enterprise_role.name
}

# User data script for Puppet Enterprise installation
locals {
  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    environment                = var.environment
    pe_version                = var.pe_version
    pe_console_admin_password = random_password.pe_console_admin_password.result
    pe_download_url           = var.pe_download_url
    aws_region                = var.aws_region
    consul_server_ips         = join(",", var.consul_server_ips)
    consul_datacenter         = var.consul_datacenter
    puppet_fqdn               = "puppet-enterprise.${var.environment}.local"
  }))
}

# EC2 instance for Puppet Enterprise (using auto-assigned public IP to avoid EIP limit)
resource "aws_instance" "puppet_enterprise_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.generate_ssh_key ? aws_key_pair.puppet_key[0].key_name : var.ssh_key_name
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.puppet_enterprise_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.puppet_enterprise_profile.name
  associate_public_ip_address = true

  user_data = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
    iops        = 3000
    throughput  = 125
    tags = {
      Name        = "${var.environment}-puppet-enterprise-root"
      Environment = var.environment
      Service     = "puppet-enterprise"
    }
  }

  # Data volume for Puppet Enterprise persistence
  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = var.data_volume_size
    encrypted             = true
    iops                  = 3000
    throughput            = 125
    delete_on_termination = false
    tags = {
      Name        = "${var.environment}-puppet-enterprise-data"
      Environment = var.environment
      Service     = "puppet-enterprise"
    }
  }

  tags = {
    Name        = "${var.environment}-puppet-enterprise"
    Environment = var.environment
    Service     = "puppet-enterprise"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_secretsmanager_secret_version.pe_console_admin_password
  ]
}

# Create a Route53 record for the Puppet Enterprise server (optional)
resource "aws_route53_record" "puppet_enterprise" {
  count   = var.create_dns_record ? 1 : 0
  zone_id = var.route53_zone_id
  name    = "puppet-enterprise.${var.environment}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.puppet_enterprise_server.public_ip]
} 