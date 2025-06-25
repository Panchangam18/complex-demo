#!/bin/bash

# AWS Subnet Cleanup Script
# Cleans up AWS resources that might be preventing subnet deletion

set -e

SUBNET_ID=${1:-subnet-0fb0a0c3e0cd4e42e}
AWS_REGION=${AWS_REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-sandbox-permanent}

echo "🔍 Investigating AWS subnet dependencies..."
echo "  - Subnet ID: $SUBNET_ID"
echo "  - AWS Region: $AWS_REGION"
echo "  - AWS Profile: $AWS_PROFILE"

# Function to run AWS CLI with proper error handling
run_aws() {
    AWS_PROFILE=$AWS_PROFILE aws --region $AWS_REGION "$@" 2>/dev/null || true
}

# 1. Check and delete network interfaces
echo "🔧 Checking network interfaces in subnet $SUBNET_ID..."
run_aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=$SUBNET_ID" --query "NetworkInterfaces[*].{Id:NetworkInterfaceId,Description:Description,Status:Status}" --output text | while read -r eni_id description status; do
    if [[ -n "$eni_id" && "$eni_id" != "None" ]]; then
        echo "  Found ENI: $eni_id ($description) - Status: $status"
        if [[ "$status" == "in-use" ]]; then
            echo "  Detaching ENI: $eni_id"
            run_aws ec2 detach-network-interface --network-interface-id $eni_id --force
            sleep 5
        fi
        echo "  Deleting ENI: $eni_id"
        run_aws ec2 delete-network-interface --network-interface-id $eni_id
    fi
done

# 2. Check and delete NAT gateways
echo "🔧 Checking NAT gateways in subnet $SUBNET_ID..."
run_aws ec2 describe-nat-gateways --filter "Name=subnet-id,Values=$SUBNET_ID" --query "NatGateways[?State=='available'].NatGatewayId" --output text | while read -r nat_id; do
    if [[ -n "$nat_id" && "$nat_id" != "None" ]]; then
        echo "  Deleting NAT gateway: $nat_id"
        run_aws ec2 delete-nat-gateway --nat-gateway-id $nat_id
        echo "  Waiting for NAT gateway to be deleted..."
        sleep 10
    fi
done

# 3. Check and delete load balancers
echo "🔧 Checking load balancers using subnet $SUBNET_ID..."
run_aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(AvailabilityZones[].SubnetId, '$SUBNET_ID')].LoadBalancerArn" --output text | while read -r lb_arn; do
    if [[ -n "$lb_arn" && "$lb_arn" != "None" ]]; then
        echo "  Deleting load balancer: $lb_arn"
        run_aws elbv2 delete-load-balancer --load-balancer-arn $lb_arn
    fi
done

# 4. Check and terminate instances
echo "🔧 Checking EC2 instances in subnet $SUBNET_ID..."
run_aws ec2 describe-instances --filters "Name=subnet-id,Values=$SUBNET_ID" --query "Reservations[*].Instances[?State.Name!='terminated'].{InstanceId:InstanceId,State:State.Name}" --output text | while read -r instance_id state; do
    if [[ -n "$instance_id" && "$instance_id" != "None" ]]; then
        echo "  Found instance: $instance_id (State: $state)"
        if [[ "$state" != "terminated" ]]; then
            echo "  Terminating instance: $instance_id"
            run_aws ec2 terminate-instances --instance-ids $instance_id
        fi
    fi
done

# 5. Check and delete VPC endpoints
echo "🔧 Checking VPC endpoints in subnet $SUBNET_ID..."
run_aws ec2 describe-vpc-endpoints --filters "Name=subnet-id,Values=$SUBNET_ID" --query "VpcEndpoints[].VpcEndpointId" --output text | while read -r endpoint_id; do
    if [[ -n "$endpoint_id" && "$endpoint_id" != "None" ]]; then
        echo "  Deleting VPC endpoint: $endpoint_id"
        run_aws ec2 delete-vpc-endpoint --vpc-endpoint-id $endpoint_id
    fi
done

# 6. Check and delete RDS subnet groups (if they reference this subnet)
echo "🔧 Checking RDS subnet groups..."
run_aws rds describe-db-subnet-groups --query "DBSubnetGroups[?contains(Subnets[].SubnetIdentifier, '$SUBNET_ID')].DBSubnetGroupName" --output text | while read -r sg_name; do
    if [[ -n "$sg_name" && "$sg_name" != "None" ]]; then
        echo "  Found RDS subnet group using this subnet: $sg_name"
        echo "  Note: You may need to delete RDS instances using this subnet group first"
    fi
done

# 7. Check Lambda functions
echo "🔧 Checking Lambda functions in subnet $SUBNET_ID..."
run_aws lambda list-functions --query "Functions[?VpcConfig.SubnetIds && contains(VpcConfig.SubnetIds, '$SUBNET_ID')].FunctionName" --output text | while read -r func_name; do
    if [[ -n "$func_name" && "$func_name" != "None" ]]; then
        echo "  Found Lambda function using subnet: $func_name"
        echo "  Removing VPC configuration from Lambda: $func_name"
        run_aws lambda update-function-configuration --function-name $func_name --vpc-config '{}'
    fi
done

echo "✅ AWS subnet cleanup completed!"
echo "🚀 You can now try running the destroy command again" 