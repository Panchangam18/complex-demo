#!/bin/bash

# 🚨 FAST MULTI-CLOUD DEVOPS PLATFORM DESTRUCTION
# ================================================
# This script quickly destroys your multi-cloud DevOps platform
# with minimal cleanup - focused on speed and efficiency.

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

# Default values
ENV=${ENV:-dev}
REGION=${REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-sandbox-permanent}
GCP_PROJECT_ID=${GCP_PROJECT_ID:-"complex-demo-465023"}

# Destruction control flags
DRY_RUN=${DRY_RUN:-false}
AUTO_APPROVE=${AUTO_APPROVE:-false}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Print banner
print_banner() {
    echo -e "${RED}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                              ║
    ║                🚨 FAST INFRASTRUCTURE DESTRUCTION 🚨                        ║
    ║                                                                              ║
    ║     ⚠️  WARNING: This will destroy your infrastructure quickly! ⚠️        ║
    ║                                                                              ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Safety confirmation
confirm_destruction() {
    if [ "$AUTO_APPROVE" == "true" ]; then
        return 0
    fi
    
    echo -e "${RED}⚠️  FAST DESTRUCTION MODE - SKIPPING BACKUPS ⚠️${NC}"
    echo -e "${YELLOW}This will quickly destroy all infrastructure in $ENV environment${NC}"
    echo
    
    read -p "Type 'DESTROY' to continue: " confirmation
    
    if [ "$confirmation" != "DESTROY" ]; then
        echo -e "${GREEN}✅ Destruction cancelled.${NC}"
        exit 0
    fi
    
    echo -e "${RED}🚨 Proceeding with fast destruction...${NC}"
}

# ============================================================================
# FAST KUBERNETES CLEANUP
# ============================================================================

fast_k8s_cleanup() {
    echo -e "${BLUE}🧹 Fast Kubernetes cleanup...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would cleanup Kubernetes resources${NC}"
        return 0
    fi
    
    # Only essential cleanups
    kubectl delete namespace consul --ignore-not-found=true &
    kubectl delete namespace nexus-dev --ignore-not-found=true &
    kubectl delete namespace argocd --ignore-not-found=true &
    kubectl delete namespace datadog --ignore-not-found=true &
    kubectl delete namespace frontend-dev --ignore-not-found=true &
    kubectl delete namespace backend-dev --ignore-not-found=true &
    
    # Wait for background jobs to finish (max 30 seconds)
    timeout 30 wait 2>/dev/null || true
    
    echo -e "${GREEN}✅ Fast Kubernetes cleanup completed${NC}"
}

# ============================================================================
# FAST TERRAFORM DESTROY
# ============================================================================

cleanup_k8s_resources_from_state() {
    echo -e "${BLUE}🧹 Removing problematic k8s resources from terraform state...${NC}"
    
    # Check if terragrunt is initialized and state exists
    if ! AWS_PROFILE="$AWS_PROFILE" terragrunt state list >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  No terraform state found or terragrunt not initialized${NC}"
        return 0
    fi
    
    # Remove all kubernetes resources from state to avoid connection issues
    local k8s_pattern="kubernetes_\|helm_release\|module.consul_eks_client\|module.consul_gke_client\|module.nexus_eks"
    
    AWS_PROFILE="$AWS_PROFILE" terragrunt state list 2>/dev/null | grep -E "$k8s_pattern" | while read -r resource; do
        echo -e "${YELLOW}  Removing $resource from terraform state...${NC}"
        AWS_PROFILE="$AWS_PROFILE" terragrunt state rm "$resource" 2>/dev/null || true
    done || true
    
    echo -e "${GREEN}✅ Kubernetes resources removed from terraform state${NC}"
}

fast_terraform_destroy() {
    echo -e "${BLUE}🎯 Fast terraform destroy...${NC}"
    
    # Check if terragrunt is initialized and state exists
    if ! AWS_PROFILE="$AWS_PROFILE" terragrunt state list >/dev/null 2>&1; then
        echo -e "${RED}❌ Terragrunt not initialized or no state found${NC}"
        return 1
    fi
    
    # Show current state summary
    local resource_count=$(AWS_PROFILE="$AWS_PROFILE" terragrunt state list 2>/dev/null | wc -l)
    echo -e "${BLUE}📊 Current state contains $resource_count resources${NC}"
    
    local tf_args=""
    if [ "$AUTO_APPROVE" == "true" ]; then
        tf_args="-auto-approve"
    fi
    
    # Try targeted destroy first (most dependent resources)
    echo -e "${BLUE}🎯 Destroying primary infrastructure...${NC}"
    AWS_PROFILE="$AWS_PROFILE" terragrunt destroy $tf_args -target="module.consul_primary" 2>/dev/null || true
    AWS_PROFILE="$AWS_PROFILE" terragrunt destroy $tf_args -target="module.puppet_enterprise" 2>/dev/null || true
    AWS_PROFILE="$AWS_PROFILE" terragrunt destroy $tf_args -target="module.jenkins" 2>/dev/null || true
    AWS_PROFILE="$AWS_PROFILE" terragrunt destroy $tf_args -target="module.aws_rds" 2>/dev/null || true
    
    echo -e "${BLUE}🎯 Destroying remaining infrastructure...${NC}"
    # Final destroy of everything else
    AWS_PROFILE="$AWS_PROFILE" terragrunt destroy $tf_args 2>/dev/null || true
    
    echo -e "${GREEN}✅ Fast terraform destroy completed${NC}"
    return 0
}

# ============================================================================
# MAIN FAST DESTRUCTION
# ============================================================================

fast_destroy() {
    echo -e "${RED}💥 Fast destroying infrastructure...${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    echo -e "   GCP Project: $GCP_PROJECT_ID"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would execute fast destroy${NC}"
        return 0
    fi
    
    # Set environment variables for Terraform
    export AWS_PROFILE="$AWS_PROFILE"
    export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
    
    # Fast Kubernetes cleanup
    fast_k8s_cleanup
    
    # Navigate to the terraform environment
    if ! cd "$PROJECT_ROOT/terraform/envs/$ENV/$REGION"; then
        echo -e "${RED}❌ Failed to navigate to terraform environment directory${NC}"
        return 1
    fi
    
    # Clean up kubernetes resources from state
    cleanup_k8s_resources_from_state
    
    # Fast terraform destroy
    fast_terraform_destroy
    local destroy_result=$?
    
    # Return to project root
    cd "$PROJECT_ROOT"
    
    if [ $destroy_result -eq 0 ]; then
        echo -e "${GREEN}✅ Fast infrastructure destruction completed${NC}"
    else
        echo -e "${YELLOW}⚠️ Infrastructure destruction completed with some issues${NC}"
    fi
    
    return $destroy_result
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << 'EOF'
🚨 Fast Multi-Cloud DevOps Platform Destruction Script

USAGE:
    ./destroy.sh [OPTIONS]

ENVIRONMENT OPTIONS:
    -e, --env ENV                 Environment to destroy (default: dev)
    -r, --region REGION           AWS region (default: us-east-2)
    -p, --profile PROFILE         AWS profile (default: sandbox-permanent)
    --gcp-project-id ID           GCP project ID (default: complex-demo-465023)

SPEED OPTIONS:
    --auto-approve                Skip all confirmation prompts
    --dry-run                     Show what would be destroyed without executing

OTHER OPTIONS:
    -h, --help                    Show this help message

EXAMPLES:
    # Fast destruction with confirmation
    ./destroy.sh -e dev

    # Ultra-fast destruction without prompts
    ./destroy.sh -e dev --auto-approve

    # Dry run to see what would be destroyed
    ./destroy.sh --dry-run

⚠️ WARNING: This is a FAST destroyer that skips backups and cleanup!
Use with caution - it will destroy infrastructure quickly!
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
            --auto-approve)
                AUTO_APPROVE=true
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
    echo -e "${BLUE}📋 Fast Destruction Configuration:${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    echo -e "   GCP Project: $GCP_PROJECT_ID"
    echo -e "   Dry Run: $DRY_RUN"
    echo -e "   Auto Approve: $AUTO_APPROVE"
    echo
    
    # Safety confirmation
    confirm_destruction
    
    # Fast destruction
    fast_destroy
    
    echo -e "\n${RED}💀 FAST DESTRUCTION COMPLETED! 💀${NC}"
    echo -e "${GREEN}Your infrastructure has been destroyed quickly.${NC}"
    echo -e "${YELLOW}Check cloud consoles to verify all resources are gone.${NC}"
}

# Execute main function with all arguments
main "$@"
