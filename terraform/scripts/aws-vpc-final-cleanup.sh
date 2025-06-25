#!/bin/bash

# AWS VPC Final Cleanup Script
# Handles default security group rules and remaining subtle dependencies

set -e

VPC_ID=${1:-vpc-03b93711487e5c72f}
AWS_REGION=${AWS_REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-sandbox-permanent}

echo "🎯 FINAL VPC CLEANUP for $VPC_ID"
echo "================================="

# Function to run AWS CLI with proper error handling
run_aws() {
    AWS_PROFILE=$AWS_PROFILE aws --region $AWS_REGION "$@" 2>/dev/null || true
}

# 1. Reset default security group to default rules
echo "🔧 Resetting default security group rules..."
default_sg=$(run_aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

if [[ -n "$default_sg" && "$default_sg" != "None" ]]; then
    echo "  Default security group: $default_sg"
    
    # Remove all inbound rules
    echo "  Removing all inbound rules..."
    run_aws ec2 describe-security-groups --group-ids $default_sg --query "SecurityGroups[0].IpPermissions" --output json > /tmp/inbound_rules.json
    if [[ -s /tmp/inbound_rules.json && "$(cat /tmp/inbound_rules.json)" != "[]" ]]; then
        run_aws ec2 revoke-security-group-ingress --group-id $default_sg --ip-permissions file:///tmp/inbound_rules.json
    fi
    
    # Remove all outbound rules except the default allow-all
    echo "  Removing custom outbound rules..."
    run_aws ec2 describe-security-groups --group-ids $default_sg --query "SecurityGroups[0].IpPermissionsEgress[?!(IpProtocol=='-1' && length(IpRanges)==`1` && IpRanges[0].CidrIp=='0.0.0.0/0')]" --output json > /tmp/outbound_rules.json
    if [[ -s /tmp/outbound_rules.json && "$(cat /tmp/outbound_rules.json)" != "[]" ]]; then
        run_aws ec2 revoke-security-group-egress --group-id $default_sg --ip-permissions file:///tmp/outbound_rules.json
    fi
    
    # Clean up temp files
    rm -f /tmp/inbound_rules.json /tmp/outbound_rules.json
fi

# 2. Force delete any remaining network interfaces
echo "🔧 Force deleting any remaining network interfaces..."
run_aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[].NetworkInterfaceId" --output text | tr '\t' '\n' | while read -r eni_id; do
    if [[ -n "$eni_id" && "$eni_id" != "None" ]]; then
        echo "  Force deleting ENI: $eni_id"
        run_aws ec2 detach-network-interface --network-interface-id $eni_id --force
        sleep 2
        run_aws ec2 delete-network-interface --network-interface-id $eni_id
    fi
done

# 3. Delete any VPC flow logs
echo "🔧 Deleting VPC flow logs..."
run_aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" --query "FlowLogs[].FlowLogId" --output text | tr '\t' '\n' | while read -r flow_log_id; do
    if [[ -n "$flow_log_id" && "$flow_log_id" != "None" ]]; then
        echo "  Deleting flow log: $flow_log_id"
        run_aws ec2 delete-flow-logs --flow-log-ids $flow_log_id
    fi
done

# 4. Check for any customer gateways
echo "🔧 Checking for customer gateways..."
run_aws ec2 describe-customer-gateways --query "CustomerGateways[?State=='available'].CustomerGatewayId" --output text | tr '\t' '\n' | while read -r cgw_id; do
    if [[ -n "$cgw_id" && "$cgw_id" != "None" ]]; then
        echo "  Found customer gateway: $cgw_id"
        # Check if it's associated with this VPC through VPN connections
        vpn_connections=$(run_aws ec2 describe-vpn-connections --filters "Name=customer-gateway-id,Values=$cgw_id" "Name=vpc-id,Values=$VPC_ID" --query "VpnConnections[].VpnConnectionId" --output text)
        if [[ -n "$vpn_connections" && "$vpn_connections" != "None" ]]; then
            echo "  Customer gateway $cgw_id is associated with this VPC via VPN connections"
        fi
    fi
done

# 5. Wait a moment for AWS to process deletions
echo "🔧 Waiting for AWS to process deletions..."
sleep 10

# 6. Final attempt to delete VPC
echo "🎯 Attempting final VPC deletion..."
if run_aws ec2 delete-vpc --vpc-id $VPC_ID; then
    echo "✅ VPC $VPC_ID successfully deleted!"
else
    echo "❌ VPC $VPC_ID still has dependencies"
    echo ""
    echo "🔍 Remaining dependencies check:"
    echo "--------------------------------"
    
    # Check what's still there
    echo "Instances:"
    run_aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[*].Instances[*].InstanceId" --output text
    
    echo "Network Interfaces:"
    run_aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text
    
    echo "Subnets:"
    run_aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text
    
    echo "Security Groups:"
    run_aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[*].GroupId" --output text
    
    echo "Route Tables:"
    run_aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[*].RouteTableId" --output text
    
    echo "Network ACLs:"
    run_aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[*].NetworkAclId" --output text
fi

echo "🎯 Final cleanup completed!" 