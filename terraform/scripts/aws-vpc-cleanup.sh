#!/bin/bash

# AWS VPC Cleanup Script
# Cleans up all AWS VPC dependencies that might be preventing VPC deletion

set -e

VPC_ID=${1:-vpc-03b93711487e5c72f}
AWS_REGION=${AWS_REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-sandbox-permanent}

echo "🔍 Investigating AWS VPC dependencies..."
echo "  - VPC ID: $VPC_ID"
echo "  - AWS Region: $AWS_REGION"
echo "  - AWS Profile: $AWS_PROFILE"

# Function to run AWS CLI with proper error handling
run_aws() {
    AWS_PROFILE=$AWS_PROFILE aws --region $AWS_REGION "$@" 2>/dev/null || true
}

# 1. Delete all non-default security groups
echo "🔧 Deleting custom security groups in VPC..."
run_aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text | tr '\t' '\n' | while read -r sg_id; do
    if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
        echo "  Deleting security group: $sg_id"
        run_aws ec2 delete-security-group --group-id $sg_id
    fi
done

# 2. Delete custom route tables (not main route table)
echo "🔧 Deleting custom route tables..."
run_aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[?Associations[0].Main!=true].RouteTableId" --output text | tr '\t' '\n' | while read -r rt_id; do
    if [[ -n "$rt_id" && "$rt_id" != "None" ]]; then
        echo "  Deleting route table: $rt_id"
        # First disassociate any subnet associations
        run_aws ec2 describe-route-tables --route-table-ids $rt_id --query "RouteTables[0].Associations[?Main!=true].RouteTableAssociationId" --output text | tr '\t' '\n' | while read -r assoc_id; do
            if [[ -n "$assoc_id" && "$assoc_id" != "None" ]]; then
                echo "    Disassociating route table association: $assoc_id"
                run_aws ec2 disassociate-route-table --association-id $assoc_id
            fi
        done
        run_aws ec2 delete-route-table --route-table-id $rt_id
    fi
done

# 3. Delete custom network ACLs (not default)
echo "🔧 Deleting custom network ACLs..."
run_aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[?IsDefault!=true].NetworkAclId" --output text | tr '\t' '\n' | while read -r acl_id; do
    if [[ -n "$acl_id" && "$acl_id" != "None" ]]; then
        echo "  Deleting network ACL: $acl_id"
        run_aws ec2 delete-network-acl --network-acl-id $acl_id
    fi
done

# 4. Delete VPC endpoints
echo "🔧 Deleting VPC endpoints..."
run_aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[].VpcEndpointId" --output text | tr '\t' '\n' | while read -r endpoint_id; do
    if [[ -n "$endpoint_id" && "$endpoint_id" != "None" ]]; then
        echo "  Deleting VPC endpoint: $endpoint_id"
        run_aws ec2 delete-vpc-endpoint --vpc-endpoint-id $endpoint_id
    fi
done

# 5. Detach and delete internet gateways
echo "🔧 Detaching and deleting internet gateways..."
run_aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[].InternetGatewayId" --output text | tr '\t' '\n' | while read -r igw_id; do
    if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
        echo "  Detaching internet gateway: $igw_id from VPC: $VPC_ID"
        run_aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $VPC_ID
        echo "  Deleting internet gateway: $igw_id"
        run_aws ec2 delete-internet-gateway --internet-gateway-id $igw_id
    fi
done

# 6. Delete VPN gateways
echo "🔧 Deleting VPN gateways..."
run_aws ec2 describe-vpn-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "VpnGateways[].VpnGatewayId" --output text | tr '\t' '\n' | while read -r vgw_id; do
    if [[ -n "$vgw_id" && "$vgw_id" != "None" ]]; then
        echo "  Detaching VPN gateway: $vgw_id from VPC: $VPC_ID"
        run_aws ec2 detach-vpn-gateway --vpn-gateway-id $vgw_id --vpc-id $VPC_ID
        echo "  Deleting VPN gateway: $vgw_id"
        run_aws ec2 delete-vpn-gateway --vpn-gateway-id $vgw_id
    fi
done

# 7. Delete any remaining network interfaces
echo "🔧 Deleting remaining network interfaces in VPC..."
run_aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[].NetworkInterfaceId" --output text | tr '\t' '\n' | while read -r eni_id; do
    if [[ -n "$eni_id" && "$eni_id" != "None" ]]; then
        echo "  Deleting network interface: $eni_id"
        # Try to detach first if attached
        run_aws ec2 detach-network-interface --network-interface-id $eni_id --force
        sleep 2
        run_aws ec2 delete-network-interface --network-interface-id $eni_id
    fi
done

# 8. Delete DHCP options sets (if custom)
echo "🔧 Checking DHCP options..."
dhcp_id=$(run_aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].DhcpOptionsId" --output text)
if [[ -n "$dhcp_id" && "$dhcp_id" != "None" && "$dhcp_id" != "default" ]]; then
    echo "  Found custom DHCP options: $dhcp_id"
    # Associate default DHCP options first
    run_aws ec2 associate-dhcp-options --dhcp-options-id default --vpc-id $VPC_ID
    echo "  Deleting custom DHCP options: $dhcp_id"
    run_aws ec2 delete-dhcp-options --dhcp-options-id $dhcp_id
fi

echo "✅ AWS VPC cleanup completed!"
echo "🚀 VPC $VPC_ID should now be ready for deletion" 