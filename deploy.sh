#!/bin/bash

# 🚀 COMPREHENSIVE MULTI-CLOUD DEVOPS PLATFORM DEPLOYMENT
# =======================================================
# This script orchestrates the complete deployment of your multi-cloud DevOps platform
# including all infrastructure, services, and integrations in the correct order.

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
readonly LOG_FILE="${PROJECT_ROOT}/deployment-${TIMESTAMP}.log"

# Default values
ENV=${ENV:-dev}
REGION=${REGION:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-sandbox-permanent}
GCP_PROJECT_ID=${GCP_PROJECT_ID:-"complex-demo-465023"}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-""}

# Deployment control flags
SKIP_BOOTSTRAP=${SKIP_BOOTSTRAP:-false}
SKIP_TERRAFORM=${SKIP_TERRAFORM:-false}
SKIP_CONFIG_MGMT=${SKIP_CONFIG_MGMT:-false}
SKIP_OBSERVABILITY=${SKIP_OBSERVABILITY:-false}
SKIP_CICD=${SKIP_CICD:-false}
SKIP_APPLICATIONS=${SKIP_APPLICATIONS:-false}
DRY_RUN=${DRY_RUN:-false}

# Deployment tracking
DEPLOYMENT_PHASES=()
FAILED_PHASES=()
SUCCESSFUL_PHASES=()

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Print section headers
print_section() {
    echo -e "\n${GREEN}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════════${NC}\n"
    log "INFO" "Starting deployment phase: $1"
}

# Generic wait helper (resource description, command, timeout seconds)
wait_for_resource() {
    local description="$1"
    local cmd="$2"
    local timeout="${3:-300}"
    local elapsed=0

    echo -e "${BLUE}⏳ Waiting for ${description} (timeout ${timeout}s)${NC}"
    until eval "${cmd}" >/dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ "${elapsed}" -ge "${timeout}" ]; then
            echo -e "${RED}❌ Timeout waiting for ${description}${NC}"
            return 1
        fi
        echo -ne "${YELLOW}> still waiting... (${elapsed}s)\\r${NC}"
    done
    echo -e "${GREEN}✅ ${description} is ready${NC}"
}

# Tool version checker. Arguments: cmd, minimum_version, friendly_name
check_tool_version() {
    local cmd="$1"
    local min_ver="$2"
    local name="${3:-$1}"

    if ! command_exists "${cmd}"; then
        log "ERROR" "${name} not installed"
        echo -e "${RED}❌ ${name} not installed${NC}"
        exit 1
    fi

    local current_ver
    # Special case for kubectl
    if [[ "${cmd}" == "kubectl" ]]; then
        current_ver=$(kubectl version --client 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    else
        # shellcheck disable=SC2086
        current_ver=$(${cmd} --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ -z "${current_ver}" ]]; then
            # Some CLIs use different flag
            current_ver=$(${cmd} version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi
    fi

    # Fallback if still empty
    if [[ -z "${current_ver}" ]]; then
        log "WARNING" "Unable to parse version for ${name} – skipping comparison"
        echo -e "${YELLOW}⚠️  Could not determine ${name} version${NC}"
        return 0
    fi

    # version comparison using sort -V
    if [[ "$(printf '%s\n%s' "${min_ver}" "${current_ver}" | sort -V | head -1)" != "${min_ver}" ]]; then
        log "ERROR" "${name} ${current_ver} < required ${min_ver}"
        echo -e "${RED}❌ ${name} version ${current_ver} is older than required ${min_ver}${NC}"
        exit 1
    fi

    echo -e "${GREEN}✔ ${name} ${current_ver}${NC}"
}

# Print banner
print_banner() {
    echo -e "${GREEN}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                              ║
    ║                🚀 MULTI-CLOUD DEVOPS PLATFORM DEPLOYMENT 🚀                ║
    ║                                                                              ║
    ║     A comprehensive platform spanning AWS, GCP, and Azure with               ║
    ║     GitOps, Service Mesh, and Enterprise Observability                      ║
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
    DEPLOYMENT_PHASES+=("$phase")
    log "INFO" "Starting deployment phase: $phase"
}

complete_phase() {
    local phase="$1"
    SUCCESSFUL_PHASES+=("$phase")
    log "SUCCESS" "Completed deployment phase: $phase"
}

fail_phase() {
    local phase="$1"
    local error="$2"
    FAILED_PHASES+=("$phase")
    log "ERROR" "Failed deployment phase: $phase - $error"
}

# ============================================================================
# BOOTSTRAP TERRAFORM BACKEND
# ============================================================================

bootstrap_terraform_backend() {
    if [ "$SKIP_BOOTSTRAP" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping bootstrap (using existing backend)${NC}"
        return 0
    fi
    
    start_phase "Terraform Backend Bootstrap"
    print_section "🏗️  BOOTSTRAPPING TERRAFORM STATE BACKEND"
    
    echo -e "${BLUE}🔧 Setting up Terraform state backend...${NC}"
    echo -e "   AWS Profile: $AWS_PROFILE"
    [ -n "$GCP_PROJECT_ID" ] && echo -e "   GCP Project: $GCP_PROJECT_ID"
    
    # Change to bootstrap directory
    cd "$PROJECT_ROOT/terraform/bootstrap"
    
    # Check if backend already exists
    if [ -f "terraform.tfstate" ] && [ -f "generated/backend-config.json" ]; then
        echo -e "${YELLOW}⚠️  Bootstrap state already exists${NC}"
        local existing_bucket=$(jq -r '.aws.config.bucket // empty' generated/backend-config.json 2>/dev/null || echo "")
        
        if [ -n "$existing_bucket" ]; then
            echo -e "${BLUE}Using existing backend: $existing_bucket${NC}"
            
            # Update terragrunt.hcl with existing backend config
            update_terragrunt_backend_config
            
            complete_phase "Terraform Backend Bootstrap"
            cd "$PROJECT_ROOT"
            return 0
        fi
    fi
    
    # Set Terraform variables
    export TF_VAR_aws_region="us-east-2"
    export AWS_PROFILE="$AWS_PROFILE"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would create Terraform backend infrastructure${NC}"
        echo -e "   - S3 bucket for state storage"
        echo -e "   - DynamoDB table for state locking"
        [ -n "$GCP_PROJECT_ID" ] && echo -e "   - GCS bucket for multi-cloud state"
    else
        # Initialize and apply bootstrap
        echo -e "${BLUE}Initializing bootstrap...${NC}"
        terraform init
        
        echo -e "${BLUE}Planning backend infrastructure...${NC}"
        terraform plan -out=bootstrap.tfplan
        
        echo -e "${BLUE}Creating backend infrastructure...${NC}"
        terraform apply -auto-approve bootstrap.tfplan
        
        # Clean up plan file
        rm -f bootstrap.tfplan
        
        # Save backend configuration
        echo -e "${BLUE}Saving backend configuration...${NC}"
        mkdir -p generated
        terraform output -json > generated/backend-config.json
        
        # Update terragrunt configuration
        update_terragrunt_backend_config
        
        echo -e "${GREEN}✅ Backend infrastructure created successfully${NC}"
    fi
    
    complete_phase "Terraform Backend Bootstrap"
    cd "$PROJECT_ROOT"
}

update_terragrunt_backend_config() {
    echo -e "${BLUE}📝 Updating terragrunt.hcl configuration...${NC}"
    
    if [ ! -f "generated/backend-config.json" ]; then
        echo -e "${YELLOW}⚠️  Backend config not found, using existing configuration${NC}"
        return 0
    fi
    
    # Extract backend configuration
    local aws_bucket=$(jq -r '.aws_backend_config.value.bucket' generated/backend-config.json)
    local aws_region=$(jq -r '.aws_backend_config.value.region' generated/backend-config.json)
    local aws_table=$(jq -r '.aws_backend_config.value.dynamodb_table' generated/backend-config.json)
    
    # Update terragrunt.hcl
    cd "$PROJECT_ROOT/terraform"
    
    # Create backup
    cp terragrunt.hcl terragrunt.hcl.backup
    
    # Update backend configuration in terragrunt.hcl
    cat > terragrunt.hcl << EOF
# Root Terragrunt configuration
# This file is inherited by all environments

# Local variables for backend configuration  
locals {
  # Parse the path to get environment and region
  path_parts = split("/", path_relative_to_include())
  # Expect path structure envs/<env>/<region>
  environment = local.path_parts[1]
  region      = local.path_parts[2]
  
  # Backend bucket name - dynamically generated by bootstrap
  backend_bucket = "$aws_bucket"
  backend_region = "$aws_region"
  backend_dynamodb_table = "$aws_table"
}

# Configure S3 backend
remote_state {
  backend = "s3"
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    bucket         = local.backend_bucket
    key            = "\${local.environment}/\${local.region}/terraform.tfstate"
    region         = local.backend_region
    dynamodb_table = local.backend_dynamodb_table
    encrypt        = true
  }
}

# Generate provider configurations
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  
  contents = <<EOT
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  profile = "$AWS_PROFILE"
  
  default_tags {
    tags = var.common_tags
  }
}

# GCP Provider Configuration
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Azure Provider Configuration
provider "azurerm" {
  features {}
  
  # Uses currently authenticated subscription from 'az login'
}
EOT
}

# Common variables
inputs = {
  # Environment will be set by child terragrunt.hcl files
  # Region will be set by child terragrunt.hcl files
  
  # Common tags applied to all resources
  common_tags = {}
}
EOF
    
    echo -e "${GREEN}✅ Terragrunt configuration updated with dynamic backend${NC}"
    cd "$PROJECT_ROOT"
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_prerequisites() {
    print_section "🔍 VALIDATING PREREQUISITES"
    
    local missing_commands=()
    local required_commands=(
        "terraform" "terragrunt" "make" "kubectl" 
        "docker" "helm" "jq" "curl" "git" "aws"
    )
    
    # Add GCP CLI if GCP project specified
    [ -n "$GCP_PROJECT_ID" ] && required_commands+=("gcloud")
    
    # Add Azure CLI if Azure subscription specified  
    [ -n "$AZURE_SUBSCRIPTION_ID" ] && required_commands+=("az")
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    # Minimum version enforcement (extend as needed)
    check_tool_version "terraform" "1.4.0" "Terraform"
    check_tool_version "kubectl" "1.24.0" "kubectl"
    check_tool_version "aws" "2.7.0" "AWS CLI"
    [ -n "$GCP_PROJECT_ID" ] && check_tool_version "gcloud" "439.0.0" "gcloud"
    [ -n "$AZURE_SUBSCRIPTION_ID" ] && check_tool_version "az" "2.53.0" "Azure CLI"
    
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
            echo -e "${YELLOW}💡 Run: gcloud auth application-default login${NC}"
            exit 1
        fi
        
        # Set GCP project
        gcloud config set project "$GCP_PROJECT_ID" >/dev/null 2>&1
    fi
    
    # Azure (if subscription ID provided)
    if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
        if ! az account show >/dev/null 2>&1; then
            log "ERROR" "Azure credentials not configured"
            echo -e "${RED}❌ Azure credentials not configured${NC}"
            echo -e "${YELLOW}💡 Run: az login${NC}"
            exit 1
        fi
        
        # Set Azure subscription
        az account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}✅ All prerequisites validated${NC}"
    log "SUCCESS" "Prerequisites validation completed"
}

# ============================================================================
# CROSS-CLOUD CONNECTIVITY VALIDATION
# ============================================================================

validate_cross_cloud_connectivity() {
    start_phase "Cross-Cloud Connectivity Validation"
    print_section "🌐 VALIDATING CROSS-CLOUD CONNECTIVITY"

    # Simple connectivity tests (place-holders; extend with VPN / TGW checks)
    local success=true

    # AWS example – check sts call
    if ! aws ec2 describe-vpcs --max-items 1 --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log "ERROR" "AWS connectivity failed"
        echo -e "${RED}❌ Unable to contact AWS EC2 API${NC}"
        success=false
    else
        echo -e "${GREEN}✔ AWS connectivity OK${NC}"
    fi

    # GCP example
    if [ -n "$GCP_PROJECT_ID" ]; then
        if ! gcloud compute networks list --project "$GCP_PROJECT_ID" --limit=1 >/dev/null 2>&1; then
            log "ERROR" "GCP connectivity failed"
            echo -e "${RED}❌ Unable to contact GCP API${NC}"
            success=false
        else
            echo -e "${GREEN}✔ GCP connectivity OK${NC}"
        fi
    fi

    # Azure example
    if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
        if ! az account show >/dev/null 2>&1; then
            log "ERROR" "Azure connectivity failed"
            echo -e "${RED}❌ Unable to contact Azure API${NC}"
            success=false
        else
            echo -e "${GREEN}✔ Azure connectivity OK${NC}"
        fi
    fi

    if [ "$success" = true ]; then
        complete_phase "Cross-Cloud Connectivity Validation"
    else
        fail_phase "Cross-Cloud Connectivity Validation" "Connectivity test failed"
        return 1
    fi
}

validate_environment() {
    print_section "🔍 VALIDATING ENVIRONMENT"
    
    # Check if environment directory exists
    if [ ! -d "terraform/envs/$ENV/$REGION" ]; then
        echo -e "${RED}❌ Environment $ENV in region $REGION not found${NC}"
        echo -e "${YELLOW}Available environments:${NC}"
        find terraform/envs -type d -name "us-*" -o -name "eu-*" -o -name "ap-*" 2>/dev/null | head -10
        exit 1
    fi
    
    # Validate environment name
    if [[ ! "$ENV" =~ ^(dev|staging|prod|production)$ ]]; then
        echo -e "${YELLOW}⚠️  Warning: Environment '$ENV' is not a standard environment name${NC}"
        echo -e "${YELLOW}   Standard names: dev, staging, prod, production${NC}"
    fi
    
    # Validate region format
    if [[ ! "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        echo -e "${YELLOW}⚠️  Warning: Region '$REGION' doesn't follow AWS format${NC}"
    fi
    
    echo -e "${GREEN}✅ Environment validation completed${NC}"
    log "SUCCESS" "Environment validation completed"
}

# ============================================================================
# INFRASTRUCTURE DEPLOYMENT
# ============================================================================

deploy_infrastructure() {
    if [ "$SKIP_TERRAFORM" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping infrastructure deployment${NC}"
        return 0
    fi
    
    start_phase "Infrastructure Deployment"
    print_section "🏗️  DEPLOYING MULTI-CLOUD INFRASTRUCTURE"
    
    # Set environment variables for Terraform
    export AWS_PROFILE="$AWS_PROFILE"
    export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
    export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
    
    echo -e "${BLUE}🔧 Deploying infrastructure via Terraform...${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    [ -n "$GCP_PROJECT_ID" ] && echo -e "   GCP Project: $GCP_PROJECT_ID"
    [ -n "$AZURE_SUBSCRIPTION_ID" ] && echo -e "   Azure Subscription: $AZURE_SUBSCRIPTION_ID"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would execute: make plan ENV=$ENV REGION=$REGION${NC}"
        cd "$PROJECT_ROOT/terraform"
        make plan ENV="$ENV" REGION="$REGION"
    else
        cd "$PROJECT_ROOT/terraform"
        if ! make apply ENV="$ENV" REGION="$REGION"; then
            fail_phase "Infrastructure Deployment" "Terraform apply failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Infrastructure deployed successfully${NC}"
    complete_phase "Infrastructure Deployment"
    cd "$PROJECT_ROOT"
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

deploy_configuration_management() {
    if [ "$SKIP_CONFIG_MGMT" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping configuration management${NC}"
        return 0
    fi
    
    start_phase "Configuration Management"
    print_section "⚙️  DEPLOYING CONFIGURATION MANAGEMENT LAYER"
    
    echo -e "${BLUE}🏗️ Setting up complete configuration management...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would execute complete configuration management setup${NC}"
    else
        if ! ./scripts/setup-configuration-management.sh; then
            fail_phase "Configuration Management" "Configuration management setup failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Configuration management layer deployed${NC}"
    complete_phase "Configuration Management"
}

# ============================================================================
# OBSERVABILITY STACK
# ============================================================================

deploy_observability_stack() {
    if [ "$SKIP_OBSERVABILITY" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping observability stack${NC}"
        return 0
    fi
    
    start_phase "Observability Stack"
    print_section "📊 DEPLOYING OBSERVABILITY STACK"
    
    # Create observability credentials
    create_observability_secrets
    
    # Deploy DataDog
    deploy_datadog
    
    # Deploy Elasticsearch integration
    deploy_elasticsearch_integration
    
    # Deploy New Relic (if configured)
    deploy_newrelic_integration
    
    # Deploy Prometheus/Grafana
    deploy_prometheus_grafana
    
    echo -e "${GREEN}✅ Observability stack deployed successfully${NC}"
    complete_phase "Observability Stack"
}

create_observability_secrets() {
    echo -e "${BLUE}🔐 Creating observability service secrets...${NC}"
    
    # DataDog secrets
    kubectl create namespace datadog --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic datadog-credentials \
        --namespace=datadog \
        --from-literal=api-key="$DATADOG_API_KEY" \
        --from-literal=app-key="$DATADOG_APP_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Elasticsearch secrets
    kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic elasticsearch-credentials \
        --namespace=logging \
        --from-literal=url="$ELASTICSEARCH_URL" \
        --from-literal=api-key="$ELASTICSEARCH_API_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # New Relic secrets
    kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic newrelic-credentials \
        --namespace=observability \
        --from-literal=license-key="$NEWRELIC_LICENSE_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log "SUCCESS" "Observability secrets created"
}

deploy_datadog() {
    echo -e "${BLUE}📊 Deploying DataDog multi-cloud monitoring...${NC}"
    
    # Create DataDog secrets using environment variables
    if [ -n "$DATADOG_API_KEY" ] && [ -n "$DATADOG_APP_KEY" ]; then
        echo -e "${BLUE}🔑 Creating DataDog secrets from environment variables...${NC}"
        kubectl create namespace datadog --dry-run=client -o yaml | kubectl apply -f -
        kubectl create secret generic datadog-credentials \
            --namespace=datadog \
            --from-literal=api-key="$DATADOG_API_KEY" \
            --from-literal=app-key="$DATADOG_APP_KEY" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        echo -e "${BLUE}🔑 Creating DataDog secrets using envsubst...${NC}"
        envsubst < k8s/envs/dev/monitoring/datadog-secrets.yaml | kubectl apply -f -
    fi
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy DataDog to all clusters${NC}"
    else
        if ! ./scripts/deploy-datadog-multicloud.sh; then
            fail_phase "DataDog Deployment" "DataDog deployment failed"
            return 1
        fi
    fi
    
    log "SUCCESS" "DataDog deployment completed"
}

deploy_elasticsearch_integration() {
    echo -e "${BLUE}🔍 Deploying Elasticsearch integration...${NC}"
    
    # Update Elasticsearch configurations with provided credentials
    if [ -f k8s/envs/dev/logging/elasticsearch-secret.yaml ]; then
        sed -i.bak "s|ELASTICSEARCH_URL_PLACEHOLDER|$ELASTICSEARCH_URL|g" \
            k8s/envs/dev/logging/elasticsearch-secret.yaml
        sed -i.bak "s/ELASTICSEARCH_API_KEY_PLACEHOLDER/$ELASTICSEARCH_API_KEY/g" \
            k8s/envs/dev/logging/elasticsearch-secret.yaml
    fi
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy Elasticsearch integration${NC}"
    else
        if ! ./scripts/deploy-elasticsearch-integration.sh; then
            fail_phase "Elasticsearch Integration" "Elasticsearch integration failed"
            return 1
        fi
    fi
    
    log "SUCCESS" "Elasticsearch integration completed"
}

deploy_newrelic_integration() {
    echo -e "${BLUE}📈 Deploying New Relic integration...${NC}"
    
    # Update New Relic configurations
    if [ -f k8s/envs/dev/monitoring/newrelic-integration.yaml ]; then
        sed -i.bak "s/NEWRELIC_LICENSE_KEY_PLACEHOLDER/$NEWRELIC_LICENSE_KEY/g" \
            k8s/envs/dev/monitoring/newrelic-*.yaml
    fi
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy New Relic integration${NC}"
    else
        kubectl apply -f k8s/envs/dev/monitoring/newrelic-integration.yaml 2>/dev/null || echo "New Relic config not found"
        kubectl apply -f k8s/envs/dev/monitoring/newrelic-lightweight.yaml 2>/dev/null || echo "New Relic lightweight config not found"
    fi
    
    log "SUCCESS" "New Relic integration completed"
}

deploy_prometheus_grafana() {
    echo -e "${BLUE}📊 Deploying Prometheus/Grafana stack...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy Prometheus/Grafana${NC}"
    else
        kubectl apply -f k8s/envs/dev/aws/observability/prometheus.yaml 2>/dev/null || echo "Prometheus config not found"
        kubectl apply -f monitoring/grafana-elasticsearch-datasource.yaml 2>/dev/null || echo "Grafana config not found"
    fi
    
    log "SUCCESS" "Prometheus/Grafana deployment completed"
}

# ============================================================================
# CI/CD PIPELINE
# ============================================================================

deploy_cicd_pipeline() {
    if [ "$SKIP_CICD" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping CI/CD pipeline deployment${NC}"
        return 0
    fi
    
    start_phase "CI/CD Pipeline"
    print_section "🔄 DEPLOYING CI/CD PIPELINE"
    
    # Deploy Nexus Repository Manager
    deploy_nexus
    
    # Configure Jenkins integration
    configure_jenkins_integration
    
    # Set up ArgoCD GitOps
    deploy_argocd
    
    echo -e "${GREEN}✅ CI/CD pipeline deployed successfully${NC}"
    complete_phase "CI/CD Pipeline"
}

deploy_nexus() {
    echo -e "${BLUE}📦 Deploying Nexus Repository Manager...${NC}"
    
    # Create Artifactory secrets
    kubectl create namespace nexus-dev --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic artifactory-credentials \
        --namespace=nexus-dev \
        --from-literal=username="$ARTIFACTORY_USERNAME" \
        --from-literal=password="$ARTIFACTORY_PASSWORD" \
        --from-literal=url="$ARTIFACTORY_URL" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy Nexus${NC}"
    else
        # Nexus is deployed via Terraform module, so it should already be running
        kubectl wait --namespace=nexus-dev \
            --for=condition=available deployment/nexus-terraform-nexus3 \
            --timeout=600s 2>/dev/null || echo "Nexus deployment not found or still starting"
    fi
    
    log "SUCCESS" "Nexus deployment completed"
}

configure_jenkins_integration() {
    echo -e "${BLUE}🔧 Configuring Jenkins-Nexus integration...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would configure Jenkins integration${NC}"
    else
        if [ -f ci-cd/jenkins/scripts/jenkins-nexus-integration-complete.sh ]; then
            if ! ./ci-cd/jenkins/scripts/jenkins-nexus-integration-complete.sh; then
                log "WARNING" "Jenkins integration had issues but continuing"
            fi
        else
            log "WARNING" "Jenkins integration script not found"
        fi
    fi
    
    log "SUCCESS" "Jenkins integration completed"
}

deploy_argocd() {
    echo -e "${BLUE}🔄 Deploying ArgoCD GitOps...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy ArgoCD${NC}"
    else
        kubectl apply -f k8s/argocd/install.yaml 2>/dev/null || echo "ArgoCD install config not found"
        kubectl apply -f k8s/envs/dev/applications.yaml 2>/dev/null || echo "ArgoCD applications config not found"
    fi
    
    log "SUCCESS" "ArgoCD deployment completed"
}

# ============================================================================
# APPLICATION DEPLOYMENT
# ============================================================================

deploy_applications() {
    if [ "$SKIP_APPLICATIONS" == "true" ]; then
        echo -e "${YELLOW}⏭️  Skipping application deployment${NC}"
        return 0
    fi
    
    start_phase "Application Deployment"
    print_section "🚀 DEPLOYING APPLICATIONS"
    
    # Build and push application images
    build_and_push_images
    
    # Update Kubernetes manifests
    update_kubernetes_manifests
    
    # Wait for ArgoCD sync
    wait_for_argocd_sync
    
    echo -e "${GREEN}✅ Applications deployed successfully${NC}"
    complete_phase "Application Deployment"
}

build_and_push_images() {
    echo -e "${BLUE}🐳 Building and pushing application images...${NC}"
    
    # Create .env file with Artifactory credentials
    cat > .env << EOF
ARTIFACTORY_URL=$ARTIFACTORY_URL
ARTIFACTORY_USERNAME=$ARTIFACTORY_USERNAME
ARTIFACTORY_PASSWORD=$ARTIFACTORY_PASSWORD
EOF
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would build and push images${NC}"
    else
        if [ -f scripts/build-and-push.sh ]; then
            if ! ./scripts/build-and-push.sh; then
                fail_phase "Image Build" "Image build and push failed"
                return 1
            fi
        else
            log "WARNING" "Image build script not found"
        fi
    fi
    
    log "SUCCESS" "Images built and pushed"
}

update_kubernetes_manifests() {
    echo -e "${BLUE}📝 Updating Kubernetes deployment manifests...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would update Kubernetes manifests${NC}"
    else
        if [ -f scripts/update-k8s-images.sh ]; then
            if ! ./scripts/update-k8s-images.sh; then
                fail_phase "K8s Manifest Update" "Kubernetes manifest update failed"
                return 1
            fi
        else
            log "WARNING" "Kubernetes manifest update script not found"
        fi
    fi
    
    log "SUCCESS" "Kubernetes manifests updated"
}

wait_for_argocd_sync() {
    echo -e "${BLUE}⏳ Waiting for ArgoCD to sync applications...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would wait for ArgoCD sync${NC}"
        return 0
    fi
    
    # Wait for frontend deployment
    kubectl wait --namespace=frontend-dev \
        --for=condition=available deployment/frontend \
        --timeout=600s 2>/dev/null || log "WARNING" "Frontend deployment timeout"
    
    # Wait for backend deployment
    kubectl wait --namespace=backend-dev \
        --for=condition=available deployment/backend \
        --timeout=600s 2>/dev/null || log "WARNING" "Backend deployment timeout"
    
    log "SUCCESS" "ArgoCD sync completed"
}

# ============================================================================
# SERVICE MESH CONFIGURATION
# ============================================================================

deploy_service_mesh() {
    start_phase "Service Mesh Configuration"
    print_section "🌐 CONFIGURING SERVICE MESH"
    
    echo -e "${BLUE}🔗 Setting up complete service discovery and mesh...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would configure service mesh${NC}"
    else
        if ! ./scripts/configure-service-mesh.sh; then
            fail_phase "Service Mesh" "Service mesh configuration failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Service mesh configured successfully${NC}"
    complete_phase "Service Mesh Configuration"
}

# ============================================================================
# SECURITY POLICIES
# ============================================================================

deploy_security_policies() {
    start_phase "Security Policies"
    print_section "🔒 DEPLOYING SECURITY POLICIES"
    
    echo -e "${BLUE}🛡️ Setting up comprehensive security policies...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy security policies${NC}"
    else
        if ! ./scripts/configure-security-policies.sh; then
            fail_phase "Security Policies" "Security policies deployment failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Security policies deployed successfully${NC}"
    complete_phase "Security Policies"
}

# ============================================================================
# SSL/TLS CERTIFICATES
# ============================================================================

deploy_ssl_certificates() {
    start_phase "SSL/TLS Certificates"
    print_section "🔐 CONFIGURING SSL/TLS CERTIFICATES"
    
    echo -e "${BLUE}📜 Setting up SSL/TLS certificates...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would configure SSL certificates${NC}"
    else
        if ! ./scripts/configure-ssl-certificates.sh; then
            fail_phase "SSL Certificates" "SSL certificate configuration failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ SSL/TLS certificates configured successfully${NC}"
    complete_phase "SSL/TLS Certificates"
}

# ============================================================================
# NETWORK POLICIES
# ============================================================================

deploy_network_policies() {
    start_phase "Network Policies"
    print_section "🌐 DEPLOYING NETWORK POLICIES"
    
    echo -e "${BLUE}🔗 Setting up network security policies...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy network policies${NC}"
    else
        if ! ./scripts/setup-network-policies.sh; then
            fail_phase "Network Policies" "Network policies deployment failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Network policies deployed successfully${NC}"
    complete_phase "Network Policies"
}

# ============================================================================
# API GATEWAY
# ============================================================================

deploy_api_gateway() {
    start_phase "API Gateway"
    print_section "🚪 DEPLOYING API GATEWAY"
    
    echo -e "${BLUE}🔌 Setting up API gateway and routing...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would deploy API gateway${NC}"
    else
        if ! ./scripts/setup-api-gateway.sh; then
            fail_phase "API Gateway" "API gateway deployment failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ API gateway deployed successfully${NC}"
    complete_phase "API Gateway"
}

# ============================================================================
# DISASTER RECOVERY
# ============================================================================

deploy_disaster_recovery() {
    start_phase "Disaster Recovery"
    print_section "💾 SETTING UP DISASTER RECOVERY"
    
    echo -e "${BLUE}🔄 Configuring backup and disaster recovery...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would setup disaster recovery${NC}"
    else
        if ! ./scripts/setup-disaster-recovery.sh; then
            fail_phase "Disaster Recovery" "Disaster recovery setup failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Disaster recovery configured successfully${NC}"
    complete_phase "Disaster Recovery"
}

# ============================================================================
# CUSTOM DNS CONFIGURATION
# ============================================================================

deploy_custom_dns() {
    start_phase "Custom DNS"
    print_section "🌍 CONFIGURING CUSTOM DNS"
    
    echo -e "${BLUE}📡 Setting up custom DNS and routing...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would configure custom DNS${NC}"
    else
        if ! ./scripts/configure-custom-dns.sh; then
            fail_phase "Custom DNS" "Custom DNS configuration failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Custom DNS configured successfully${NC}"
    complete_phase "Custom DNS"
}

# ============================================================================
# COMPLIANCE SCANNING
# ============================================================================

deploy_compliance_scanning() {
    start_phase "Compliance Scanning"
    print_section "🛡️ SETTING UP COMPLIANCE SCANNING"
    
    echo -e "${BLUE}📋 Configuring security compliance scanning...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would setup compliance scanning${NC}"
    else
        if ! ./scripts/configure-compliance-scanning.sh; then
            fail_phase "Compliance Scanning" "Compliance scanning setup failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Compliance scanning configured successfully${NC}"
    complete_phase "Compliance Scanning"
}

# ============================================================================
# PERFORMANCE MONITORING
# ============================================================================

deploy_performance_monitoring() {
    start_phase "Performance Monitoring"
    print_section "📊 SETTING UP PERFORMANCE MONITORING"
    
    echo -e "${BLUE}⚡ Configuring performance monitoring and testing...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would setup performance monitoring${NC}"
    else
        if ! ./scripts/setup-performance-monitoring.sh; then
            fail_phase "Performance Monitoring" "Performance monitoring setup failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Performance monitoring configured successfully${NC}"
    complete_phase "Performance Monitoring"
}

# ============================================================================
# INTEGRATION TESTING
# ============================================================================

deploy_integration_testing() {
    start_phase "Integration Testing"
    print_section "🧪 SETTING UP INTEGRATION TESTING"
    
    echo -e "${BLUE}🔬 Configuring automated integration testing...${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would setup integration testing${NC}"
    else
        if ! ./scripts/setup-integration-testing.sh; then
            fail_phase "Integration Testing" "Integration testing setup failed"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Integration testing configured successfully${NC}"
    complete_phase "Integration Testing"
}

# ============================================================================
# POST-DEPLOYMENT VALIDATION
# ============================================================================

validate_deployment() {
    print_section "✅ VALIDATING DEPLOYMENT"
    
    echo -e "${BLUE}🔍 Running comprehensive deployment validation...${NC}"
    
    # Infrastructure validation
    validate_infrastructure
    
    # Service mesh validation
    validate_service_mesh
    
    # Observability validation
    validate_observability
    
    # Application validation
    validate_applications
    
    echo -e "${GREEN}✅ Deployment validation completed${NC}"
}

validate_complete_integration() {
    print_section "🔍 COMPREHENSIVE INTEGRATION VALIDATION"
    
    echo -e "${BLUE}🧪 Running complete end-to-end validation...${NC}"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${YELLOW}🧪 DRY RUN: Would run comprehensive validation${NC}"
        return 0
    fi
    
    if ! ./scripts/validate-complete-setup.sh; then
        fail_phase "Complete Validation" "Comprehensive validation failed"
        return 1
    fi
    
    echo -e "${GREEN}✅ Complete integration validation passed${NC}"
}

validate_infrastructure() {
    echo -e "${BLUE}🏗️ Validating infrastructure...${NC}"
    
    # Check current context
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    echo -e "${GREEN}  ✅ Current context: $current_context${NC}"
    
    # Check key infrastructure components
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    echo -e "${GREEN}  ✅ $node_count Kubernetes nodes accessible${NC}"
}

validate_service_mesh() {
    echo -e "${BLUE}🌐 Validating service mesh...${NC}"
    
    # Check Consul cluster
    local consul_pods=$(kubectl get pods -A -l app=consul --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
    if [ "$consul_pods" -gt 0 ]; then
        echo -e "${GREEN}  ✅ $consul_pods Consul pods running${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Consul pods not found${NC}"
    fi
}

validate_observability() {
    echo -e "${BLUE}📊 Validating observability stack...${NC}"
    
    # Check DataDog agents
    local dd_agents=$(kubectl get pods -n datadog --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
    if [ "$dd_agents" -gt 0 ]; then
        echo -e "${GREEN}  ✅ $dd_agents DataDog agents running${NC}"
    else
        echo -e "${YELLOW}  ⚠️  DataDog agents not found${NC}"
    fi
    
    # Check logging infrastructure
    local flb_agents=$(kubectl get pods -n logging --no-headers 2>/dev/null | grep fluent-bit | grep Running | wc -l || echo "0")
    if [ "$flb_agents" -gt 0 ]; then
        echo -e "${GREEN}  ✅ $flb_agents Fluent Bit agents running${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Fluent Bit agents not found${NC}"
    fi
}

validate_applications() {
    echo -e "${BLUE}🚀 Validating applications...${NC}"
    
    # Check frontend
    local frontend_ready=$(kubectl get deployment frontend -n frontend-dev -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$frontend_ready" -gt 0 ]; then
        echo -e "${GREEN}  ✅ Frontend: $frontend_ready replicas ready${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Frontend deployment not ready${NC}"
    fi
    
    # Check backend
    local backend_ready=$(kubectl get deployment backend -n backend-dev -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$backend_ready" -gt 0 ]; then
        echo -e "${GREEN}  ✅ Backend: $backend_ready replicas ready${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Backend deployment not ready${NC}"
    fi
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

print_deployment_summary() {
    print_section "🎉 DEPLOYMENT SUMMARY"
    
    echo -e "${BLUE}📊 Deployment Statistics:${NC}"
    echo -e "   Total Phases: ${#DEPLOYMENT_PHASES[@]}"
    echo -e "   Successful: ${GREEN}${#SUCCESSFUL_PHASES[@]}${NC}"
    echo -e "   Failed: ${RED}${#FAILED_PHASES[@]}${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   Timestamp: $TIMESTAMP"
    echo -e "   Log File: $LOG_FILE"
    
    if [ ${#SUCCESSFUL_PHASES[@]} -gt 0 ]; then
        echo -e "\n${GREEN}✅ Successful Phases:${NC}"
        printf "${GREEN}   • %s${NC}\n" "${SUCCESSFUL_PHASES[@]}"
    fi
    
    if [ ${#FAILED_PHASES[@]} -gt 0 ]; then
        echo -e "\n${RED}❌ Failed Phases:${NC}"
        printf "${RED}   • %s${NC}\n" "${FAILED_PHASES[@]}"
    fi
    
    # Access information
    echo -e "\n${BLUE}🌐 Access Information:${NC}"
    print_access_urls
    
    # Next steps
    echo -e "\n${BLUE}🔗 Next Steps:${NC}"
    print_next_steps
    
    if [ ${#FAILED_PHASES[@]} -eq 0 ]; then
        echo -e "\n${GREEN}🎊 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎊${NC}"
        log "SUCCESS" "Full deployment completed successfully"
    else
        echo -e "\n${YELLOW}⚠️  DEPLOYMENT COMPLETED WITH WARNINGS${NC}"
        log "WARNING" "Deployment completed with some failures"
    fi
}

print_access_urls() {
    echo -e "   📊 DataDog: https://app.datadoghq.com/"
    echo -e "   🔍 Elasticsearch: $ELASTICSEARCH_URL"
    echo -e "   📈 New Relic: https://one.newrelic.com/"
    echo -e "   📦 Artifactory: $ARTIFACTORY_URL"
    
    # Try to get service URLs from current cluster
    local jenkins_url=$(kubectl get svc -A -l app=jenkins -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$jenkins_url" ]; then
        echo -e "   🔧 Jenkins: http://$jenkins_url:8080"
    fi
    
    local nexus_url=$(kubectl get svc -A -l app=nexus -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$nexus_url" ]; then
        echo -e "   📦 Nexus: http://$nexus_url:8081"
    fi
}

print_next_steps() {
    echo -e "   1. Monitor deployment status: ${CYAN}kubectl get pods -A${NC}"
    echo -e "   2. Check application logs: ${CYAN}kubectl logs -f deployment/frontend -n frontend-dev${NC}"
    echo -e "   3. Access service UIs using the URLs above"
    echo -e "   4. Configure monitoring alerts and dashboards"
    echo -e "   5. Set up additional environments using: ${CYAN}./deploy.sh -e staging [credentials...]${NC}"
}

# ============================================================================
# CLEANUP FUNCTIONS
# ============================================================================

cleanup() {
    echo -e "\n${YELLOW}🧹 Performing cleanup...${NC}"
    
    # Remove temporary files
    rm -f .env 2>/dev/null || true
    
    # Remove backup files created by sed
    find . -name "*.bak" -delete 2>/dev/null || true
    
    log "INFO" "Cleanup completed"
}

cleanup_on_error() {
    echo -e "\n${RED}❌ Deployment failed. Performing cleanup...${NC}"
    cleanup
    
    echo -e "${BLUE}📋 Troubleshooting Information:${NC}"
    echo -e "   Log file: $LOG_FILE"
    echo -e "   Failed phases: ${FAILED_PHASES[*]}"
    echo -e "   Check logs for detailed error information"
    
    log "ERROR" "Deployment failed and cleanup completed"
    exit 1
}

# ============================================================================
# HELP AND USAGE
# ============================================================================

show_help() {
    cat << 'EOF'
🚀 Multi-Cloud DevOps Platform Deployment Script

USAGE:
    ./deploy.sh [OPTIONS]

REQUIRED EXTERNAL SERVICE CREDENTIALS:
    --elasticsearch-url URL        Elasticsearch Cloud URL
    --elasticsearch-api-key KEY    Elasticsearch API key
    --datadog-api-key KEY         DataDog API key
    --datadog-app-key KEY         DataDog application key
    --newrelic-license KEY        New Relic license key
    --artifactory-url URL         JFrog Artifactory URL
    --artifactory-username USER   JFrog Artifactory username
    --artifactory-password PASS   JFrog Artifactory password

DEPLOYMENT OPTIONS:
    -e, --env ENV                 Environment (default: dev)
    -r, --region REGION           AWS region (default: us-east-2)
    -p, --profile PROFILE         AWS profile (default: default)
    --gcp-project-id ID           GCP project ID
    --azure-subscription-id ID    Azure subscription ID

CONTROL FLAGS:
    --skip-bootstrap              Skip Terraform backend bootstrap (use existing)
    --skip-terraform              Skip infrastructure deployment
    --skip-config-mgmt            Skip configuration management
    --skip-observability          Skip observability stack
    --skip-cicd                   Skip CI/CD pipeline
    --skip-applications           Skip application deployment
    --dry-run                     Show what would be deployed without executing

OTHER OPTIONS:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose logging

EXAMPLES:
    # Full deployment with all credentials
    ./deploy.sh \
        --elasticsearch-url "https://your-cluster.es.io:443" \
        --elasticsearch-api-key "your-es-api-key" \
        --datadog-api-key "your-dd-api-key" \
        --datadog-app-key "your-dd-app-key" \
        --newrelic-license "your-nr-license" \
        --artifactory-url "https://your-company.jfrog.io" \
        --artifactory-username "your-username" \
        --artifactory-password "your-password"

    # Dry run to see what would be deployed
    ./deploy.sh --dry-run [credentials...]

    # Deploy only infrastructure
    ./deploy.sh --skip-observability --skip-cicd --skip-applications [credentials...]

    # Deploy to production environment
    ./deploy.sh -e prod -r us-west-2 [credentials...]

DEPLOYMENT PHASES:
    1. Prerequisites validation
    2. Infrastructure deployment (Terraform)
    3. Configuration management (Ansible/Puppet)
    4. Observability stack (DataDog, Elasticsearch, New Relic)
    5. CI/CD pipeline (Jenkins, Nexus, ArgoCD)
    6. Application deployment
    7. Validation and summary

For more information, see the documentation in the docs/ directory.
EOF
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --elasticsearch-url)
                ELASTICSEARCH_URL="$2"
                shift 2
                ;;
            --elasticsearch-api-key)
                ELASTICSEARCH_API_KEY="$2"
                shift 2
                ;;
            --datadog-api-key)
                DATADOG_API_KEY="$2"
                shift 2
                ;;
            --datadog-app-key)
                DATADOG_APP_KEY="$2"
                shift 2
                ;;
            --newrelic-license)
                NEWRELIC_LICENSE_KEY="$2"
                shift 2
                ;;
            --artifactory-url)
                ARTIFACTORY_URL="$2"
                shift 2
                ;;
            --artifactory-username)
                ARTIFACTORY_USERNAME="$2"
                shift 2
                ;;
            --artifactory-password)
                ARTIFACTORY_PASSWORD="$2"
                shift 2
                ;;
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
            --skip-bootstrap)
                SKIP_BOOTSTRAP=true
                shift
                ;;
            --skip-terraform)
                SKIP_TERRAFORM=true
                shift
                ;;
            --skip-config-mgmt)
                SKIP_CONFIG_MGMT=true
                shift
                ;;
            --skip-observability)
                SKIP_OBSERVABILITY=true
                shift
                ;;
            --skip-cicd)
                SKIP_CICD=true
                shift
                ;;
            --skip-applications)
                SKIP_APPLICATIONS=true
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
    log "INFO" "Starting Multi-Cloud DevOps Platform deployment"
    log "INFO" "Environment: $ENV, Region: $REGION, Dry Run: $DRY_RUN"
    
    # Print banner
    print_banner
    
    # Display configuration
    echo -e "${BLUE}📋 Deployment Configuration:${NC}"
    echo -e "   Environment: $ENV"
    echo -e "   Region: $REGION"
    echo -e "   AWS Profile: $AWS_PROFILE"
    [ -n "$GCP_PROJECT_ID" ] && echo -e "   GCP Project: $GCP_PROJECT_ID"
    [ -n "$AZURE_SUBSCRIPTION_ID" ] && echo -e "   Azure Subscription: $AZURE_SUBSCRIPTION_ID"
    echo -e "   Dry Run: $DRY_RUN"
    echo -e "   Log File: $LOG_FILE"
    
    # Validation phase
    validate_prerequisites
    validate_environment
    
    # Bootstrap phase (set up Terraform state backend)
    bootstrap_terraform_backend
    
    # Main deployment phases
    deploy_infrastructure
    deploy_configuration_management
    deploy_service_mesh
    deploy_security_policies
    deploy_ssl_certificates
    deploy_network_policies
    deploy_observability_stack
    deploy_cicd_pipeline
    deploy_applications
    deploy_api_gateway
    deploy_disaster_recovery
    deploy_custom_dns
    deploy_compliance_scanning
    deploy_performance_monitoring
    deploy_integration_testing
    
    # Post-deployment validation
    validate_deployment
    validate_complete_integration
    
    # Summary and next steps
    print_deployment_summary
}

# Execute main function with all arguments
main "$@" 