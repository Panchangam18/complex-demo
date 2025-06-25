#!/bin/bash

# AWS VPC Investigation Script
# Investigates all possible dependencies that might be preventing VPC deletion

set -e

VPC_ID=${1:-vpc-03b93711487e5c72f}
AWS_REGION=${AWS_REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-sandbox-permanent}

echo "🔍 COMPREHENSIVE VPC DEPENDENCY INVESTIGATION"
echo "=============================================="
echo "  - VPC ID: $VPC_ID"
echo "  - AWS Region: $AWS_REGION"
echo "  - AWS Profile: $AWS_PROFILE"
echo ""

# Function to run AWS CLI with proper error handling
run_aws() {
    AWS_PROFILE=$AWS_PROFILE aws --region $AWS_REGION "$@" 2>/dev/null || echo "No results"
}

echo "1. 🖥️  INSTANCES in VPC:"
run_aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[*].Instances[*].{InstanceId:InstanceId,State:State.Name,SubnetId:SubnetId}" --output table

echo -e "\n2. 🔌 NETWORK INTERFACES in VPC:"
run_aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[*].{Id:NetworkInterfaceId,Description:Description,Status:Status,Type:InterfaceType}" --output table

echo -e "\n3. 🛡️  SECURITY GROUPS in VPC:"
run_aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,IsDefault:GroupName}" --output table

echo -e "\n4. 🛣️  ROUTE TABLES in VPC:"
run_aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[*].{RouteTableId:RouteTableId,Main:Associations[0].Main,AssociationCount:length(Associations)}" --output table

echo -e "\n5. 🌐 INTERNET GATEWAYS attached to VPC:"
run_aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].{InternetGatewayId:InternetGatewayId,State:Attachments[0].State}" --output table

echo -e "\n6. 🔗 VPC PEERING CONNECTIONS:"
run_aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$VPC_ID" --query "VpcPeeringConnections[*].{VpcPeeringConnectionId:VpcPeeringConnectionId,Status:Status.Code}" --output table
run_aws ec2 describe-vpc-peering-connections --filters "Name=accepter-vpc-info.vpc-id,Values=$VPC_ID" --query "VpcPeeringConnections[*].{VpcPeeringConnectionId:VpcPeeringConnectionId,Status:Status.Code}" --output table

echo -e "\n7. 🔄 NAT GATEWAYS in VPC:"
run_aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].{NatGatewayId:NatGatewayId,State:State,SubnetId:SubnetId}" --output table

echo -e "\n8. 📡 VPC ENDPOINTS:"
run_aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].{VpcEndpointId:VpcEndpointId,ServiceName:ServiceName,State:State}" --output table

echo -e "\n9. 🔒 NETWORK ACLs in VPC:"
run_aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[*].{NetworkAclId:NetworkAclId,IsDefault:IsDefault,AssociationCount:length(Associations)}" --output table

echo -e "\n10. 🏠 SUBNETS in VPC:"
run_aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].{SubnetId:SubnetId,State:State,AvailabilityZone:AvailabilityZone}" --output table

echo -e "\n11. 🚪 VPN GATEWAYS attached to VPC:"
run_aws ec2 describe-vpn-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "VpnGateways[*].{VpnGatewayId:VpnGatewayId,State:State}" --output table

echo -e "\n12. 🌉 TRANSIT GATEWAY ATTACHMENTS:"
run_aws ec2 describe-transit-gateway-attachments --filters "Name=vpc-id,Values=$VPC_ID" --query "TransitGatewayAttachments[*].{TransitGatewayAttachmentId:TransitGatewayAttachmentId,State:State}" --output table

echo -e "\n13. 📊 VPC FLOW LOGS:"
run_aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" --query "FlowLogs[*].{FlowLogId:FlowLogId,FlowLogStatus:FlowLogStatus}" --output table

echo -e "\n14. 🔧 DHCP OPTIONS SETS:"
dhcp_id=$(run_aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].DhcpOptionsId" --output text)
echo "DHCP Options ID: $dhcp_id"

echo -e "\n15. 🎯 DEFAULT SECURITY GROUP RULES:"
default_sg=$(run_aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)
echo "Default Security Group: $default_sg"
if [[ "$default_sg" != "None" && "$default_sg" != "" ]]; then
    run_aws ec2 describe-security-groups --group-ids $default_sg --query "SecurityGroups[0].{InboundRules:IpPermissions,OutboundRules:IpPermissionsEgress}" --output table
fi

echo -e "\n=============================================="
echo "🎯 INVESTIGATION COMPLETE"
echo "==============================================" 