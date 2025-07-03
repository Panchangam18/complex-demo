#!/bin/bash

# 🚨 COMPREHENSIVE MULTI-CLOUD DEVOPS PLATFORM DESTRUCTION
# ========================================================
# This script safely tears down your multi-cloud DevOps platform
# in proper reverse order with data preservation options.

set -euo pipefail

# ============================================================================
# CONFIGURATION & COLORS
# ============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Project configuration
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="${PROJECT_ROOT}/destruction-${TIMESTAMP}.log"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups-${TIMESTAMP}"

# Default values
ENV=${ENV:-dev}
REGION=${REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-default}
GCP_PROJECT_ID=${GCP_PROJECT_ID:-""}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-""}

# Destruction control flags
SKIP_BACKUPS=${SKIP_BACKUPS:-false}
SKIP_EXTERNAL_CLEANUP=${SKIP_EXTERNAL_CLEANUP:-false}
FORCE_DESTROY=${FORCE_DESTROY:-false}
PRESERVE_DATA=${PRESERVE_DATA:-true}
DRY_RUN=${DRY_RUN:-false}
AUTO_APPROVE=${AUTO_APPROVE:-false}

# Destruction tracking
DESTRUCTION_PHASES=()
FAILED_PHASES=()
SUCCESSFUL_PHASES=()
PRESERVED_RESOURCES=()

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Print section headers
print_section() {
    echo -e "\n${RED}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}$1${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════════════════${NC}\n"
    log "INFO" "Starting destruction phase: $1"
}

# Print banner
print_banner() {
    echo -e "${RED}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                              ║
    ║                🚨 MULTI-CLOUD DEVOPS PLATFORM DESTRUCTION 🚨               ║
    ║                                                                              ║
    ║     ⚠️  WARNING: This will destroy your entire infrastructure! ⚠️         ║
    ║                                                                              ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Command existence check
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Phase tracking
start_phase() {
    local phase="$1"
    DESTRUCTION_PHASES+=("$phase")
    log "INFO" "Starting destruction phase: $phase"
}

complete_phase() {
    local phase="$1"
    SUCCESSFUL_PHASES+=("$phase")
    log "SUCCESS" "Completed destruction phase: $phase"
}

fail_phase() {
    local phase="$1"
    local error="$2"
    FAILED_PHASES+=("$phase")
    log "ERROR" "Failed destruction phase: $phase - $error"
}

# Safety confirmation
confirm_destruction() {
    if [ "$AUTO_APPROVE" == "true" ] || [ "$FORCE_DESTROY" == "true" ]; then
        return 0
    fi
    
    echo -e "${RED}⚠️  YOU ARE ABOUT TO DESTROY YOUR ENTIRE MULTI-CLOUD DEVOPS PLATFORM ⚠️${NC}"
    echo -e "${YELLOW}This action will:${NC}"
    echo -e "   🚨 Destroy all infrastructure in $ENV environment"
    echo -e "   🚨 Remove all applications and data"
    echo -e "   🚨 Delete monitoring and logging configurations"
    echo -e "   🚨 Remove CI/CD pipelines and artifacts"
    echo -e "   🚨 Clean up all external service integrations"
    echo
    echo -e "${BLUE}Environment: $ENV${NC}"
    echo -e "${BLUE}Region: $REGION${NC}"
    echo -e "${BLUE}Preserve Data: $PRESERVE_DATA${NC}"
    echo
    
    read -p "Are you ABSOLUTELY SURE you want to proceed? Type 'DESTROY' to continue: " confirmation
    
    if [ "$confirmation" != "DESTROY" ]; then
        echo -e "${GREEN}✅ Destruction cancelled. Your infrastructure is safe.${NC}"
        exit 0
    fi
    
    echo -e "${RED}🚨 Proceeding with destruction...${NC}"
    log "WARNING" "User confirmed destruction of $ENV environment"
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_prerequisites() {
    print_section "🔍 VALIDATING PREREQUISITES"
    
    local missing_commands=()
    local required_commands=(
        "terraform" "terragrunt" "make" "kubectl"
        "docker" "jq" "curl" "git"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log "ERROR" "Missing required commands: ${missing_commands[*]}"
        echo -e "${RED}❌ Missing required commands: ${missing_commands[*]}${NC}"
        echo -e "${YELLOW}💡 Please install missing tools and retry${NC}"
        exit 1
    fi
    
    # Validate cloud credentials
    echo -e "${BLUE}🔐 Validating cloud credentials...${NC}"
    
    # AWS
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log "ERROR" "AWS credentials not configured for profile: $AWS_PROFILE"
        echo -e "${RED}❌ AWS credentials not configured for profile: $AWS_PROFILE${NC}"
        exit 1
    fi
    
    # GCP (if project ID provided)
    if [ -n "$GCP_PROJECT_ID" ]; then
        if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
            log "ERROR" "GCP credentials not configured"
            echo -e "${RED}❌ GCP credentials not configured${NC}"
            exit 1
        fi
    fi
    
    # Azure (if subscription ID provided)
    if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
        if ! az account show >/dev/null 2>&1; then
            log "ERROR" "Azure credentials not configured"
            echo -e "${RED}❌ Azure credentials not configured${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✅ All prerequisites validated${NC}"
    log "SUCCESS" "Prerequisites validation completed"
}

validate_environment() {
    print_section "🔍 VALIDATING ENVIRONMENT"
    
    # Check if environment exists
    if [ ! -d "terraform/envs/$ENV/$REGION" ]; then
        echo -e "${RED}❌ Environment $ENV in region $REGION not found${NC}"
        echo -e "${YELLOW}Available environments:${NC}"
        find terraform/envs -type d -name "us-*" -o -name "eu-*" -o -name "ap-*" 2>/dev/null | head -10
        exit 1
    fi
    
    # Check if kubectl is connected to the right cluster
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    echo -e "${BLUE}Current kubectl context: $current_context${NC}"
    
    # Warn if this might be production
    if [[ "$ENV" == "prod" || "$ENV" == "production" ]]; then
        echo -e "${RED}🚨 WARNING: You are about to destroy PRODUCTION environment!${NC}"
        echo -e "${RED}🚨 This cannot be undone!${NC}"
        
        if [ "$FORCE_DESTROY" != "true" ]; then
            read -p "Type 'DESTROY-PRODUCTION' to confirm: " prod_confirmation
            if [ "$prod_confirmation" != "DESTROY-PRODUCTION" ]; then
                echo -e "${GREEN}✅ Production destruction cancelled${NC}"
                exit 0
            fi
        fi
    fi
    
    echo -e "${GREEN}✅ Environment validation completed${NC}"
    log "SUCCESS" "Environment validation completed"
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

create_backups() {
    if [ "$SKIP_BACKUPS" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping backups${NC}"
        return 0
    fi
    
    print_section "💾 CREATING BACKUPS"
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup Terraform state
    backup_terraform_state
    
    # Backup Kubernetes configurations
    backup_kubernetes_configs
    
    # Backup application data
    backup_application_data
    
    # Backup monitoring configurations
    backup_monitoring_configs
    
    echo -e "${GREEN}✅ Backups completed in: $BACKUP_DIR${NC}"
    log "SUCCESS" "Backup phase completed"
}

backup_terraform_state() {
    echo -e "${BLUE}📁 Backing up Terraform state...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would backup Terraform state${NC}"
        return 0
    fi
    
    cd "terraform/envs/$ENV/$REGION"
    
    # Export current state
    terragrunt show -json > "$BACKUP_DIR/terraform-state.json" 2>/dev/null || echo "No state found"
    
    # Backup state file itself if using local backend
    if [ -f terraform.tfstate ]; then
        cp terraform.tfstate "$BACKUP_DIR/"
    fi
    
    # Export outputs
    terragrunt output -json > "$BACKUP_DIR/terraform-outputs.json" 2>/dev/null || echo "No outputs found"
    
    cd - >/dev/null
    log "SUCCESS" "Terraform state backed up"
}

backup_kubernetes_configs() {
    echo -e "${BLUE}☸️ Backing up Kubernetes configurations...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would backup Kubernetes configs${NC}"
        return 0
    fi
    
    # Backup all custom resources
    kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/k8s-all-resources.yaml" 2>/dev/null || true
    
    # Backup ConfigMaps and Secrets (without sensitive data)
    kubectl get configmaps --all-namespaces -o yaml > "$BACKUP_DIR/k8s-configmaps.yaml" 2>/dev/null || true
    
    # Backup PVCs (list only, not data)
    kubectl get pvc --all-namespaces -o yaml > "$BACKUP_DIR/k8s-pvcs.yaml" 2>/dev/null || true
    
    # Backup custom CRDs
    kubectl get crd -o yaml > "$BACKUP_DIR/k8s-crds.yaml" 2>/dev/null || true
    
    log "SUCCESS" "Kubernetes configurations backed up"
}

backup_application_data() {
    echo -e "${BLUE}💾 Backing up application data...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would backup application data${NC}"
        return 0
    fi
    
    # Note: In a real scenario, you'd backup actual database data
    # For this demo, we'll just document what exists
    echo "# Application Data Backup Summary" > "$BACKUP_DIR/application-data-summary.md"
    echo "Generated: $(date)" >> "$BACKUP_DIR/application-data-summary.md"
    echo "" >> "$BACKUP_DIR/application-data-summary.md"
    
    # List databases
    echo "## Databases" >> "$BACKUP_DIR/application-data-summary.md"
    kubectl get pods -A | grep -i postgres >> "$BACKUP_DIR/application-data-summary.md" 2>/dev/null || true
    
    # List PVCs
    echo "## Persistent Volumes" >> "$BACKUP_DIR/application-data-summary.md"
    kubectl get pvc -A >> "$BACKUP_DIR/application-data-summary.md" 2>/dev/null || true
    
    log "SUCCESS" "Application data summary created"
}

backup_monitoring_configs() {
    echo -e "${BLUE}📊 Backing up monitoring configurations...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would backup monitoring configs${NC}"
        return 0
    fi
    
    # Backup monitoring namespace resources
    kubectl get all -n datadog -o yaml > "$BACKUP_DIR/datadog-resources.yaml" 2>/dev/null || true
    kubectl get all -n observability -o yaml > "$BACKUP_DIR/observability-resources.yaml" 2>/dev/null || true
    kubectl get all -n logging -o yaml > "$BACKUP_DIR/logging-resources.yaml" 2>/dev/null || true
    
    # Copy local monitoring configs
    cp -r monitoring/ "$BACKUP_DIR/" 2>/dev/null || true
    cp -r k8s/envs/dev/monitoring/ "$BACKUP_DIR/k8s-monitoring/" 2>/dev/null || true
    
    log "SUCCESS" "Monitoring configurations backed up"
}

# ============================================================================
# DESTRUCTION PHASES (in reverse order of deployment)
# ============================================================================

destroy_integration_testing() {
    start_phase "Integration Testing Cleanup"
    print_section "🧪 DESTROYING INTEGRATION TESTING"
    
    echo -e "${RED}🔬 Removing integration testing infrastructure...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy integration testing${NC}"
    else
        kubectl delete namespace integration-testing --ignore-not-found=true
        kubectl delete -f k8s/envs/dev/testing/ --ignore-not-found=true 2>/dev/null || true
    fi
    
    complete_phase "Integration Testing Cleanup"
}

destroy_performance_monitoring() {
    start_phase "Performance Monitoring Cleanup"
    print_section "📊 DESTROYING PERFORMANCE MONITORING"
    
    echo -e "${RED}⚡ Removing performance monitoring stack...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy performance monitoring${NC}"
    else
        kubectl delete namespace performance --ignore-not-found=true
        helm uninstall prometheus-stack -n observability 2>/dev/null || true
    fi
    
    complete_phase "Performance Monitoring Cleanup"
}

destroy_compliance_scanning() {
    start_phase "Compliance Scanning Cleanup"
    print_section "🛡️ DESTROYING COMPLIANCE SCANNING"
    
    echo -e "${RED}📋 Removing compliance scanning tools...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy compliance scanning${NC}"
    else
        kubectl delete namespace trivy-system --ignore-not-found=true
        kubectl delete -f k8s/envs/dev/security/ --ignore-not-found=true 2>/dev/null || true
    fi
    
    complete_phase "Compliance Scanning Cleanup"
}

destroy_custom_dns() {
    start_phase "Custom DNS Cleanup"
    print_section "🌍 DESTROYING CUSTOM DNS"
    
    echo -e "${RED}📡 Removing custom DNS configurations...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy custom DNS${NC}"
    else
        helm uninstall external-dns -n kube-system 2>/dev/null || true
        kubectl delete configmap coredns-consul -n kube-system --ignore-not-found=true
    fi
    
    complete_phase "Custom DNS Cleanup"
}

destroy_disaster_recovery() {
    start_phase "Disaster Recovery Cleanup"
    print_section "💾 DESTROYING DISASTER RECOVERY"
    
    echo -e "${RED}🔄 Removing backup and DR configurations...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy disaster recovery${NC}"
    else
        kubectl delete namespace backup --ignore-not-found=true
        helm uninstall velero -n velero 2>/dev/null || true
    fi
    
    complete_phase "Disaster Recovery Cleanup"
}

destroy_api_gateway() {
    start_phase "API Gateway Cleanup"
    print_section "🚪 DESTROYING API GATEWAY"
    
    echo -e "${RED}🔌 Removing API gateway...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy API gateway${NC}"
    else
        kubectl delete namespace gateway --ignore-not-found=true
        helm uninstall kong -n kong 2>/dev/null || true
    fi
    
    complete_phase "API Gateway Cleanup"
}

destroy_applications() {
    start_phase "Application Cleanup"
    print_section "🚀 DESTROYING APPLICATIONS"
    
    echo -e "${RED}💻 Removing application deployments...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy applications${NC}"
    else
        # Remove frontend
        kubectl delete namespace frontend-dev --ignore-not-found=true
        
        # Remove backend
        kubectl delete namespace backend-dev --ignore-not-found=true
        
        # Remove ArgoCD applications
        kubectl delete -f k8s/envs/dev/applications.yaml --ignore-not-found=true 2>/dev/null || true
    fi
    
    complete_phase "Application Cleanup"
}

destroy_cicd_pipeline() {
    start_phase "CI/CD Pipeline Cleanup"
    print_section "🔄 DESTROYING CI/CD PIPELINE"
    
    # Destroy ArgoCD
    destroy_argocd
    
    # Destroy Jenkins integration
    destroy_jenkins_integration
    
    # Destroy Nexus (handled by Terraform)
    destroy_nexus
    
    complete_phase "CI/CD Pipeline Cleanup"
}

destroy_argocd() {
    echo -e "${RED}🔄 Removing ArgoCD...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy ArgoCD${NC}"
    else
        kubectl delete namespace argocd --ignore-not-found=true
        kubectl delete -f k8s/argocd/ --ignore-not-found=true 2>/dev/null || true
    fi
}

destroy_jenkins_integration() {
    echo -e "${RED}🔧 Removing Jenkins integration...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy Jenkins integration${NC}"
    else
        # Jenkins server itself is destroyed with Terraform
        echo "Jenkins integration cleanup (server destroyed with Terraform)"
    fi
}

destroy_nexus() {
    echo -e "${RED}📦 Removing Nexus Repository Manager...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy Nexus${NC}"
    else
        kubectl delete namespace nexus-dev --ignore-not-found=true
        # Nexus itself is destroyed with Terraform module
    fi
}

destroy_observability_stack() {
    start_phase "Observability Stack Cleanup"
    print_section "📊 DESTROYING OBSERVABILITY STACK"
    
    # Destroy monitoring
    destroy_monitoring
    
    # Destroy logging
    destroy_logging
    
    # Clean up external service integrations
    cleanup_external_monitoring
    
    complete_phase "Observability Stack Cleanup"
}

destroy_monitoring() {
    echo -e "${RED}📊 Removing monitoring stack...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy monitoring${NC}"
    else
        # Remove DataDog
        kubectl delete namespace datadog --ignore-not-found=true
        
        # Remove New Relic
        kubectl delete namespace newrelic --ignore-not-found=true
        
        # Remove Prometheus/Grafana
        kubectl delete namespace observability --ignore-not-found=true
        helm uninstall prometheus-stack -n observability 2>/dev/null || true
    fi
}

destroy_logging() {
    echo -e "${RED}🔍 Removing logging infrastructure...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy logging${NC}"
    else
        kubectl delete namespace logging --ignore-not-found=true
        kubectl delete -f k8s/envs/dev/logging/ --ignore-not-found=true 2>/dev/null || true
    fi
}

cleanup_external_monitoring() {
    if [ "$SKIP_EXTERNAL_CLEANUP" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping external monitoring cleanup${NC}"
        return 0
    fi
    
    echo -e "${RED}🔗 Cleaning up external monitoring integrations...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would cleanup external integrations${NC}"
    else
        echo -e "${BLUE}Note: External DataDog, New Relic, and Elasticsearch data will persist${NC}"
        echo -e "${BLUE}Manual cleanup may be required in external service UIs${NC}"
    fi
}

destroy_network_policies() {
    start_phase "Network Policies Cleanup"
    print_section "🌐 DESTROYING NETWORK POLICIES"
    
    echo -e "${RED}🔗 Removing network security policies...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy network policies${NC}"
    else
        kubectl delete networkpolicies --all --all-namespaces --ignore-not-found=true
        kubectl delete -f k8s/envs/dev/network-policies/ --ignore-not-found=true 2>/dev/null || true
    fi
    
    complete_phase "Network Policies Cleanup"
}

destroy_ssl_certificates() {
    start_phase "SSL/TLS Certificates Cleanup"
    print_section "🔐 DESTROYING SSL/TLS CERTIFICATES"
    
    echo -e "${RED}📜 Removing SSL/TLS certificates...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy SSL certificates${NC}"
    else
        # Remove certificates
        kubectl delete certificates --all --all-namespaces --ignore-not-found=true
        
        # Remove cert-manager
        kubectl delete namespace cert-manager --ignore-not-found=true
        helm uninstall cert-manager -n cert-manager 2>/dev/null || true
        
        # Remove ClusterIssuers
        kubectl delete clusterissuers --all --ignore-not-found=true
    fi
    
    complete_phase "SSL/TLS Certificates Cleanup"
}

destroy_security_policies() {
    start_phase "Security Policies Cleanup"
    print_section "🔒 DESTROYING SECURITY POLICIES"
    
    echo -e "${RED}🛡️ Removing security policies...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy security policies${NC}"
    else
        # Remove OPA Gatekeeper
        kubectl delete namespace gatekeeper-system --ignore-not-found=true
        helm uninstall gatekeeper -n gatekeeper-system 2>/dev/null || true
        
        # Remove security constraints
        kubectl delete constraints --all --ignore-not-found=true
    fi
    
    complete_phase "Security Policies Cleanup"
}

destroy_service_mesh() {
    start_phase "Service Mesh Cleanup"
    print_section "🌐 DESTROYING SERVICE MESH"
    
    echo -e "${RED}🔗 Removing service mesh...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy service mesh${NC}"
    else
        # Remove Consul from Kubernetes
        kubectl delete namespace consul --ignore-not-found=true
        helm uninstall consul -n consul 2>/dev/null || true
        
        # Consul servers are destroyed with Terraform
        echo "Consul server cluster will be destroyed with Terraform"
    fi
    
    complete_phase "Service Mesh Cleanup"
}

destroy_configuration_management() {
    start_phase "Configuration Management Cleanup"
    print_section "⚙️ DESTROYING CONFIGURATION MANAGEMENT"
    
    echo -e "${RED}🔧 Removing configuration management...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy configuration management${NC}"
    else
        # Ansible Tower and Puppet Enterprise are destroyed with Terraform
        echo "Ansible Tower and Puppet Enterprise will be destroyed with Terraform"
        
        # Clean up any local ansible artifacts
        rm -rf ansible/inventory/terraform-inventory.py.bak 2>/dev/null || true
    fi
    
    complete_phase "Configuration Management Cleanup"
}

destroy_infrastructure() {
    start_phase "Infrastructure Destruction"
    print_section "🏗️ DESTROYING MULTI-CLOUD INFRASTRUCTURE"
    
    # Set environment variables for Terraform
    export AWS_PROFILE="$AWS_PROFILE"
    export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
    export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
    
    echo -e "${RED}💥 Destroying infrastructure via Terraform...${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    [ -n "$GCP_PROJECT_ID" ] && echo -e "   GCP Project: $GCP_PROJECT_ID"
    [ -n "$AZURE_SUBSCRIPTION_ID" ] && echo -e "   Azure Subscription: $AZURE_SUBSCRIPTION_ID"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would execute: make destroy ENV=$ENV REGION=$REGION${NC}"
        cd "$PROJECT_ROOT/terraform"
        make plan-destroy ENV="$ENV" REGION="$REGION" 2>/dev/null || echo "Plan-destroy not available"
    else
        cd "$PROJECT_ROOT/terraform"
        
        # Pre-cleanup to handle dependencies
        echo -e "${BLUE}🧹 Running pre-destroy cleanup...${NC}"
        if [ -f "$PROJECT_ROOT/terraform/scripts/pre-destroy-cleanup.sh" ]; then
            ./scripts/pre-destroy-cleanup.sh || echo "Pre-cleanup had issues"
        fi
        
        # Main destruction
        if [ "$AUTO_APPROVE" == "true" ] || [ "$FORCE_DESTROY" == "true" ]; then
            make destroy ENV="$ENV" REGION="$REGION" TERRAFORM_ARGS="-auto-approve"
        else
            make destroy ENV="$ENV" REGION="$REGION"
        fi
        
        if [ $? -ne 0 ]; then
            fail_phase "Infrastructure Destruction" "Terraform destroy failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Infrastructure destroyed successfully${NC}"
    complete_phase "Infrastructure Destruction"
    cd "$PROJECT_ROOT"
}

# ============================================================================
# POST-DESTRUCTION CLEANUP
# ============================================================================

cleanup_state_files() {
    print_section "🧹 CLEANING UP STATE FILES"
    
    echo -e "${RED}🗑️ Removing state files and artifacts...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would cleanup state files${NC}"
        return 0
    fi
    
    if [ "$PRESERVE_DATA" != "true" ]; then
        # Remove local state files
        find terraform -name "terraform.tfstate*" -delete 2>/dev/null || true
        find terraform -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
        
        # Remove generated files
        rm -f .env ci-cd/.env 2>/dev/null || true
        find . -name "*.bak" -delete 2>/dev/null || true
        
        echo -e "${GREEN}✅ State files cleaned up${NC}"
    else
        echo -e "${YELLOW}⚠️ State files preserved (PRESERVE_DATA=true)${NC}"
        PRESERVED_RESOURCES+=("Local state files")
    fi
}

cleanup_docker_images() {
    print_section "🐳 CLEANING UP DOCKER IMAGES"
    
    echo -e "${RED}🗑️ Removing local Docker images...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would cleanup Docker images${NC}"
        return 0
    fi
    
    # Remove project-specific images
    docker images | grep -E "(frontend|backend|$ENV)" | awk '{print $3}' | xargs docker rmi -f 2>/dev/null || true
    
    # Clean up dangling images
    docker image prune -f 2>/dev/null || true
    
    echo -e "${GREEN}✅ Docker images cleaned up${NC}"
}

destroy_bootstrap_infrastructure() {
    print_section "🏗️ DESTROYING BOOTSTRAP INFRASTRUCTURE"
    
    echo -e "${RED}⚠️  WARNING: This will destroy the Terraform state backend!${NC}"
    echo -e "${RED}💀 This includes S3 buckets and DynamoDB tables used for state storage${NC}"
    
    if [ "$PRESERVE_DATA" == "true" ]; then
        echo -e "${YELLOW}💾 Preserving bootstrap infrastructure (PRESERVE_DATA=true)${NC}"
        PRESERVED_RESOURCES+=("Bootstrap infrastructure (S3/DynamoDB)")
        return 0
    fi
    
    if [ "$AUTO_APPROVE" != "true" ] && [ "$FORCE_DESTROY" != "true" ]; then
        echo -e "${YELLOW}Do you want to destroy the Terraform state backend infrastructure?${NC}"
        echo -e "${YELLOW}This will delete S3 buckets and DynamoDB tables.${NC}"
        read -p "Type 'DESTROY-BACKEND' to confirm: " backend_confirmation
        
        if [ "$backend_confirmation" != "DESTROY-BACKEND" ]; then
            echo -e "${GREEN}✅ Bootstrap infrastructure preserved${NC}"
            PRESERVED_RESOURCES+=("Bootstrap infrastructure")
            return 0
        fi
    fi
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would destroy bootstrap infrastructure${NC}"
        echo -e "   - S3 bucket for Terraform state"
        echo -e "   - DynamoDB table for state locking"
        echo -e "   - GCS bucket (if exists)"
        return 0
    fi
    
    # Change to bootstrap directory
    if [ -d "$PROJECT_ROOT/terraform/bootstrap" ]; then
        cd "$PROJECT_ROOT/terraform/bootstrap"
        
        if [ -f "terraform.tfstate" ]; then
            echo -e "${RED}💥 Destroying bootstrap infrastructure...${NC}"
            
            # Set environment variables
            export AWS_PROFILE="$AWS_PROFILE"
            export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
            
            # Initialize terraform (in case it's not initialized)
            terraform init 2>/dev/null || true
            
            # Destroy bootstrap infrastructure
            if terraform destroy -auto-approve; then
                echo -e "${GREEN}✅ Bootstrap infrastructure destroyed${NC}"
                
                # Clean up local state
                rm -f terraform.tfstate terraform.tfstate.backup
                rm -f generated/backend-config.json
                rm -f .terraform.lock.hcl
                rm -rf .terraform/
                
                # Restore original terragrunt.hcl if backup exists
                if [ -f "$PROJECT_ROOT/terraform/terragrunt.hcl.backup" ]; then
                    mv "$PROJECT_ROOT/terraform/terragrunt.hcl.backup" "$PROJECT_ROOT/terraform/terragrunt.hcl"
                    echo -e "${GREEN}✅ Terragrunt configuration restored${NC}"
                fi
                
            else
                echo -e "${YELLOW}⚠️ Bootstrap destruction had issues - some resources may remain${NC}"
                FAILED_PHASES+=("Bootstrap Infrastructure Destruction")
            fi
        else
            echo -e "${YELLOW}⚠️ No bootstrap state found${NC}"
        fi
        
        cd "$PROJECT_ROOT"
    else
        echo -e "${YELLOW}⚠️ Bootstrap directory not found${NC}"
    fi
}

verify_destruction() {
    print_section "✅ VERIFYING DESTRUCTION"
    
    echo -e "${BLUE}🔍 Verifying resource destruction...${NC}"
    
    # Check if any resources remain
    local remaining_resources=()
    
    # Check Kubernetes
    local k8s_namespaces=$(kubectl get namespaces --no-headers 2>/dev/null | grep -E "(frontend-dev|backend-dev|datadog|consul|argocd)" | wc -l)
    if [ "$k8s_namespaces" -gt 0 ]; then
        remaining_resources+=("$k8s_namespaces Kubernetes namespaces")
    fi
    
    # Check Terraform state
    cd "terraform/envs/$ENV/$REGION" 2>/dev/null || true
    local tf_resources=$(terragrunt state list 2>/dev/null | wc -l)
    if [ "$tf_resources" -gt 0 ]; then
        remaining_resources+=("$tf_resources Terraform resources")
    fi
    cd - >/dev/null
    
    if [ ${#remaining_resources[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All resources successfully destroyed${NC}"
    else
        echo -e "${YELLOW}⚠️ Some resources may still exist:${NC}"
        printf "${YELLOW}   • %s${NC}\n" "${remaining_resources[@]}"
    fi
}

# ============================================================================
# DESTRUCTION SUMMARY
# ============================================================================

print_destruction_summary() {
    print_section "💀 DESTRUCTION SUMMARY"
    
    echo -e "${RED}💥 Destruction Statistics:${NC}"
    echo -e "   Total Phases: ${#DESTRUCTION_PHASES[@]}"
    echo -e "   Successful: ${GREEN}${#SUCCESSFUL_PHASES[@]}${NC}"
    echo -e "   Failed: ${RED}${#FAILED_PHASES[@]}${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   Timestamp: $TIMESTAMP"
    echo -e "   Log File: $LOG_FILE"
    
    if [ ${#SUCCESSFUL_PHASES[@]} -gt 0 ]; then
        echo -e "\n${GREEN}✅ Successfully Destroyed:${NC}"
        printf "${GREEN}   • %s${NC}\n" "${SUCCESSFUL_PHASES[@]}"
    fi
    
    if [ ${#FAILED_PHASES[@]} -gt 0 ]; then
        echo -e "\n${RED}❌ Failed to Destroy:${NC}"
        printf "${RED}   • %s${NC}\n" "${FAILED_PHASES[@]}"
    fi
    
    if [ ${#PRESERVED_RESOURCES[@]} -gt 0 ]; then
        echo -e "\n${BLUE}💾 Preserved Resources:${NC}"
        printf "${BLUE}   • %s${NC}\n" "${PRESERVED_RESOURCES[@]}"
    fi
    
    # Backup information
    if [ "$SKIP_BACKUPS" != "true" ]; then
        echo -e "\n${BLUE}💾 Backup Information:${NC}"
        echo -e "   Backup Directory: $BACKUP_DIR"
        echo -e "   Terraform State: Backed up"
        echo -e "   Kubernetes Configs: Backed up"
        echo -e "   Application Data: Documented"
    fi
    
    # Next steps
    echo -e "\n${BLUE}🔗 Manual Cleanup Required:${NC}"
    print_manual_cleanup_steps
    
    if [ ${#FAILED_PHASES[@]} -eq 0 ]; then
        echo -e "\n${RED}💀 DESTRUCTION COMPLETED SUCCESSFULLY! 💀${NC}"
        echo -e "${GREEN}Your multi-cloud DevOps platform has been safely destroyed.${NC}"
        log "SUCCESS" "Full destruction completed successfully"
    else
        echo -e "\n${YELLOW}⚠️  DESTRUCTION COMPLETED WITH WARNINGS${NC}"
        echo -e "${YELLOW}Some resources may require manual cleanup.${NC}"
        log "WARNING" "Destruction completed with some failures"
    fi
}

print_manual_cleanup_steps() {
    echo -e "   1. Verify external services (DataDog, New Relic, Elasticsearch) for orphaned data"
    echo -e "   2. Check cloud consoles for any remaining resources"
    echo -e "   3. Review DNS records for cleanup"
    echo -e "   4. Clean up external integrations and webhooks"
    echo -e "   5. Remove any domain certificates from external CAs"
    echo -e "   6. Verify all costs have stopped accruing"
}

# ============================================================================
# CLEANUP FUNCTIONS
# ============================================================================

cleanup() {
    echo -e "\n${YELLOW}🧹 Performing final cleanup...${NC}"
    
    # Remove any temporary files
    rm -f /tmp/destroy-*.yaml 2>/dev/null || true
    
    log "INFO" "Final cleanup completed"
}

cleanup_on_error() {
    echo -e "\n${RED}❌ Destruction failed. Performing cleanup...${NC}"
    cleanup
    
    echo -e "${BLUE}📋 Troubleshooting Information:${NC}"
    echo -e "   Log file: $LOG_FILE"
    echo -e "   Failed phases: ${FAILED_PHASES[*]}"
    echo -e "   Check logs for detailed error information"
    echo -e "   Your infrastructure may be in a partially destroyed state"
    
    log "ERROR" "Destruction failed and cleanup completed"
    exit 1
}

# ============================================================================
# HELP AND USAGE
# ============================================================================

show_help() {
    cat << 'EOF'
🚨 Multi-Cloud DevOps Platform Destruction Script

USAGE:
    ./destroy.sh [OPTIONS]

ENVIRONMENT OPTIONS:
    -e, --env ENV                 Environment to destroy (default: dev)
    -r, --region REGION           AWS region (default: us-east-2)
    -p, --profile PROFILE         AWS profile (default: default)
    --gcp-project-id ID           GCP project ID
    --azure-subscription-id ID    Azure subscription ID

SAFETY OPTIONS:
    --auto-approve                Skip all confirmation prompts
    --force-destroy               Force destruction even in production
    --preserve-data               Keep backups and state files (default: true)
    --skip-backups                Skip backup creation
    --skip-external-cleanup       Skip external service cleanup
    --dry-run                     Show what would be destroyed without executing

OTHER OPTIONS:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose logging

EXAMPLES:
    # Safe destruction with backups
    ./destroy.sh -e dev

    # Quick destruction without backups
    ./destroy.sh -e dev --skip-backups --auto-approve

    # Dry run to see what would be destroyed
    ./destroy.sh --dry-run

    # Force destroy production (dangerous!)
    ./destroy.sh -e prod --force-destroy --auto-approve

DESTRUCTION PHASES (in reverse order):
    1. Integration Testing
    2. Performance Monitoring
    3. Compliance Scanning
    4. Custom DNS
    5. Disaster Recovery
    6. API Gateway
    7. Applications
    8. CI/CD Pipeline
    9. Observability Stack
    10. Network Policies
    11. SSL/TLS Certificates
    12. Security Policies
    13. Service Mesh
    14. Configuration Management
    15. Infrastructure (Terraform)

SAFETY FEATURES:
    • Requires explicit confirmation for destruction
    • Creates backups by default
    • Preserves critical data unless specified
    • Extra protection for production environments
    • Comprehensive logging
    • Dry-run capability

⚠️ WARNING: This will destroy your entire multi-cloud infrastructure!
Make sure you have proper backups before proceeding.
EOF
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

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
                shift
                ;;
            --preserve-data)
                PRESERVE_DATA=true
                shift
                ;;
            --skip-backups)
                SKIP_BACKUPS=true
                shift
                ;;
            --skip-external-cleanup)
                SKIP_EXTERNAL_CLEANUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                set -x
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
    # Set up error handling
    trap cleanup_on_error ERR
    trap cleanup EXIT
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize logging
    log "INFO" "Starting Multi-Cloud DevOps Platform destruction"
    log "INFO" "Environment: $ENV, Region: $REGION, Dry Run: $DRY_RUN"
    
    # Print banner
    print_banner
    
    # Display configuration
    echo -e "${BLUE}📋 Destruction Configuration:${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    [ -n "$GCP_PROJECT_ID" ] && echo -e "   GCP Project: $GCP_PROJECT_ID"
    [ -n "$AZURE_SUBSCRIPTION_ID" ] && echo -e "   Azure Subscription: $AZURE_SUBSCRIPTION_ID"
    echo -e "   Preserve Data: $PRESERVE_DATA"
    echo -e "   Skip Backups: $SKIP_BACKUPS"
    echo -e "   Dry Run: $DRY_RUN"
    echo -e "   Log File: $LOG_FILE"
    
    # Validation phase
    validate_prerequisites
    validate_environment
    
    # Safety confirmation
    confirm_destruction
    
    # Backup phase
    create_backups
    
    # Main destruction phases (in reverse order)
    destroy_integration_testing
    destroy_performance_monitoring
    destroy_compliance_scanning
    destroy_custom_dns
    destroy_disaster_recovery
    destroy_api_gateway
    destroy_applications
    destroy_cicd_pipeline
    destroy_observability_stack
    destroy_network_policies
    destroy_ssl_certificates
    destroy_security_policies
    destroy_service_mesh
    destroy_configuration_management
    destroy_infrastructure
    
    # Post-destruction cleanup
    cleanup_state_files
    cleanup_docker_images
    
    # Optionally destroy bootstrap infrastructure (last step)
    destroy_bootstrap_infrastructure
    
    verify_destruction
    
    # Summary and next steps
    print_destruction_summary
}

# Execute main function with all arguments
main "$@"
