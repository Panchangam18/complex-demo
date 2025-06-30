# Jenkins on AWS EC2 - Integrated with existing VPC infrastructure
# Based on the original jenkins/ approach but using existing infrastructure

# Generate random password for Jenkins admin
resource "random_password" "jenkins_admin_password" {
  length  = 16
  special = true
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

# Create security group for Jenkins
resource "aws_security_group" "jenkins_sg" {
  name_prefix = "${var.environment}-jenkins-"
  vpc_id      = var.vpc_id
  description = "Security group for Jenkins server"
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH access"
  }
  
  # Jenkins web interface
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Jenkins web interface"
  }
  
  # Jenkins JNLP port for agents
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Jenkins JNLP agent port"
  }
  
  # All outbound traffic
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
      Name        = "${var.environment}-jenkins-sg"
      Environment = var.environment
      Service     = "jenkins"
    }
  )
}

# Create SSH key pair for Jenkins if not provided
resource "tls_private_key" "jenkins_key" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "jenkins_key" {
  key_name   = "${var.environment}-jenkins-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.jenkins_key[0].public_key_openssh
  
  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-jenkins-key-pair"
      Environment = var.environment
      Service     = "jenkins"
    }
  )
}

# Store private key in AWS Secrets Manager if auto-generated
resource "aws_secretsmanager_secret" "jenkins_ssh_key" {
  count       = var.ssh_public_key == "" ? 1 : 0
  name        = "${var.environment}-jenkins-ssh-private-key"
  description = "SSH private key for Jenkins server"
  
  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "jenkins_ssh_key" {
  count     = var.ssh_public_key == "" ? 1 : 0
  secret_id = aws_secretsmanager_secret.jenkins_ssh_key[0].id
  secret_string = jsonencode({
    private_key = tls_private_key.jenkins_key[0].private_key_pem
    public_key  = tls_private_key.jenkins_key[0].public_key_openssh
  })
}

# Create IAM role for Jenkins EC2 instance
resource "aws_iam_role" "jenkins_role" {
  name = "${var.environment}-jenkins-ec2-role"
  
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
  
  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-jenkins-iam-role"
      Environment = var.environment
      Service     = "jenkins"
    }
  )
}

# Enhanced IAM policies for Jenkins
resource "aws_iam_role_policy" "jenkins_policy" {
  name = "${var.environment}-jenkins-policy"
  role = aws_iam_role.jenkins_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.environment}-*"
        ]
      }
    ]
  })
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.environment}-jenkins-instance-profile"
  role = aws_iam_role.jenkins_role.name
  
  tags = var.common_tags
}

# Store Jenkins admin password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "jenkins_admin_password" {
  name        = "${var.environment}-jenkins-admin-password"
  description = "Jenkins admin password"
  
  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "jenkins_admin_password" {
  secret_id = aws_secretsmanager_secret.jenkins_admin_password.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.jenkins_admin_password.result
  })
}

# User data script for Jenkins installation
locals {
  user_data = base64encode(file("${path.module}/user_data.sh"))
}

# Create Jenkins EC2 instance
resource "aws_instance" "jenkins_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name              = aws_key_pair.jenkins_key.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  subnet_id             = var.public_subnet_ids[0]  # Use first public subnet
  iam_instance_profile  = aws_iam_instance_profile.jenkins_profile.name
  
  user_data = local.user_data
  
  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size
    encrypted   = true
  }
  
  tags = merge(
    var.common_tags,
    {
      Name                = "${var.environment}-jenkins-server"
      Environment         = var.environment
      Service             = "jenkins"
      jenkins_server      = "true"
    }
  )
}

# Create Elastic IP for Jenkins server
resource "aws_eip" "jenkins_eip" {
  instance = aws_instance.jenkins_server.id
  domain   = "vpc"
  
  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-jenkins-eip"
      Environment = var.environment
      Service     = "jenkins"
    }
  )
}

# Simple EC2 approach - no ALB needed 