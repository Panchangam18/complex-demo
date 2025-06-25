#!/bin/bash

# Import all existing resources that are causing conflicts

echo "Importing all existing AWS and GCP resources..."

# ---------------------------------------
# AWS VPC core networking
# ---------------------------------------

# Internet-Gateway already attached to VPC – import so Terraform doesn't try to recreate
echo "Importing Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-03b93711487e5c72f" --query 'InternetGateways[0].InternetGatewayId' --output text --region us-east-2)
if [[ "$IGW_ID" != "None" && -n "$IGW_ID" ]]; then
  terragrunt import module.aws_vpc.aws_internet_gateway.main $IGW_ID 2>/dev/null || echo "IGW already imported"
else
  echo "⚠ Could not auto-detect IGW – please check manually"
fi

# CloudWatch log group for VPC flow-logs
echo "Importing CloudWatch log group for VPC flow logs..."
terragrunt import 'module.aws_vpc.aws_cloudwatch_log_group.flow_logs[0]' /aws/vpc/dev 2>/dev/null || echo "Log group already imported"

# AWS KMS Alias
terragrunt import 'module.aws_eks.aws_kms_alias.eks[0]' alias/dev-eks-us-east-2-eks 2>/dev/null || echo "KMS alias already imported"

# AWS CloudWatch Log Group
terragrunt import module.aws_eks.aws_cloudwatch_log_group.eks /aws/eks/dev-eks-us-east-2/cluster 2>/dev/null || echo "Log group already imported"

# AWS IAM Roles
terragrunt import module.aws_eks.aws_iam_role.eks_cluster dev-eks-us-east-2-eks-cluster-role 2>/dev/null || echo "EKS cluster role already imported"
terragrunt import module.aws_eks.aws_iam_role.eks_nodes dev-eks-us-east-2-eks-node-role 2>/dev/null || echo "EKS node role already imported"
terragrunt import module.aws_rds.aws_iam_role.monitoring[0] dev-postgres-us-east-2-monitoring-role 2>/dev/null || echo "RDS monitoring role already imported"
terragrunt import 'module.aws_vpc.aws_iam_role.flow_logs[0]' dev-vpc-flow-logs-role 2>/dev/null || echo "VPC flow logs role already imported"

# AWS VPC Subnets - get subnet IDs first (names now follow dev-<type>-<az>)
echo "Getting subnet IDs..."

PUBLIC_SUBNET_0=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-public-us-east-2a" --query 'Subnets[0].SubnetId' --output text --region us-east-2)
PUBLIC_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-public-us-east-2b" --query 'Subnets[0].SubnetId' --output text --region us-east-2)
PUBLIC_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-public-us-east-2c" --query 'Subnets[0].SubnetId' --output text --region us-east-2)

PRIVATE_SUBNET_0=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-private-us-east-2a" --query 'Subnets[0].SubnetId' --output text --region us-east-2)
PRIVATE_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-private-us-east-2b" --query 'Subnets[0].SubnetId' --output text --region us-east-2)
PRIVATE_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-private-us-east-2c" --query 'Subnets[0].SubnetId' --output text --region us-east-2)

INTRA_SUBNET_0=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-intra-us-east-2a" --query 'Subnets[0].SubnetId' --output text --region us-east-2)
INTRA_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-intra-us-east-2b" --query 'Subnets[0].SubnetId' --output text --region us-east-2)
INTRA_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-intra-us-east-2c" --query 'Subnets[0].SubnetId' --output text --region us-east-2)

# Helper to import subnet if ID found
import_subnet() {
  local addr=$1
  local id=$2
  local label=$3
  if [[ "$id" != "None" && -n "$id" ]]; then
    terragrunt import "$addr" "$id" 2>/dev/null || echo "$label already imported"
  else
    echo "⚠ $label not found"
  fi
}

# Import subnets if they exist
import_subnet 'module.aws_vpc.aws_subnet.public[0]'  "$PUBLIC_SUBNET_0"  "Public subnet 0"
import_subnet 'module.aws_vpc.aws_subnet.public[1]'  "$PUBLIC_SUBNET_1"  "Public subnet 1"
import_subnet 'module.aws_vpc.aws_subnet.public[2]'  "$PUBLIC_SUBNET_2"  "Public subnet 2"

import_subnet 'module.aws_vpc.aws_subnet.private[0]' "$PRIVATE_SUBNET_0" "Private subnet 0"
import_subnet 'module.aws_vpc.aws_subnet.private[1]' "$PRIVATE_SUBNET_1" "Private subnet 1"
import_subnet 'module.aws_vpc.aws_subnet.private[2]' "$PRIVATE_SUBNET_2" "Private subnet 2"

import_subnet 'module.aws_vpc.aws_subnet.intra[0]'   "$INTRA_SUBNET_0"  "Intra subnet 0"
import_subnet 'module.aws_vpc.aws_subnet.intra[1]'   "$INTRA_SUBNET_1"  "Intra subnet 1"
import_subnet 'module.aws_vpc.aws_subnet.intra[2]'   "$INTRA_SUBNET_2"  "Intra subnet 2"

# AWS VPC Security Groups
SG_EKS_CLUSTER=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=dev-eks-us-east-2-cluster-sg" --query 'SecurityGroups[0].GroupId' --output text --region us-east-2)
SG_EKS_PODS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=dev-eks-us-east-2-pods-sg" --query 'SecurityGroups[0].GroupId' --output text --region us-east-2)

if [ "$SG_EKS_CLUSTER" != "None" ] && [ -n "$SG_EKS_CLUSTER" ]; then
    terragrunt import module.aws_eks.aws_security_group.eks_cluster $SG_EKS_CLUSTER 2>/dev/null || echo "EKS cluster SG already imported"
fi
if [ "$SG_EKS_PODS" != "None" ] && [ -n "$SG_EKS_PODS" ]; then
    terragrunt import module.aws_eks.aws_security_group.eks_pods $SG_EKS_PODS 2>/dev/null || echo "EKS pods SG already imported"
fi

# AWS S3 buckets
for bucket in "dev-thanos-us-east-2" "dev-app-assets-us-east-2" "dev-elasticsearch-us-east-2"; do
    aws s3api head-bucket --bucket $bucket 2>/dev/null
    if [ $? -eq 0 ]; then
        case $bucket in
            *thanos*) key="thanos" ;;
            *app-assets*) key="app_assets" ;;
            *elasticsearch*) key="elasticsearch" ;;
        esac
        terragrunt import "module.aws_s3.aws_s3_bucket.buckets[\"$key\"]" $bucket 2>/dev/null || echo "S3 bucket $bucket already imported"
    fi
done

echo "Import process completed!"