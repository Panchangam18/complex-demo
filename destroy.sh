#!/bin/bash

# 🚨 COMPREHENSIVE MULTI-CLOUD DEVOPS PLATFORM DESTRUCTION
# ==========================================================
# This script comprehensively destroys your multi-cloud DevOps platform
# with thorough cleanup, proper dependency handling, and robust error recovery.

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
readonly RESOURCE_DELETE_TIMEOUT=600  # 10 minutes
readonly CLUSTER_DELETE_TIMEOUT=1800  # 30 minutes

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Logging function
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
    ║           🚨 COMPREHENSIVE INFRASTRUCTURE DESTRUCTION 🚨                     ║
    ║                                                                              ║
    ║     ⚠️  WARNING: This will thoroughly destroy your infrastructure! ⚠️      ║
    ║                                                                              ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    log "INFO" "Starting comprehensive destruction process"
}

# Safety confirmation with enhanced warnings
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

# Backup function
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
    
    cd "$PROJECT_ROOT"
    log "INFO" "Backup completed in $backup_dir"
}

# Retry function for critical operations
retry_command() {
    local max_attempts=$1
    local delay=$2
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
            log "WARN" "Attempt $i failed, retrying in $delay seconds: ${command[*]}"
            sleep "$delay"
        fi
    done
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
    
    # Get all namespaces first
    local namespaces
    namespaces=$(kubectl get namespaces -o name 2>/dev/null | grep -v "namespace/kube-" | grep -v "namespace/default" || true)
    
    # Delete finalizers and force cleanup stuck resources
    log "INFO" "Removing finalizers from stuck resources"
    kubectl get namespace -o json | jq '.items[] | select(.metadata.name | startswith("kube-") | not) | select(.metadata.name != "default") | .metadata.name' -r 2>/dev/null | while read -r ns; do
        kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
    
    # Delete LoadBalancer services first (to release AWS LBs)
    log "INFO" "Deleting LoadBalancer services"
    kubectl get services --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' | while read -r namespace service; do
        kubectl delete service "$service" -n "$namespace" --ignore-not-found=true --timeout=60s || true
    done
    
    # Delete persistent volumes (to release EBS volumes)
    log "INFO" "Deleting persistent volumes"
    kubectl delete pv --all --ignore-not-found=true --timeout=120s || true
    
    # Force delete problematic namespaces
    local problematic_namespaces=(
        "consul" "nexus-dev" "argocd" "gitops" "datadog" "observability"
        "frontend-dev" "backend-dev" "monitoring" "logging" "security"
        "nexus-$ENV" "frontend-$ENV" "backend-$ENV"
    )
    
    for ns in "${problematic_namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            log "INFO" "Force deleting namespace: $ns"
            
            # Try graceful delete first
            kubectl delete namespace "$ns" --ignore-not-found=true --timeout=60s &
            local pid=$!
            
            # If graceful delete takes too long, force it
            sleep 60
            if kill -0 $pid 2>/dev/null; then
                log "WARN" "Graceful delete timed out for $ns, forcing deletion"
                kill $pid 2>/dev/null || true
                kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                kubectl delete namespace "$ns" --force --grace-period=0 2>/dev/null || true
            fi
        fi
    done
    
    # Clean up any remaining custom resources
    log "INFO" "Cleaning up custom resources"
    kubectl get crd -o name 2>/dev/null | while read -r crd; do
        kubectl delete "$crd" --all --ignore-not-found=true --timeout=30s || true
    done
    
    wait  # Wait for all background processes
    log "INFO" "Comprehensive Kubernetes cleanup completed"
}

# ============================================================================
# SUBNET DEPENDENCY RESOLUTION
# ============================================================================

resolve_subnet_dependencies() {
    log "INFO" "Resolving subnet dependencies to prevent deletion failures"
    
    # This function addresses the common AWS issue where subnets cannot be deleted
    # due to dependencies like NAT gateways, load balancers, or network interfaces.
    # It identifies and removes these dependencies before attempting subnet deletion.
    
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "DRY RUN: Would resolve subnet dependencies"
        return 0
    fi
    
    # Set AWS profile for all operations
    export AWS_PROFILE="$AWS_PROFILE"
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        log "WARN" "AWS CLI not configured or credentials invalid, skipping subnet dependency resolution"
        return 0
    fi
    
    # Get VPC ID from current state
    local vpc_id
    vpc_id=$(terragrunt state show module.aws_vpc.aws_vpc.main 2>/dev/null | grep "^id" | awk '{print $3}' | tr -d '"' || true)
    
    if [ -z "$vpc_id" ]; then
        log "INFO" "No VPC found in state, skipping subnet dependency resolution"
        return 0
    fi
    
    log "INFO" "Found VPC: $vpc_id, checking for subnet dependencies"
    
    # Get all subnets in the VPC
    local subnets
    subnets=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)
    
    if [ -z "$subnets" ]; then
        log "INFO" "No subnets found in VPC, skipping dependency resolution"
        return 0
    fi
    
    log "INFO" "Found subnets: $subnets"
    
    # For each subnet, check and resolve dependencies
    for subnet_id in $subnets; do
        log "INFO" "Checking dependencies for subnet: $subnet_id"
        
        # Check for NAT Gateways
        local nat_gateways
        nat_gateways=$(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=subnet-id,Values=$subnet_id" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text 2>/dev/null || true)
        
        if [ -n "$nat_gateways" ]; then
            log "INFO" "Found NAT Gateways using subnet $subnet_id: $nat_gateways"
            for nat_id in $nat_gateways; do
                log "INFO" "Deleting NAT Gateway: $nat_id"
                aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$REGION" 2>/dev/null || true
            done
            
            # Wait for NAT Gateways to be deleted
            if [ -n "$nat_gateways" ]; then
                log "INFO" "Waiting for NAT Gateways to be deleted..."
                sleep 30
                
                # Check deletion status
                for nat_id in $nat_gateways; do
                    local retries=0
                    while [ $retries -lt 12 ]; do  # 12 * 10 = 120 seconds
                        local state
                        state=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$nat_id" --region "$REGION" --query 'NatGateways[0].State' --output text 2>/dev/null || echo "deleted")
                        if [ "$state" == "deleted" ]; then
                            log "INFO" "NAT Gateway $nat_id successfully deleted"
                            break
                        fi
                        log "INFO" "NAT Gateway $nat_id still in state: $state, waiting..."
                        sleep 10
                        retries=$((retries + 1))
                    done
                done
            fi
        fi
        
        # Check for Load Balancers
        local load_balancers
        load_balancers=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(AvailabilityZones[].SubnetId, '$subnet_id')].LoadBalancerArn" --output text 2>/dev/null || true)
        
        if [ -n "$load_balancers" ]; then
            log "INFO" "Found Load Balancers using subnet $subnet_id: $load_balancers"
            for lb_arn in $load_balancers; do
                log "INFO" "Deleting Load Balancer: $lb_arn"
                aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$REGION" 2>/dev/null || true
            done
            
            # Wait for Load Balancers to be deleted
            if [ -n "$load_balancers" ]; then
                log "INFO" "Waiting for Load Balancers to be deleted..."
                sleep 30
            fi
        fi
        
        # Check for EC2 Instances
        local instances
        instances=$(aws ec2 describe-instances --region "$REGION" --filters "Name=subnet-id,Values=$subnet_id" "Name=instance-state-name,Values=running,stopped,stopping" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
        
        if [ -n "$instances" ]; then
            log "WARN" "Found EC2 Instances in subnet $subnet_id: $instances"
            log "WARN" "EC2 instances will be terminated by Terraform destroy"
        fi
        
        # Check for Network Interfaces
        local network_interfaces
        network_interfaces=$(aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=subnet-id,Values=$subnet_id" --query 'NetworkInterfaces[?Status!=`available`].NetworkInterfaceId' --output text 2>/dev/null || true)
        
        if [ -n "$network_interfaces" ]; then
            log "INFO" "Found Network Interfaces in subnet $subnet_id: $network_interfaces"
            for eni_id in $network_interfaces; do
                # Check if attached and detach
                local attachment_id
                attachment_id=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni_id" --region "$REGION" --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text 2>/dev/null || true)
                
                if [ -n "$attachment_id" ] && [ "$attachment_id" != "None" ]; then
                    log "INFO" "Detaching network interface: $eni_id"
                    aws ec2 detach-network-interface --attachment-id "$attachment_id" --region "$REGION" 2>/dev/null || true
                    sleep 10
                fi
                
                # Delete the network interface
                log "INFO" "Deleting network interface: $eni_id"
                aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$REGION" 2>/dev/null || true
            done
        fi
    done
    
    log "INFO" "Subnet dependency resolution completed"
}

# ============================================================================
# ENHANCED TERRAFORM DESTROY
# ============================================================================

cleanup_terraform_state() {
    log "INFO" "Cleaning up problematic resources from Terraform state"
    
    # Set AWS profile for all operations
    export AWS_PROFILE="$AWS_PROFILE"
    
    # Check if terragrunt is initialized and state exists
    if ! terragrunt state list >/dev/null 2>&1; then
        log "WARN" "No terraform state found or terragrunt not initialized"
        return 0
    fi
    
    # Remove all kubernetes and helm resources from state to avoid connection issues
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
            log "INFO" "Removing $resource from terraform state"
            terragrunt state rm "$resource" 2>/dev/null || true
        done || true
    done
    
    log "INFO" "Kubernetes resources removed from terraform state"
}

comprehensive_terraform_destroy() {
    log "INFO" "Starting comprehensive terraform destroy with subnet dependency resolution"
    
    # Set AWS profile for all operations
    export AWS_PROFILE="$AWS_PROFILE"
    
    # Check if terragrunt is initialized and state exists
    if ! terragrunt state list >/dev/null 2>&1; then
        log "ERROR" "Terragrunt not initialized or no state found"
        return 1
    fi
    
    # Show current state summary
    local resource_count
    resource_count=$(terragrunt state list 2>/dev/null | wc -l)
    log "INFO" "Current state contains $resource_count resources"
    
    local tf_args=""
    if [ "$AUTO_APPROVE" == "true" ] || [ "$FORCE_DESTROY" == "true" ]; then
        tf_args="-auto-approve"
    fi
    
    # Resolve subnet dependencies before destroying VPC resources
    resolve_subnet_dependencies
    
    # Targeted destroy in dependency order
    local destroy_targets=(
        "module.k8s_argocd"
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
    )
    
    log "INFO" "Destroying resources in dependency order"
    export AWS_PROFILE="$AWS_PROFILE"
    for target in "${destroy_targets[@]}"; do
        # Check if target exists in state
        if terragrunt state list 2>/dev/null | grep -q "^$target"; then
            log "INFO" "Destroying $target"
            terragrunt destroy $tf_args -target="$target" || log "WARN" "Failed to destroy $target, continuing"
        else
            log "INFO" "Target $target not found in state, skipping"
        fi
    done
    
    # Additional targeted destroy for VPC resources to handle subnet dependencies
    local vpc_targets=(
        "module.aws_vpc.aws_nat_gateway.main"
        "module.aws_vpc.aws_eip.nat"
        "module.aws_vpc.aws_route_table_association.public"
        "module.aws_vpc.aws_route_table_association.private"
        "module.aws_vpc.aws_route_table_association.intra"
        "module.aws_vpc.aws_route.private_nat"
        "module.aws_vpc.aws_route.public_internet"
        "module.aws_vpc.aws_route_table.private"
        "module.aws_vpc.aws_route_table.public"
        "module.aws_vpc.aws_route_table.intra"
        "module.aws_vpc.aws_subnet.public"
        "module.aws_vpc.aws_subnet.private"
        "module.aws_vpc.aws_subnet.intra"
        "module.aws_vpc.aws_internet_gateway.main"
        "module.aws_vpc.aws_vpc.main"
    )
    
    log "INFO" "Destroying VPC resources in dependency order"
    for target in "${vpc_targets[@]}"; do
        # Check if target exists in state
        if terragrunt state list 2>/dev/null | grep -q "^$target"; then
            log "INFO" "Destroying VPC resource: $target"
            terragrunt destroy $tf_args -target="$target" || log "WARN" "Failed to destroy $target, continuing"
        else
            log "INFO" "VPC target $target not found in state, skipping"
        fi
    done
    
    # Final subnet dependency resolution check
    log "INFO" "Final subnet dependency resolution check"
    resolve_subnet_dependencies
    
    # Final comprehensive destroy
    log "INFO" "Running final comprehensive destroy"
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "DRY RUN: Would run final terragrunt destroy"
    else
        # Set AWS profile and run destroy without timeout command wrapper
        export AWS_PROFILE="$AWS_PROFILE"
        terragrunt destroy $tf_args || log "WARN" "Final destroy had issues, but continuing"
    fi
    
    # Verify state is clean
    local remaining_resources
    remaining_resources=$(terragrunt state list 2>/dev/null | wc -l)
    if [ "$remaining_resources" -gt 0 ]; then
        log "WARN" "$remaining_resources resources remain in state after destroy"
        terragrunt state list 2>/dev/null | head -20 | while read -r resource; do
            log "WARN" "Remaining resource: $resource"
        done
    else
        log "INFO" "Terraform state is clean"
    fi
    
    return 0
}

# ============================================================================
# ADDITIONAL CLOUD CLEANUP
# ============================================================================

cleanup_aws_resources() {
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "DRY RUN: Would cleanup additional AWS resources"
        return 0
    fi
    
    log "INFO" "Cleaning up additional AWS resources"
    
    # Clean up any orphaned ELBs
    aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName, '$ENV')].LoadBalancerArn" --output text 2>/dev/null | while read -r lb_arn; do
        if [ -n "$lb_arn" ]; then
            log "INFO" "Deleting orphaned load balancer: $lb_arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Clean up security groups (after other resources)
    sleep 60  # Wait for dependent resources to be deleted
    aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=$ENV-*" --query "SecurityGroups[?GroupName != 'default'].GroupId" --output text 2>/dev/null | while read -r sg_id; do
        if [ -n "$sg_id" ]; then
            log "INFO" "Deleting security group: $sg_id"
            aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    log "INFO" "AWS resource cleanup completed"
}

cleanup_gcp_resources() {
    if [ "$DRY_RUN" == "true" ] || [ -z "$GCP_PROJECT_ID" ]; then
        log "INFO" "DRY RUN or no GCP project ID: Skipping GCP cleanup"
        return 0
    fi
    
    log "INFO" "Cleaning up additional GCP resources"
    
    # Clean up any remaining GKE clusters
    gcloud container clusters list --project="$GCP_PROJECT_ID" --format="value(name,zone)" 2>/dev/null | while read -r cluster_name zone; do
        if [[ "$cluster_name" == *"$ENV"* ]]; then
            log "INFO" "Deleting GKE cluster: $cluster_name in $zone"
            gcloud container clusters delete "$cluster_name" --zone="$zone" --project="$GCP_PROJECT_ID" --quiet 2>/dev/null || true
        fi
    done
    
    log "INFO" "GCP resource cleanup completed"
}

cleanup_azure_resources() {
    if [ "$DRY_RUN" == "true" ] || [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
        log "INFO" "DRY RUN or no Azure subscription: Skipping Azure cleanup"
        return 0
    fi
    
    log "INFO" "Cleaning up additional Azure resources"
    
    # Clean up resource groups
    az group list --subscription "$AZURE_SUBSCRIPTION_ID" --query "[?contains(name, '$ENV')].name" -o tsv 2>/dev/null | while read -r rg_name; do
        if [ -n "$rg_name" ]; then
            log "INFO" "Deleting Azure resource group: $rg_name"
            az group delete --name "$rg_name" --subscription "$AZURE_SUBSCRIPTION_ID" --yes --no-wait 2>/dev/null || true
        fi
    done
    
    log "INFO" "Azure resource cleanup completed"
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
    
    # Set environment variables for Terraform
    export AWS_PROFILE="$AWS_PROFILE"
    export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
    export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
    
    # Create backup before destruction
    create_backup
    
    # Navigate to the terraform environment
    if ! cd "$PROJECT_ROOT/terraform/envs/$ENV/$REGION"; then
        log "ERROR" "Failed to navigate to terraform environment directory"
        return 1
    fi
    
    # Comprehensive Kubernetes cleanup
    comprehensive_k8s_cleanup
    
    # Clean up kubernetes resources from state
    cleanup_terraform_state
    
    # Comprehensive terraform destroy
    comprehensive_terraform_destroy
    local destroy_result=$?
    
    # Return to project root for additional cleanup
    cd "$PROJECT_ROOT"
    
    # Additional cloud-specific cleanup
    cleanup_aws_resources
    cleanup_gcp_resources  
    cleanup_azure_resources
    
    if [ $destroy_result -eq 0 ]; then
        log "INFO" "Comprehensive infrastructure destruction completed successfully"
        echo -e "${GREEN}✅ Comprehensive infrastructure destruction completed${NC}"
    else
        log "WARN" "Infrastructure destruction completed with some issues"
        echo -e "${YELLOW}⚠️ Infrastructure destruction completed with some issues${NC}"
    fi
    
    # Final verification
    cd "$PROJECT_ROOT/terraform/envs/$ENV/$REGION"
    export AWS_PROFILE="$AWS_PROFILE"
    local final_count
    final_count=$(terragrunt state list 2>/dev/null | wc -l)
    if [ "$final_count" -gt 0 ]; then
        log "WARN" "$final_count resources still remain in Terraform state"
        echo -e "${YELLOW}⚠️ $final_count resources still remain in Terraform state${NC}"
    else
        log "INFO" "Terraform state is completely clean"
        echo -e "${GREEN}✅ Terraform state is completely clean${NC}"
    fi
    
    cd "$PROJECT_ROOT"
    
    return $destroy_result
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << 'EOF'
🚨 Comprehensive Multi-Cloud DevOps Platform Destruction Script

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

FEATURES:
    • Comprehensive backup creation before destruction
    • Automatic subnet dependency resolution (NAT gateways, load balancers, etc.)
    • Kubernetes resource cleanup with finalizer removal
    • Multi-cloud resource cleanup (AWS, GCP, Azure)
    • Proper dependency ordering to avoid deletion conflicts
    • Detailed logging and error handling

EXAMPLES:
    # Comprehensive destruction with confirmation and backup
    ./destroy.sh -e dev

    # Force destruction without prompts or backups (DANGEROUS)
    ./destroy.sh -e dev --force-destroy --skip-backups

    # Dry run to see what would be destroyed
    ./destroy.sh --dry-run

⚠️ WARNING: This is a COMPREHENSIVE destroyer that will completely remove
all infrastructure and data! Use with extreme caution!
EOF
}

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
    echo -e "${BLUE}📋 Comprehensive Destruction Configuration:${NC}"
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
        echo -e "${GREEN}Your infrastructure has been comprehensively destroyed.${NC}"
    else
        echo -e "${YELLOW}Destruction completed with some issues. Check the log: $LOG_FILE${NC}"
    fi
    echo -e "${YELLOW}Check cloud consoles to verify all resources are gone.${NC}"
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
    
    return $result
}

# Execute main function with all arguments
main "$@"
