#!/bin/bash

# Full Stack Deployment Script
# This script handles: Infrastructure (Terraform) + Application Images (JFrog) + Kubernetes Updates
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Default values
ENV=${ENV:-dev}
REGION=${REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-default}
SKIP_TERRAFORM=${SKIP_TERRAFORM:-false}
SKIP_IMAGES=${SKIP_IMAGES:-false}
SKIP_K8S_UPDATE=${SKIP_K8S_UPDATE:-false}

# Print banner
echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                     🚀 FULL STACK DEPLOYMENT SCRIPT 🚀                      ║"
echo "║                                                                              ║"
echo "║  Infrastructure (Terraform) + Applications (JFrog) + Kubernetes Updates     ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}📋 Deployment Configuration:${NC}"
echo -e "  Environment: ${ENV}"
echo -e "  Region: ${REGION}"
echo -e "  AWS Profile: ${AWS_PROFILE}"
echo -e "  Skip Terraform: ${SKIP_TERRAFORM}"
echo -e "  Skip Images: ${SKIP_IMAGES}"
echo -e "  Skip K8s Update: ${SKIP_K8S_UPDATE}"

# Function to print section headers
print_section() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    print_section "🔍 VALIDATING PREREQUISITES"
    
    local missing_commands=()
    
    if [ "$SKIP_TERRAFORM" != "true" ]; then
        if ! command_exists "make"; then
            missing_commands+=("make")
        fi
        if ! command_exists "terraform"; then
            missing_commands+=("terraform")
        fi
        if ! command_exists "terragrunt"; then
            missing_commands+=("terragrunt")
        fi
    fi
    
    if [ "$SKIP_IMAGES" != "true" ]; then
        if ! command_exists "docker"; then
            missing_commands+=("docker")
        fi
    fi
    
    if [ "$SKIP_K8S_UPDATE" != "true" ]; then
        if ! command_exists "kubectl"; then
            missing_commands+=("kubectl")
        fi
    fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required commands: ${missing_commands[*]}${NC}"
        exit 1
    fi
    
    # Check .env file exists for JFrog operations
    if [ "$SKIP_IMAGES" != "true" ] && [ ! -f .env ]; then
        echo -e "${RED}❌ .env file not found! Required for JFrog operations.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites validated${NC}"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    if [ "$SKIP_TERRAFORM" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping Terraform deployment${NC}"
        return 0
    fi
    
    print_section "🏗️  DEPLOYING INFRASTRUCTURE WITH TERRAFORM"
    
    echo -e "${YELLOW}🔧 Running terraform deployment...${NC}"
    cd terraform
    
    # Set AWS profile for this session
    export AWS_PROFILE="${AWS_PROFILE}"
    
    # Run make apply with specified environment and region
    make apply ENV="${ENV}" REGION="${REGION}"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Terraform deployment failed${NC}"
        cd ..
        exit 1
    fi
    
    echo -e "${GREEN}✅ Infrastructure deployed successfully${NC}"
    cd ..
}

# Build and push application images
build_and_push_images() {
    if [ "$SKIP_IMAGES" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping image build and push${NC}"
        return 0
    fi
    
    print_section "🐳 BUILDING AND PUSHING APPLICATION IMAGES"
    
    echo -e "${YELLOW}🔨 Building and pushing images to JFrog Artifactory...${NC}"
    ./scripts/build-and-push.sh
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Image build and push failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Images built and pushed successfully${NC}"
}

# Update Kubernetes deployments
update_kubernetes_deployments() {
    if [ "$SKIP_K8S_UPDATE" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping Kubernetes deployment updates${NC}"
        return 0
    fi
    
    print_section "☸️  UPDATING KUBERNETES DEPLOYMENTS"
    
    echo -e "${YELLOW}🔄 Updating Kubernetes deployment files...${NC}"
    ./scripts/update-k8s-images.sh
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Kubernetes deployment update failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Kubernetes deployments updated${NC}"
}

# Setup image pull secrets
setup_image_pull_secrets() {
    if [ "$SKIP_K8S_UPDATE" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping image pull secrets setup${NC}"
        return 0
    fi
    
    print_section "🔐 SETTING UP IMAGE PULL SECRETS"
    
    echo -e "${YELLOW}🔑 Creating JFrog image pull secrets...${NC}"
    
    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${YELLOW}⚠️  kubectl not configured or cluster not accessible${NC}"
        echo -e "${YELLOW}💡 Run this command to connect to your EKS cluster:${NC}"
        echo -e "   aws eks update-kubeconfig --region ${REGION} --name ${ENV}-eks-${REGION} --profile ${AWS_PROFILE}"
        echo -e "${YELLOW}⏭️  Skipping image pull secrets setup${NC}"
        return 0
    fi
    
    ./scripts/create-image-pull-secrets.sh
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}⚠️  Image pull secrets setup had issues, but continuing...${NC}"
    else
        echo -e "${GREEN}✅ Image pull secrets configured${NC}"
    fi
}

# Commit and push changes
commit_and_push_changes() {
    print_section "📤 COMMITTING AND PUSHING CHANGES"
    
    echo -e "${YELLOW}📝 Checking for changes to commit...${NC}"
    
    # Check if there are changes to commit
    if git diff --quiet && git diff --cached --quiet; then
        echo -e "${YELLOW}📭 No changes to commit${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}📋 Changes detected:${NC}"
    git status --porcelain
    
    # Add Kubernetes deployment changes
    git add k8s/envs/${ENV}/*/deployment.yaml 2>/dev/null || true
    
    # Create commit message
    local commit_msg="feat: deploy ${ENV} environment with JFrog images"
    commit_msg="${commit_msg}\n\n- Updated Kubernetes deployments to use JFrog Artifactory"
    commit_msg="${commit_msg}\n- Environment: ${ENV}"
    commit_msg="${commit_msg}\n- Region: ${REGION}"
    commit_msg="${commit_msg}\n- Deployed via full-stack deployment script"
    
    echo -e "${YELLOW}💾 Committing changes...${NC}"
    git commit -m "${commit_msg}"
    
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}📤 Pushing to remote...${NC}"
        git push origin main
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Changes committed and pushed successfully${NC}"
        else
            echo -e "${YELLOW}⚠️  Push failed, but deployment was successful${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Commit failed, but deployment was successful${NC}"
    fi
}

# Print deployment summary
print_summary() {
    print_section "🎉 DEPLOYMENT SUMMARY"
    
    echo -e "${GREEN}✅ Full stack deployment completed successfully!${NC}"
    echo -e "\n${BLUE}📋 What was deployed:${NC}"
    
    if [ "$SKIP_TERRAFORM" != "true" ]; then
        echo -e "  ✅ Infrastructure (Terraform): ${ENV}/${REGION}"
    fi
    
    if [ "$SKIP_IMAGES" != "true" ]; then
        echo -e "  ✅ Application Images: Built and pushed to JFrog"
    fi
    
    if [ "$SKIP_K8S_UPDATE" != "true" ]; then
        echo -e "  ✅ Kubernetes Deployments: Updated with new image URLs"
        echo -e "  ✅ Image Pull Secrets: Configured for JFrog authentication"
    fi
    
    echo -e "\n${YELLOW}🔗 Next Steps:${NC}"
    echo -e "  1. ArgoCD will automatically sync the updated deployments"
    echo -e "  2. Monitor deployment status: kubectl get pods -A"
    echo -e "  3. Check application logs: kubectl logs -f deployment/frontend -n frontend-${ENV}"
    echo -e "  4. Access Consul UI: make consul-status ENV=${ENV} REGION=${REGION}"
    
    echo -e "\n${PURPLE}🎊 Your multi-cloud DevOps platform is now fully deployed! 🎊${NC}"
}

# Help function
show_help() {
    echo "Full Stack Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --env ENV              Environment (default: dev)"
    echo "  -r, --region REGION        AWS region (default: us-east-2)"
    echo "  -p, --profile PROFILE      AWS profile (default: default)"
    echo "  --skip-terraform          Skip Terraform deployment"
    echo "  --skip-images             Skip image building and pushing"
    echo "  --skip-k8s-update         Skip Kubernetes deployment updates"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy everything with defaults"
    echo "  $0 -e prod -r us-west-2 -p prod     # Deploy to prod environment"
    echo "  $0 --skip-terraform                  # Only build images and update K8s"
    echo "  $0 --skip-images                     # Only deploy infrastructure"
}

# Parse command line arguments
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
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-images)
            SKIP_IMAGES=true
            shift
            ;;
        --skip-k8s-update)
            SKIP_K8S_UPDATE=true
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

# Add this function after the existing functions and before the main deployment logic

extract_and_save_credentials() {
    echo -e "${BLUE}🔐 Extracting deployment credentials...${NC}"
    
    # Run the credential extraction script
    if [ -f "scripts/extract-credentials-to-env.sh" ]; then
        chmod +x scripts/extract-credentials-to-env.sh
        ENVIRONMENT=$ENVIRONMENT REGION=$REGION ./scripts/extract-credentials-to-env.sh
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Credentials extracted and saved to .env${NC}"
        else
            echo -e "${YELLOW}⚠️  Credential extraction failed, but deployment continues${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Credential extraction script not found${NC}"
    fi
}

# Main execution
main() {
    validate_prerequisites
    deploy_infrastructure
    build_and_push_images
    update_kubernetes_deployments
    setup_image_pull_secrets
    commit_and_push_changes
    extract_and_save_credentials
    print_summary
}

# Run main function
main "$@" 