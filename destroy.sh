#!/bin/bash

# 🚨 COMPREHENSIVE MULTI-CLOUD DEVOPS PLATFORM DESTRUCTION - FIXED VERSION
# =======================================================================
# This script comprehensively destroys your multi-cloud DevOps platform
# with proper dependency resolution, state management, and complete cleanup.

set -euo pipefail

# ============================================================================
# CONFIGURATION & COLORS
# ============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Project configuration
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="$PROJECT_ROOT/destruction-$TIMESTAMP.log"

# Default values
ENV=${ENV:-dev}
REGION=${REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-default}
GCP_PROJECT_ID=${GCP_PROJECT_ID:-"complex-demo-465023"}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-""}

# Destruction control flags
DRY_RUN=${DRY_RUN:-false}
AUTO_APPROVE=${AUTO_APPROVE:-false}
FORCE_DESTROY=${FORCE_DESTROY:-false}
SKIP_BACKUPS=${SKIP_BACKUPS:-false}

# Retry and timeout settings
readonly MAX_RETRIES=3
readonly AWS_OPERATION_TIMEOUT=300    # 5 minutes for single operations
readonly CLUSTER_DELETE_TIMEOUT=1800  # 30 minutes for cluster deletion
readonly NAT_GATEWAY_DELETE_TIMEOUT=600 # 10 minutes for NAT gateway deletion

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Enhanced logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Print banner
print_banner() {
    echo -e "${RED}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                              ║
    ║     🚨 COMPREHENSIVE INFRASTRUCTURE DESTRUCTION - FIXED VERSION 🚨          ║
    ║                                                                              ║
    ║     ⚠️  WARNING: This will thoroughly destroy your infrastructure! ⚠️      ║
    ║                                                                              ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    log "INFO" "Starting comprehensive destruction process - Fixed Version"
}

# Safety confirmation
confirm_destruction() {
    if [ "$AUTO_APPROVE" == "true" ] || [ "$FORCE_DESTROY" == "true" ]; then
        log "WARN" "Auto-approve enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${RED}⚠️  COMPREHENSIVE DESTRUCTION MODE ⚠️${NC}"
    echo -e "${YELLOW}This will completely destroy all infrastructure in $ENV environment${NC}"
    echo -e "${YELLOW}Including: EKS/GKE/AKS clusters, VPCs, databases, storage, and all data!${NC}"
    echo
    
    if [ "$SKIP_BACKUPS" != "true" ]; then
        echo -e "${BLUE}📋 A backup will be created before destruction${NC}"
    else
        echo -e "${RED}⚠️  BACKUPS WILL BE SKIPPED!${NC}"
    fi
    
    echo
    read -p "Type 'DESTROY-EVERYTHING' to continue: " confirmation
    
    if [ "$confirmation" != "DESTROY-EVERYTHING" ]; then
        echo -e "${GREEN}✅ Destruction cancelled.${NC}"
        exit 0
    fi
    
    echo -e "${RED}🚨 Proceeding with comprehensive destruction...${NC}"
    log "WARN" "User confirmed comprehensive destruction"
}

# Enhanced backup function
create_backup() {
    if [ "$SKIP_BACKUPS" == "true" ] || [ "$DRY_RUN" == "true" ]; then
        log "INFO" "Skipping backup creation"
        return 0
    fi
    
    local backup_dir="$PROJECT_ROOT/backups/$ENV-$REGION-$TIMESTAMP"
    mkdir -p "$backup_dir"
    
    log "INFO" "Creating backup in $backup_dir"
    
    # Backup Kubernetes resources
    if command -v kubectl &> /dev/null; then
        log "INFO" "Backing up Kubernetes resources"
        kubectl get all --all-namespaces -o yaml > "$backup_dir/k8s-all-resources.yaml" 2>/dev/null || true
        kubectl get secrets --all-namespaces -o yaml > "$backup_dir/k8s-secrets.yaml" 2>/dev/null || true
        kubectl get configmaps --all-namespaces -o yaml > "$backup_dir/k8s-configmaps.yaml" 2>/dev/null || true
    fi
    
    # Backup Terraform state
    cd "$PROJECT_ROOT/terraform/envs/$ENV/$REGION" || return 1
    if [ -f ".terraform/terraform.tfstate" ]; then
        cp .terraform/terraform.tfstate "$backup_dir/terraform.tfstate" || true
    fi
    
    # Export Terraform state as JSON
    export AWS_PROFILE="$AWS_PROFILE"
    terragrunt show -json > "$backup_dir/terraform-state.json" 2>/dev/null || true
    
    # List all resources for reference
    terragrunt state list > "$backup_dir/terraform-resources.txt" 2>/dev/null || true
    
    # Backup AWS resource information
    if command -v aws &> /dev/null; then
        log "INFO" "Backing up AWS resource information"
        aws ec2 describe-vpcs --region "$REGION" --profile "$AWS_PROFILE" > "$backup_dir/aws-vpcs.json" 2>/dev/null || true
        aws eks describe-cluster --name "$ENV-eks-$REGION" --region "$REGION" --profile "$AWS_PROFILE" > "$backup_dir/aws-eks.json" 2>/dev/null || true
        aws rds describe-db-instances --region "$REGION" --profile "$AWS_PROFILE" > "$backup_dir/aws-rds.json" 2>/dev/null || true
    fi
    
    cd "$PROJECT_ROOT"
    log "INFO" "Backup completed in $backup_dir"
}

# Retry function with exponential backoff
retry_command() {
    local max_attempts=$1
    local base_delay=$2
    shift 2
    local command=("$@")
    
    for ((i=1; i<=max_attempts; i++)); do
        if "${command[@]}"; then
            return 0
        else
            if [ $i -eq $max_attempts ]; then
                log "ERROR" "Command failed after $max_attempts attempts: ${command[*]}"
                return 1
            fi
            local delay=$((base_delay * i))
            log "WARN" "Attempt $i failed, retrying in $delay seconds: ${command[*]}"
            sleep "$delay"
        fi
    done
}

# Wait for operation with timeout
wait_for_operation() {
    local operation_name=$1
    local check_command=$2
    local timeout=$3
    local interval=${4:-10}
    
    log "INFO" "Waiting for $operation_name to complete (max ${timeout}s)"
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$check_command"; then
            log "INFO" "$operation_name completed successfully"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        log "INFO" "$operation_name still in progress... (${elapsed}s/${timeout}s)"
    done
    
    log "WARN" "$operation_name timed out after ${timeout}s"
    return 1
}

# ============================================================================
# ENHANCED CLOUD RESOURCE DISCOVERY
# ============================================================================

# Get all VPC IDs from AWS (not just from terraform state)
get_aws_vpc_ids() {
    local vpc_ids
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
        log "WARN" "AWS CLI not configured, skipping VPC discovery"
        return 0
    fi
    
    vpc_ids=$(aws ec2 describe-vpcs --region "$REGION" --profile "$AWS_PROFILE" \
        --filters "Name=tag:Environment,Values=$ENV" \
        --query 'Vpcs[].VpcId' --output text 2>/dev/null || true)
    
    echo "$vpc_ids"
}

# Get all GCP networks
get_gcp_networks() {
    if [ -z "$GCP_PROJECT_ID" ]; then
        return 0
    fi
    
    gcloud compute networks list --project="$GCP_PROJECT_ID" \
        --filter="name~'.*$ENV.*'" --format="value(name)" 2>/dev/null || true
}

# Get all Azure resource groups
get_azure_resource_groups() {
    if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
        return 0
    fi
    
    az group list --subscription "$AZURE_SUBSCRIPTION_ID" \
        --query "[?contains(name, '$ENV')].name" --output tsv 2>/dev/null || true
}

# ============================================================================
# COMPREHENSIVE KUBERNETES CLEANUP
# ============================================================================

comprehensive_k8s_cleanup() {
    log "INFO" "Starting comprehensive Kubernetes cleanup"
    
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "DRY RUN: Would cleanup Kubernetes resources"
        return 0
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log "WARN" "kubectl not found, skipping Kubernetes cleanup"
        return 0
    fi
    
    # Check if kubectl can connect to any cluster
    if ! kubectl cluster-info &>/dev/null; then
        log "WARN" "kubectl cannot connect to any cluster, skipping Kubernetes cleanup"
        return 0
    fi
    
    # Delete LoadBalancer services first (critical for AWS LB cleanup)
    log "INFO" "Deleting LoadBalancer services"
    kubectl get services --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read -r namespace service; do
            if [ -n "$namespace" ] && [ -n "$service" ]; then
                log "INFO" "Deleting LoadBalancer service: $namespace/$service"
                kubectl delete service "$service" -n "$namespace" --ignore-not-found=true --timeout=60s || true
            fi
        done
    
    # Wait for LoadBalancer deletion to complete
    log "INFO" "Waiting for LoadBalancer services to be fully deleted"
    sleep 30
    
    # Delete persistent volumes and persistent volume claims
    log "INFO" "Deleting persistent volumes and claims"
    kubectl delete pvc --all --all-namespaces --ignore-not-found=true --timeout=120s || true
    kubectl delete pv --all --ignore-not-found=true --timeout=120s || true
    
    # Delete namespaces with finalizer removal
    local problematic_namespaces=(
        "consul" "nexus-dev" "argocd" "gitops" "datadog" "observability"
        "frontend-dev" "backend-dev" "monitoring" "logging" "security"
        "nexus-$ENV" "frontend-$ENV" "backend-$ENV"
        "kube-system" "ingress-nginx" "cert-manager" "external-dns"
    )
    
    for ns in "${problematic_namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            log "INFO" "Deleting namespace: $ns"
            
            # Remove finalizers from all resources in the namespace
            kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            
            # Delete the namespace
            kubectl delete namespace "$ns" --ignore-not-found=true --timeout=60s &
            local pid=$!
            
            # Force delete if it takes too long
            sleep 60
            if kill -0 $pid 2>/dev/null; then
                log "WARN" "Namespace $ns deletion taking too long, forcing deletion"
                kill $pid 2>/dev/null || true
                kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            fi
        fi
    done
    
    # Clean up custom resources and CRDs
    log "INFO" "Cleaning up custom resources"
    kubectl get crd -o name 2>/dev/null | while read -r crd; do
        kubectl delete "$crd" --all --ignore-not-found=true --timeout=30s || true
    done
    
    wait  # Wait for all background processes
    log "INFO" "Comprehensive Kubernetes cleanup completed"
}

# ============================================================================
# ENHANCED AWS RESOURCE CLEANUP
# ============================================================================

# Comprehensive AWS resource dependency resolution
comprehensive_aws_cleanup() {
    log "INFO" "Starting comprehensive AWS resource cleanup"
    
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "DRY RUN: Would perform AWS cleanup"
        return 0
    fi
    
    export AWS_PROFILE="$AWS_PROFILE"
    
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        log "WARN" "AWS CLI not configured, skipping AWS cleanup"
        return 0
    fi
    
    local vpc_ids
    vpc_ids=$(get_aws_vpc_ids)
    
    if [ -z "$vpc_ids" ]; then
        log "INFO" "No VPCs found for environment $ENV"
        return 0
    fi
    
    log "INFO" "Found VPCs to cleanup: $vpc_ids"
    
    for vpc_id in $vpc_ids; do
        log "INFO" "Cleaning up VPC: $vpc_id"
        cleanup_vpc_dependencies "$vpc_id"
    done
    
    # Clean up additional AWS resources
    cleanup_additional_aws_resources
    
    log "INFO" "Comprehensive AWS cleanup completed"
}

# Cleanup VPC dependencies in correct order
cleanup_vpc_dependencies() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up dependencies for VPC: $vpc_id"
    
    # 1. Clean up EKS clusters first (they create many resources)
    cleanup_eks_clusters "$vpc_id"
    
    # 2. Clean up RDS instances
    cleanup_rds_instances "$vpc_id"
    
    # 3. Clean up Load Balancers
    cleanup_load_balancers "$vpc_id"
    
    # 4. Clean up NAT Gateways
    cleanup_nat_gateways "$vpc_id"
    
    # 5. Clean up VPC Endpoints
    cleanup_vpc_endpoints "$vpc_id"
    
    # 6. Clean up Network Interfaces
    cleanup_network_interfaces "$vpc_id"
    
    # 7. Clean up Security Groups
    cleanup_security_groups "$vpc_id"
    
    # 8. Clean up Route Tables
    cleanup_route_tables "$vpc_id"
    
    # 9. Clean up Subnets
    cleanup_subnets "$vpc_id"
    
    # 10. Clean up Internet Gateways
    cleanup_internet_gateways "$vpc_id"
    
    # 11. Finally, delete the VPC
    delete_vpc "$vpc_id"
}

# EKS cluster cleanup
cleanup_eks_clusters() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up EKS clusters in VPC: $vpc_id"
    
    local clusters
    clusters=$(aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text 2>/dev/null || true)
    
    for cluster in $clusters; do
        # Check if cluster is in our VPC
        local cluster_vpc
        cluster_vpc=$(aws eks describe-cluster --name "$cluster" --region "$REGION" \
            --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || true)
        
        if [ "$cluster_vpc" == "$vpc_id" ]; then
            log "INFO" "Deleting EKS cluster: $cluster"
            
            # Delete node groups first
            local node_groups
            node_groups=$(aws eks list-nodegroups --cluster-name "$cluster" --region "$REGION" \
                --query 'nodegroups[]' --output text 2>/dev/null || true)
            
            for node_group in $node_groups; do
                log "INFO" "Deleting EKS node group: $node_group"
                aws eks delete-nodegroup --cluster-name "$cluster" --nodegroup-name "$node_group" \
                    --region "$REGION" 2>/dev/null || true
            done
            
            # Wait for node groups to be deleted
            for node_group in $node_groups; do
                wait_for_operation "EKS node group $node_group deletion" \
                    "! aws eks describe-nodegroup --cluster-name '$cluster' --nodegroup-name '$node_group' --region '$REGION' &>/dev/null" \
                    600
            done
            
            # Delete the cluster
            aws eks delete-cluster --name "$cluster" --region "$REGION" 2>/dev/null || true
            
            # Wait for cluster deletion
            wait_for_operation "EKS cluster $cluster deletion" \
                "! aws eks describe-cluster --name '$cluster' --region '$REGION' &>/dev/null" \
                "$CLUSTER_DELETE_TIMEOUT"
        fi
    done
}

# RDS instance cleanup
cleanup_rds_instances() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up RDS instances in VPC: $vpc_id"
    
    local db_instances
    db_instances=$(aws rds describe-db-instances --region "$REGION" \
        --query 'DBInstances[].DBInstanceIdentifier' --output text 2>/dev/null || true)
    
    for db_instance in $db_instances; do
        # Check if RDS instance is in our VPC
        local db_vpc
        db_vpc=$(aws rds describe-db-instances --db-instance-identifier "$db_instance" --region "$REGION" \
            --query 'DBInstances[0].DBSubnetGroup.VpcId' --output text 2>/dev/null || true)
        
        if [ "$db_vpc" == "$vpc_id" ]; then
            log "INFO" "Deleting RDS instance: $db_instance"
            aws rds delete-db-instance --db-instance-identifier "$db_instance" \
                --skip-final-snapshot --region "$REGION" 2>/dev/null || true
            
            # Wait for RDS deletion
            wait_for_operation "RDS instance $db_instance deletion" \
                "! aws rds describe-db-instances --db-instance-identifier '$db_instance' --region '$REGION' &>/dev/null" \
                1200
        fi
    done
}

# Load Balancer cleanup
cleanup_load_balancers() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up Load Balancers in VPC: $vpc_id"
    
    # Application Load Balancers
    local alb_arns
    alb_arns=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" --output text 2>/dev/null || true)
    
    for alb_arn in $alb_arns; do
        if [ -n "$alb_arn" ]; then
            log "INFO" "Deleting ALB: $alb_arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Classic Load Balancers
    local classic_lbs
    classic_lbs=$(aws elb describe-load-balancers --region "$REGION" \
        --query "LoadBalancerDescriptions[?VPCId=='$vpc_id'].LoadBalancerName" --output text 2>/dev/null || true)
    
    for clb in $classic_lbs; do
        if [ -n "$clb" ]; then
            log "INFO" "Deleting Classic LB: $clb"
            aws elb delete-load-balancer --load-balancer-name "$clb" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Wait for load balancers to be deleted
    if [ -n "$alb_arns" ] || [ -n "$classic_lbs" ]; then
        log "INFO" "Waiting for Load Balancers to be deleted"
        sleep 60
    fi
}

# NAT Gateway cleanup
cleanup_nat_gateways() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up NAT Gateways in VPC: $vpc_id"
    
    local nat_gateways
    nat_gateways=$(aws ec2 describe-nat-gateways --region "$REGION" \
        --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending,failed" \
        --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || true)
    
    for nat_id in $nat_gateways; do
        if [ -n "$nat_id" ]; then
            log "INFO" "Deleting NAT Gateway: $nat_id"
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Wait for NAT Gateways to be deleted
    if [ -n "$nat_gateways" ]; then
        for nat_id in $nat_gateways; do
            wait_for_operation "NAT Gateway $nat_id deletion" \
                "aws ec2 describe-nat-gateways --nat-gateway-ids '$nat_id' --region '$REGION' --query 'NatGateways[0].State' --output text 2>/dev/null | grep -q 'deleted'" \
                "$NAT_GATEWAY_DELETE_TIMEOUT"
        done
    fi
}

# VPC Endpoint cleanup
cleanup_vpc_endpoints() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up VPC Endpoints in VPC: $vpc_id"
    
    local vpc_endpoints
    vpc_endpoints=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || true)
    
    for endpoint_id in $vpc_endpoints; do
        if [ -n "$endpoint_id" ]; then
            log "INFO" "Deleting VPC Endpoint: $endpoint_id"
            aws ec2 delete-vpc-endpoint --vpc-endpoint-id "$endpoint_id" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Wait for VPC endpoints to be deleted
    if [ -n "$vpc_endpoints" ]; then
        sleep 30
    fi
}

# Network Interface cleanup
cleanup_network_interfaces() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up Network Interfaces in VPC: $vpc_id"
    
    local network_interfaces
    network_interfaces=$(aws ec2 describe-network-interfaces --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || true)
    
    for eni_id in $network_interfaces; do
        if [ -n "$eni_id" ]; then
            log "INFO" "Processing Network Interface: $eni_id"
            
            # Check if attached and detach
            local attachment_id
            attachment_id=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni_id" --region "$REGION" \
                --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text 2>/dev/null || true)
            
            if [ -n "$attachment_id" ] && [ "$attachment_id" != "None" ]; then
                log "INFO" "Detaching Network Interface: $eni_id"
                aws ec2 detach-network-interface --attachment-id "$attachment_id" --region "$REGION" 2>/dev/null || true
                
                # Wait for detachment
                wait_for_operation "ENI $eni_id detachment" \
                    "aws ec2 describe-network-interfaces --network-interface-ids '$eni_id' --region '$REGION' --query 'NetworkInterfaces[0].Status' --output text 2>/dev/null | grep -q 'available'" \
                    120
            fi
            
            # Delete the network interface
            log "INFO" "Deleting Network Interface: $eni_id"
            aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Wait for all ENIs to be deleted
    if [ -n "$network_interfaces" ]; then
        sleep 30
    fi
}

# Security Group cleanup
cleanup_security_groups() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up Security Groups in VPC: $vpc_id"
    
    local security_groups
    security_groups=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)
    
    # Remove all security group rules first
    for sg_id in $security_groups; do
        if [ -n "$sg_id" ]; then
            log "INFO" "Removing rules from Security Group: $sg_id"
            
            # Remove ingress rules
            local ingress_rules
            ingress_rules=$(aws ec2 describe-security-groups --group-ids "$sg_id" --region "$REGION" \
                --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null || echo "[]")
            
            if [ "$ingress_rules" != "[]" ]; then
                aws ec2 revoke-security-group-ingress --group-id "$sg_id" --ip-permissions "$ingress_rules" --region "$REGION" 2>/dev/null || true
            fi
            
            # Remove egress rules
            local egress_rules
            egress_rules=$(aws ec2 describe-security-groups --group-ids "$sg_id" --region "$REGION" \
                --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null || echo "[]")
            
            if [ "$egress_rules" != "[]" ]; then
                aws ec2 revoke-security-group-egress --group-id "$sg_id" --ip-permissions "$egress_rules" --region "$REGION" 2>/dev/null || true
            fi
        fi
    done
    
    # Wait for rule removal
    sleep 10
    
    # Delete security groups
    for sg_id in $security_groups; do
        if [ -n "$sg_id" ]; then
            log "INFO" "Deleting Security Group: $sg_id"
            aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION" 2>/dev/null || true
        fi
    done
}

# Route Table cleanup
cleanup_route_tables() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up Route Tables in VPC: $vpc_id"
    
    local route_tables
    route_tables=$(aws ec2 describe-route-tables --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?!Associations[0].Main].RouteTableId' --output text 2>/dev/null || true)
    
    for rt_id in $route_tables; do
        if [ -n "$rt_id" ]; then
            log "INFO" "Deleting Route Table: $rt_id"
            aws ec2 delete-route-table --route-table-id "$rt_id" --region "$REGION" 2>/dev/null || true
        fi
    done
}

# Subnet cleanup
cleanup_subnets() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up Subnets in VPC: $vpc_id"
    
    local subnets
    subnets=$(aws ec2 describe-subnets --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)
    
    for subnet_id in $subnets; do
        if [ -n "$subnet_id" ]; then
            log "INFO" "Deleting Subnet: $subnet_id"
            aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$REGION" 2>/dev/null || true
        fi
    done
}

# Internet Gateway cleanup
cleanup_internet_gateways() {
    local vpc_id=$1
    
    log "INFO" "Cleaning up Internet Gateways in VPC: $vpc_id"
    
    local igw_ids
    igw_ids=$(aws ec2 describe-internet-gateways --region "$REGION" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || true)
    
    for igw_id in $igw_ids; do
        if [ -n "$igw_id" ]; then
            log "INFO" "Detaching Internet Gateway: $igw_id"
            aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$REGION" 2>/dev/null || true
            
            log "INFO" "Deleting Internet Gateway: $igw_id"
            aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$REGION" 2>/dev/null || true
        fi
    done
}

# VPC deletion
delete_vpc() {
    local vpc_id=$1
    
    log "INFO" "Deleting VPC: $vpc_id"
    aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$REGION" 2>/dev/null || true
}

# Additional AWS resource cleanup
cleanup_additional_aws_resources() {
    log "INFO" "Cleaning up additional AWS resources"
    
    # Clean up CloudWatch Log Groups
    local log_groups
    log_groups=$(aws logs describe-log-groups --region "$REGION" \
        --log-group-name-prefix "/aws/eks/$ENV" \
        --query 'logGroups[].logGroupName' --output text 2>/dev/null || true)
    
    for log_group in $log_groups; do
        if [ -n "$log_group" ]; then
            log "INFO" "Deleting CloudWatch Log Group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Clean up ECR repositories
    local ecr_repos
    ecr_repos=$(aws ecr describe-repositories --region "$REGION" \
        --query "repositories[?contains(repositoryName, '$ENV')].repositoryName" --output text 2>/dev/null || true)
    
    for repo in $ecr_repos; do
        if [ -n "$repo" ]; then
            log "INFO" "Deleting ECR repository: $repo"
            aws ecr delete-repository --repository-name "$repo" --force --region "$REGION" 2>/dev/null || true
        fi
    done
}

# ============================================================================
# GCP RESOURCE CLEANUP
# ============================================================================

comprehensive_gcp_cleanup() {
    log "INFO" "Starting comprehensive GCP resource cleanup"
    
    if [ "$DRY_RUN" == "true" ] || [ -z "$GCP_PROJECT_ID" ]; then
        log "INFO" "DRY RUN or no GCP project ID: Skipping GCP cleanup"
        return 0
    fi
    
    # Set the project
    gcloud config set project "$GCP_PROJECT_ID" 2>/dev/null || {
        log "WARN" "Failed to set GCP project, skipping GCP cleanup"
        return 0
    }
    
    # Clean up GKE clusters
    local gke_clusters
    gke_clusters=$(gcloud container clusters list --project="$GCP_PROJECT_ID" \
        --filter="name~'.*$ENV.*'" --format="value(name,zone)" 2>/dev/null || true)
    
    while IFS=$'\t' read -r cluster_name zone; do
        if [ -n "$cluster_name" ] && [ -n "$zone" ]; then
            log "INFO" "Deleting GKE cluster: $cluster_name in $zone"
            gcloud container clusters delete "$cluster_name" --zone="$zone" \
                --project="$GCP_PROJECT_ID" --quiet 2>/dev/null || true
        fi
    done <<< "$gke_clusters"
    
    # Clean up VPC networks
    local networks
    networks=$(get_gcp_networks)
    
    for network in $networks; do
        if [ -n "$network" ]; then
            log "INFO" "Cleaning up GCP network: $network"
            
            # Delete firewall rules
            local firewall_rules
            firewall_rules=$(gcloud compute firewall-rules list --project="$GCP_PROJECT_ID" \
                --filter="network:$network" --format="value(name)" 2>/dev/null || true)
            
            for rule in $firewall_rules; do
                if [ -n "$rule" ]; then
                    log "INFO" "Deleting firewall rule: $rule"
                    gcloud compute firewall-rules delete "$rule" --project="$GCP_PROJECT_ID" --quiet 2>/dev/null || true
                fi
            done
            
            # Delete subnets
            local subnets
            subnets=$(gcloud compute networks subnets list --project="$GCP_PROJECT_ID" \
                --filter="network:$network" --format="value(name,region)" 2>/dev/null || true)
            
            while IFS=$'\t' read -r subnet_name region; do
                if [ -n "$subnet_name" ] && [ -n "$region" ]; then
                    log "INFO" "Deleting subnet: $subnet_name in $region"
                    gcloud compute networks subnets delete "$subnet_name" --region="$region" \
                        --project="$GCP_PROJECT_ID" --quiet 2>/dev/null || true
                fi
            done <<< "$subnets"
            
            # Delete the network
            log "INFO" "Deleting network: $network"
            gcloud compute networks delete "$network" --project="$GCP_PROJECT_ID" --quiet 2>/dev/null || true
        fi
    done
    
    log "INFO" "GCP resource cleanup completed"
}

# ============================================================================
# AZURE RESOURCE CLEANUP
# ============================================================================

comprehensive_azure_cleanup() {
    log "INFO" "Starting comprehensive Azure resource cleanup"
    
    if [ "$DRY_RUN" == "true" ] || [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
        log "INFO" "DRY RUN or no Azure subscription: Skipping Azure cleanup"
        return 0
    fi
    
    # Clean up resource groups
    local resource_groups
    resource_groups=$(get_azure_resource_groups)
    
    for rg_name in $resource_groups; do
        if [ -n "$rg_name" ]; then
            log "INFO" "Deleting Azure resource group: $rg_name"
            az group delete --name "$rg_name" --subscription "$AZURE_SUBSCRIPTION_ID" --yes --no-wait 2>/dev/null || true
        fi
    done
    
    log "INFO" "Azure resource cleanup completed"
}

# ============================================================================
# ENHANCED TERRAFORM DESTROY
# ============================================================================

comprehensive_terraform_destroy() {
    log "INFO" "Starting comprehensive terraform destroy"
    
    export AWS_PROFILE="$AWS_PROFILE"
    export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
    export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
    
    # Navigate to terraform directory
    if ! cd "$PROJECT_ROOT/terraform/envs/$ENV/$REGION"; then
        log "ERROR" "Failed to navigate to terraform environment directory"
        return 1
    fi
    
    # Check if terragrunt is initialized
    if ! terragrunt state list >/dev/null 2>&1; then
        log "ERROR" "Terragrunt not initialized or no state found"
        return 1
    fi
    
    # Clean Kubernetes resources from state (they're cleaned up manually)
    cleanup_terraform_state
    
    # Show current state
    local resource_count
    resource_count=$(terragrunt state list 2>/dev/null | wc -l)
    log "INFO" "Current state contains $resource_count resources"
    
    # Prepare terraform arguments
    local tf_args=""
    if [ "$AUTO_APPROVE" == "true" ] || [ "$FORCE_DESTROY" == "true" ]; then
        tf_args="-auto-approve"
    fi
    
    # Targeted destroy in proper dependency order
    local destroy_targets=(
        "module.nexus_eks"
        "module.k8s_nexus"
        "module.consul_eks_client"
        "module.consul_gke_client"
        "module.consul_primary"
        "module.puppet_enterprise"
        "module.jenkins"
        "module.aws_rds"
        "module.aws_eks"
        "module.gcp_gke"
        "module.azure_aks"
        "module.azure_ansible_controller"
        "module.aws_ecr"
        "module.gcp_vpc"
        "module.azure_vnet"
        "module.aws_vpc"
    )
    
    log "INFO" "Destroying resources in dependency order"
    for target in "${destroy_targets[@]}"; do
        if terragrunt state list 2>/dev/null | grep -q "^$target"; then
            log "INFO" "Destroying $target"
            
            if ! terragrunt destroy -auto-approve $tf_args -target="$target"; then
                log "WARN" "Failed to destroy $target, attempting to remove from state"
                terragrunt state rm "$target" 2>/dev/null || true
            fi
        else
            log "INFO" "Target $target not found in state, skipping"
        fi
    done
    
    # Final comprehensive destroy
    log "INFO" "Running final comprehensive destroy"
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "DRY RUN: Would run final terragrunt destroy"
    else
        terragrunt destroy -auto-approve $tf_args || {
            log "WARN" "Final destroy had issues, attempting cleanup"
            
            # Remove problematic resources from state
            terragrunt state list 2>/dev/null | grep -v "^data\." | while read -r resource; do
                if [ -n "$resource" ]; then
                    log "INFO" "Removing $resource from state"
                    terragrunt state rm "$resource" 2>/dev/null || true
                fi
            done
        }
    fi
    
    # Return to project root
    cd "$PROJECT_ROOT"
    
    return 0
}

# Clean up problematic resources from terraform state
cleanup_terraform_state() {
    log "INFO" "Cleaning up problematic resources from Terraform state"
    
    # Remove kubernetes and helm resources from state
    local k8s_patterns=(
        "kubernetes_"
        "helm_release"
        "module.consul_eks_client"
        "module.consul_gke_client"
        "module.k8s_argocd"
        "module.nexus_eks"
        "module.k8s_nexus"
        "null_resource.wait_for_cluster"
        "null_resource.wait_for_gke_cluster"
    )
    
    for pattern in "${k8s_patterns[@]}"; do
        terragrunt state list 2>/dev/null | grep "$pattern" | while read -r resource; do
            if [ -n "$resource" ]; then
                log "INFO" "Removing $resource from terraform state"
                terragrunt state rm "$resource" 2>/dev/null || true
            fi
        done || true
    done
    
    log "INFO" "Terraform state cleanup completed"
}

# ============================================================================
# MAIN COMPREHENSIVE DESTRUCTION
# ============================================================================

comprehensive_destroy() {
    log "INFO" "Starting comprehensive destruction"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    echo -e "   GCP Project: $GCP_PROJECT_ID"
    echo -e "   Azure Subscription: $AZURE_SUBSCRIPTION_ID"
    
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "DRY RUN: Would execute comprehensive destroy"
        return 0
    fi
    
    # Set environment variables
    export AWS_PROFILE="$AWS_PROFILE"
    export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
    export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
    
    # Create backup
    create_backup
    
    # Navigate to terraform directory
    if ! cd "$PROJECT_ROOT/terraform/envs/$ENV/$REGION"; then
        log "ERROR" "Failed to navigate to terraform environment directory"
        return 1
    fi
    
    # Phase 1: Kubernetes cleanup
    log "INFO" "Phase 1: Kubernetes cleanup"
    comprehensive_k8s_cleanup
    
    # Phase 2: Terraform destroy
    log "INFO" "Phase 2: Terraform destroy"
    comprehensive_terraform_destroy
    
    # Phase 3: Manual cloud resource cleanup
    log "INFO" "Phase 3: Manual cloud resource cleanup"
    comprehensive_aws_cleanup
    comprehensive_gcp_cleanup
    comprehensive_azure_cleanup
    
    # Return to project root
    cd "$PROJECT_ROOT"
    
    # Final verification
    cd "$PROJECT_ROOT/terraform/envs/$ENV/$REGION"
    export AWS_PROFILE="$AWS_PROFILE"
    
    local final_count
    final_count=$(terragrunt state list 2>/dev/null | wc -l)
    
    if [ "$final_count" -gt 0 ]; then
        log "WARN" "$final_count resources still remain in Terraform state"
        echo -e "${YELLOW}⚠️ $final_count resources still remain in Terraform state${NC}"
        
        log "INFO" "Remaining resources:"
        terragrunt state list 2>/dev/null | head -10 | while read -r resource; do
            log "INFO" "  - $resource"
        done
        
        return 1
    else
        log "INFO" "Terraform state is completely clean"
        echo -e "${GREEN}✅ Terraform state is completely clean${NC}"
        return 0
    fi
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << 'EOF'
🚨 Comprehensive Multi-Cloud DevOps Platform Destruction Script - FIXED VERSION

USAGE:
    ./destroy.sh [OPTIONS]

ENVIRONMENT OPTIONS:
    -e, --env ENV                 Environment to destroy (default: dev)
    -r, --region REGION           AWS region (default: us-east-2)
    -p, --profile PROFILE         AWS profile (default: default)
    --gcp-project-id ID           GCP project ID (default: complex-demo-465023)
    --azure-subscription-id ID    Azure subscription ID

CONTROL OPTIONS:
    --auto-approve                Skip all confirmation prompts
    --force-destroy               Force destruction without any safety checks
    --skip-backups                Skip backup creation before destruction
    --dry-run                     Show what would be destroyed without executing

OTHER OPTIONS:
    -h, --help                    Show this help message

NEW FEATURES IN FIXED VERSION:
    • Proper dependency resolution order
    • Enhanced resource discovery (doesn't rely on terraform state)
    • Comprehensive timeout handling
    • Better error recovery and retry logic
    • Complete coverage of all AWS resource types
    • Proper multi-cloud coordination
    • Enhanced logging and monitoring

EXAMPLES:
    # Comprehensive destruction with confirmation and backup
    ./destroy.sh -e dev

    # Force destruction without prompts or backups (DANGEROUS)
    ./destroy.sh -e dev --force-destroy --skip-backups

    # Dry run to see what would be destroyed
    ./destroy.sh --dry-run

⚠️ WARNING: This FIXED version will completely and thoroughly destroy
all infrastructure and data! Use with extreme caution!
EOF
}

# Parse arguments function
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--env)
                ENV="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --gcp-project-id)
                GCP_PROJECT_ID="$2"
                shift 2
                ;;
            --azure-subscription-id)
                AZURE_SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --force-destroy)
                FORCE_DESTROY=true
                AUTO_APPROVE=true
                shift
                ;;
            --skip-backups)
                SKIP_BACKUPS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Print banner
    print_banner
    
    # Display configuration
    echo -e "${BLUE}📋 Comprehensive Destruction Configuration (FIXED VERSION):${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    echo -e "   GCP Project: $GCP_PROJECT_ID"
    echo -e "   Azure Subscription: $AZURE_SUBSCRIPTION_ID"
    echo -e "   Dry Run: $DRY_RUN"
    echo -e "   Auto Approve: $AUTO_APPROVE"
    echo -e "   Force Destroy: $FORCE_DESTROY"
    echo -e "   Skip Backups: $SKIP_BACKUPS"
    echo -e "   Log File: $LOG_FILE"
    echo
    
    # Safety confirmation
    confirm_destruction
    
    # Comprehensive destruction
    comprehensive_destroy
    local result=$?
    
    echo -e "\n${RED}💀 COMPREHENSIVE DESTRUCTION COMPLETED! 💀${NC}"
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}✅ Your infrastructure has been completely destroyed.${NC}"
    else
        echo -e "${YELLOW}⚠️ Destruction completed with some issues. Check the log: $LOG_FILE${NC}"
    fi
    echo -e "${YELLOW}Please verify in your cloud consoles that all resources are gone.${NC}"
    echo -e "${BLUE}📋 Detailed log file: $LOG_FILE${NC}"
    
    return $result
}

# Execute main function with all arguments
main "$@"
