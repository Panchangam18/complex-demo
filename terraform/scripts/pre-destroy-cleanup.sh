#!/bin/bash

# Pre-Destroy Cleanup Script
# Run this before 'make destroy' to ensure no dependencies block the destruction

set -e

echo "🧹 Starting pre-destroy cleanup..."

# Set variables
PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-forge-demo-463617}
AWS_REGION=${AWS_REGION:-us-east-2}
ENV=${ENV:-dev}

echo "📋 Configuration:"
echo "  - GCP Project: $PROJECT_ID"
echo "  - AWS Region: $AWS_REGION"
echo "  - Environment: $ENV"

# 1. Delete all GKE clusters
echo "🔧 Deleting GKE clusters..."
gcloud container clusters list --project=$PROJECT_ID --format="value(name,location)" | while read cluster_name location; do
    if [[ $cluster_name == *"$ENV"* ]]; then
        echo "  Deleting GKE cluster: $cluster_name in $location"
        gcloud container clusters delete $cluster_name --location=$location --project=$PROJECT_ID --quiet
    fi
done

# 2. Delete all EKS clusters
echo "🔧 Deleting EKS clusters..."
aws eks list-clusters --region $AWS_REGION --query "clusters[]" --output text | while read cluster_name; do
    if [[ $cluster_name == *"$ENV"* ]]; then
        echo "  Deleting EKS cluster: $cluster_name"
        aws eks delete-cluster --name $cluster_name --region $AWS_REGION
        
        # Wait for cluster to be deleted
        echo "  Waiting for EKS cluster deletion to complete..."
        aws eks wait cluster-deleted --name $cluster_name --region $AWS_REGION
        
        # Delete associated node groups first if they exist
        aws eks list-nodegroups --cluster-name $cluster_name --region $AWS_REGION --query "nodegroups[]" --output text 2>/dev/null | while read nodegroup_name; do
            echo "  Deleting node group: $nodegroup_name"
            aws eks delete-nodegroup --cluster-name $cluster_name --nodegroup-name $nodegroup_name --region $AWS_REGION
            aws eks wait nodegroup-deleted --cluster-name $cluster_name --nodegroup-name $nodegroup_name --region $AWS_REGION
        done
    fi
done

# 3. Delete GCP firewall rules that might be auto-created by GKE
echo "🔧 Cleaning up GCP firewall rules..."
gcloud compute firewall-rules list --project=$PROJECT_ID --filter="network:$ENV-vpc" --format="value(name)" | while read rule_name; do
    echo "  Deleting firewall rule: $rule_name"
    gcloud compute firewall-rules delete $rule_name --project=$PROJECT_ID --quiet
done

# 3.5. Delete GCP subnetworks that might be blocking VPC deletion
echo "🔧 Cleaning up GCP subnetworks..."
gcloud compute networks subnets list --project=$PROJECT_ID --filter="network:$ENV-vpc" --format="value(name,region)" | while read subnet_name region; do
    if [[ -n "$subnet_name" && -n "$region" ]]; then
        echo "  Deleting subnetwork: $subnet_name in region: $region"
        gcloud compute networks subnets delete $subnet_name --region=$region --project=$PROJECT_ID --quiet
    fi
done

# 4. Delete any load balancers that might be using subnets
echo "🔧 Cleaning up AWS load balancers..."
aws elbv2 describe-load-balancers --region $AWS_REGION --query "LoadBalancers[?contains(LoadBalancerName, '$ENV')].LoadBalancerArn" --output text | tr '\t' '\n' | while read -r lb_arn; do
    if [[ -n "$lb_arn" && "$lb_arn" != "None" ]]; then
        echo "  Deleting load balancer: $lb_arn"
        aws elbv2 delete-load-balancer --load-balancer-arn $lb_arn --region $AWS_REGION
    fi
done

# 5. Delete NAT gateways
echo "🔧 Cleaning up NAT gateways..."
aws ec2 describe-nat-gateways --region $AWS_REGION --filter "Name=tag:environment,Values=$ENV" --query "NatGateways[?State=='available'].NatGatewayId" --output text | tr '\t' '\n' | while read -r nat_gateway_id; do
    if [[ -n "$nat_gateway_id" && "$nat_gateway_id" != "None" ]]; then
        echo "  Deleting NAT gateway: $nat_gateway_id"
        aws ec2 delete-nat-gateway --nat-gateway-id $nat_gateway_id --region $AWS_REGION
    fi
done

# 6. Release Elastic IPs before detaching internet gateways
echo "🔧 Releasing Elastic IPs..."
# Release all Elastic IPs associated with NAT gateways first
aws ec2 describe-addresses --region $AWS_REGION --query "Addresses[?AssociationId].AllocationId" --output text | tr '\t' '\n' | while read -r alloc_id; do
    if [[ -n "$alloc_id" && "$alloc_id" != "None" ]]; then
        echo "  Releasing Elastic IP: $alloc_id"
        aws ec2 release-address --allocation-id $alloc_id --region $AWS_REGION
    fi
done

# Wait a moment for the releases to process
sleep 5

# 7. Delete internet gateways attached to VPC
echo "🔧 Cleaning up internet gateways..."
aws ec2 describe-internet-gateways --region $AWS_REGION --filters "Name=tag:environment,Values=$ENV" --query "InternetGateways[].InternetGatewayId" --output text | tr '\t' '\n' | while read -r igw_id; do
    if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
        # Get VPC ID attached to this IGW
        vpc_id=$(aws ec2 describe-internet-gateways --region $AWS_REGION --internet-gateway-ids $igw_id --query "InternetGateways[0].Attachments[0].VpcId" --output text)
        if [[ $vpc_id != "None" && $vpc_id != "" ]]; then
            echo "  Detaching IGW $igw_id from VPC $vpc_id"
            aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id --region $AWS_REGION
        fi
        echo "  Deleting internet gateway: $igw_id"
        aws ec2 delete-internet-gateway --internet-gateway-id $igw_id --region $AWS_REGION
    fi
done

# 8. Run comprehensive AWS subnet cleanup for any remaining subnet dependencies
echo "🔧 Running comprehensive AWS subnet cleanup..."
if [[ -f ./scripts/aws-subnet-cleanup.sh ]]; then
    # Find all subnets in the environment and clean them up
    aws ec2 describe-subnets --region $AWS_REGION --filters "Name=tag:environment,Values=$ENV" --query "Subnets[].SubnetId" --output text | tr '\t' '\n' | while read -r subnet_id; do
        if [[ -n "$subnet_id" && "$subnet_id" != "None" ]]; then
            echo "  Cleaning up subnet dependencies: $subnet_id"
            AWS_PROFILE=$AWS_PROFILE AWS_REGION=$AWS_REGION ./scripts/aws-subnet-cleanup.sh $subnet_id
        fi
    done
fi

# 9. Run comprehensive AWS VPC cleanup for any remaining VPC dependencies
echo "🔧 Running comprehensive AWS VPC cleanup..."
if [[ -f ./scripts/aws-vpc-cleanup.sh ]]; then
    # Find all VPCs in the environment and clean them up
    aws ec2 describe-vpcs --region $AWS_REGION --filters "Name=tag:environment,Values=$ENV" --query "Vpcs[].VpcId" --output text | tr '\t' '\n' | while read -r vpc_id; do
        if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
            echo "  Cleaning up VPC dependencies: $vpc_id"
            AWS_PROFILE=$AWS_PROFILE AWS_REGION=$AWS_REGION ./scripts/aws-vpc-cleanup.sh $vpc_id
        fi
    done
fi

echo "✅ Pre-destroy cleanup completed!"
echo "🚀 You can now run: make destroy AWS_PROFILE=sandbox-permanent ENV=$ENV REGION=$AWS_REGION" 