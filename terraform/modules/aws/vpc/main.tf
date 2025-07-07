# AWS VPC Module
# Creates a VPC with public, private, and intra-service subnets across multiple AZs

locals {
  # Limit to 3 AZs to ensure we have enough IP space
  max_azs = min(3, length(data.aws_availability_zones.available.names))
  azs = slice(data.aws_availability_zones.available.names, 0, local.max_azs)
  
  # Calculate subnet CIDRs
  public_subnet_cidrs  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i + length(local.azs))]
  intra_subnet_cidrs   = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i + 2 * length(local.azs))]
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-vpc"
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-igw"
    }
  )
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(local.azs)
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-public-${local.azs[count.index]}"
      Type = "Public"
      "kubernetes.io/role/elb" = "1"
    },
    # Add tags for each EKS cluster
    { for cluster in var.eks_cluster_names : "kubernetes.io/cluster/${cluster}" => "shared" }
  )
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(local.azs)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-private-${local.azs[count.index]}"
      Type = "Private"
      "kubernetes.io/role/internal-elb" = "1"
    },
    # Add tags for each EKS cluster
    { for cluster in var.eks_cluster_names : "kubernetes.io/cluster/${cluster}" => "shared" }
  )
}

# Intra-Service Subnets (for internal services like RDS)
resource "aws_subnet" "intra" {
  count = length(local.azs)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.intra_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-intra-${local.azs[count.index]}"
      Type = "Intra"
    }
  )
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(local.azs)) : 0
  domain = "vpc"
  
  tags = merge(
    var.common_tags,
    {
      Name = var.single_nat_gateway ? "${var.environment}-nat-eip" : "${var.environment}-nat-eip-${local.azs[count.index]}"
    }
  )
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(local.azs)) : 0
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[var.single_nat_gateway ? 0 : count.index].id
  
  tags = merge(
    var.common_tags,
    {
      Name = var.single_nat_gateway ? "${var.environment}-nat" : "${var.environment}-nat-${local.azs[count.index]}"
    }
  )
  
  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-public-rt"
    }
  )
}

# Private Route Tables (one per AZ for HA)
resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.main.id
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-private-rt-${local.azs[count.index]}"
    }
  )
}

# Intra Route Table
resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-intra-rt"
    }
  )
}

# Routes
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? length(local.azs) : 0
  
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(local.azs)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(local.azs)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "intra" {
  count = length(local.azs)
  
  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra.id
}

# VPC Flow Logs
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0
  
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-vpc-flow-logs"
    }
  )
}

# CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  name              = "/aws/vpc/${var.environment}"
  retention_in_days = 30
  
  tags = var.common_tags
  
  lifecycle {
    ignore_changes = [name]
  }
}

# IAM Role for Flow Logs
resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  name = "${var.environment}-vpc-flow-logs-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
  
  tags = var.common_tags
}

# IAM Role Policy for Flow Logs
resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  name = "${var.environment}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}