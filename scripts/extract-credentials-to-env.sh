#!/bin/bash

# Extract Deployment Credentials to .env
# This script runs after terraform deployment to extract credentials and URLs
# from the deployed infrastructure and save them to .env files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-dev}
REGION=${REGION:-us-east-2}
TERRAFORM_DIR="${TERRAFORM_DIR:-terraform/envs/${ENVIRONMENT}/${REGION}}"
ENV_FILE="${ENV_FILE:-.env}"

echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    🔐 EXTRACTING DEPLOYMENT CREDENTIALS                      ║"
echo "║                                                                              ║"
echo "║  Extracting credentials from deployed infrastructure to .env file            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}📋 Configuration:${NC}"
echo -e "  Environment: ${ENVIRONMENT}"
echo -e "  Region: ${REGION}"
echo -e "  Terraform Dir: ${TERRAFORM_DIR}"
echo -e "  Output File: ${ENV_FILE}"

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo -e "${RED}❌ Terraform directory not found: $TERRAFORM_DIR${NC}"
    exit 1
fi

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ kubectl not configured or cluster not accessible${NC}"
    echo -e "${YELLOW}💡 Run this command to connect to your EKS cluster:${NC}"
    echo -e "   aws eks update-kubeconfig --region ${REGION} --name ${ENVIRONMENT}-eks-${REGION}"
    exit 1
fi

cd "$TERRAFORM_DIR"

print_section() {
    echo -e "\n${BLUE}=================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=================================${NC}"
}

print_section "📦 EXTRACTING NEXUS CREDENTIALS"

echo -e "${YELLOW}🔍 Getting Nexus URL from Terraform outputs...${NC}"
NEXUS_URL_COMMAND=$(terragrunt output -raw nexus_external_url_command 2>/dev/null || echo "")
if [ -n "$NEXUS_URL_COMMAND" ]; then
    NEXUS_URL=$(eval "$NEXUS_URL_COMMAND" 2>/dev/null || echo "")
    if [ -z "$NEXUS_URL" ]; then
        # Fallback to direct service lookup
        NEXUS_NAMESPACE=$(terragrunt output -raw nexus_namespace 2>/dev/null || echo "nexus-${ENVIRONMENT}")
        NEXUS_LB_HOST=$(kubectl get svc -n "$NEXUS_NAMESPACE" -l app=nexus -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -n "$NEXUS_LB_HOST" ]; then
            NEXUS_URL="http://${NEXUS_LB_HOST}:8081"
        fi
    fi
fi

if [ -z "$NEXUS_URL" ]; then
    echo -e "${RED}❌ Could not determine Nexus URL${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Nexus URL: ${NEXUS_URL}${NC}"

echo -e "${YELLOW}🔑 Retrieving Nexus admin password...${NC}"
NEXUS_PASSWORD_COMMAND=$(terragrunt output -raw nexus_admin_password_command 2>/dev/null || echo "")
if [ -n "$NEXUS_PASSWORD_COMMAND" ]; then
    NEXUS_ADMIN_PASSWORD=$(eval "$NEXUS_PASSWORD_COMMAND" 2>/dev/null | tr -d '\r\n' || echo "")
else
    # Fallback to direct kubectl command
    NEXUS_NAMESPACE=$(terragrunt output -raw nexus_namespace 2>/dev/null || echo "nexus-${ENVIRONMENT}")
    NEXUS_POD=$(kubectl get pods -n "$NEXUS_NAMESPACE" -l app=nexus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$NEXUS_POD" ]; then
        NEXUS_ADMIN_PASSWORD=$(kubectl exec -n "$NEXUS_NAMESPACE" "$NEXUS_POD" -- cat /nexus-data/admin.password 2>/dev/null | tr -d '\r\n' || echo "")
    fi
fi

if [ -z "$NEXUS_ADMIN_PASSWORD" ]; then
    echo -e "${RED}❌ Could not retrieve Nexus admin password${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Nexus admin password retrieved${NC}"

print_section "🚀 EXTRACTING JENKINS CREDENTIALS"

echo -e "${YELLOW}🔍 Getting Jenkins URL from Terraform outputs...${NC}"
JENKINS_URL=$(terragrunt output -raw jenkins_url 2>/dev/null || echo "")
if [ -z "$JENKINS_URL" ]; then
    echo -e "${RED}❌ Could not determine Jenkins URL${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Jenkins URL: ${JENKINS_URL}${NC}"

echo -e "${YELLOW}🔑 Getting Jenkins admin password secret ARN...${NC}"
JENKINS_SECRET_ARN=$(terragrunt output -raw jenkins_admin_password_secret_arn 2>/dev/null || echo "")
if [ -z "$JENKINS_SECRET_ARN" ]; then
    echo -e "${RED}❌ Could not determine Jenkins secret ARN${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Jenkins secret ARN: ${JENKINS_SECRET_ARN}${NC}"

print_section "📝 CREATING .ENV FILE"

# Create .env file with extracted credentials
cat > "../../../${ENV_FILE}" << EOF
# DevOps Infrastructure Credentials
# Generated on: $(date)
# Environment: ${ENVIRONMENT}
# Region: ${REGION}

# Nexus Repository Manager
NEXUS_URL=${NEXUS_URL}
NEXUS_ADMIN_USERNAME=admin
NEXUS_ADMIN_PASSWORD=${NEXUS_ADMIN_PASSWORD}

# Jenkins CI/CD Server  
JENKINS_URL=${JENKINS_URL}
JENKINS_ADMIN_USERNAME=admin
JENKINS_SECRET_ARN=${JENKINS_SECRET_ARN}

# Repository URLs
NEXUS_NPM_REGISTRY=${NEXUS_URL}/repository/npm-public/
NEXUS_DOCKER_REGISTRY=${NEXUS_URL%:*}:8086
NEXUS_PYPI_INDEX=${NEXUS_URL}/repository/pypi-public/simple/

# Monitoring & Observability
# TODO: Replace with your actual New Relic license key
NEWRELIC_LICENSE_KEY=YOUR_NEWRELIC_LICENSE_KEY_HERE

# Environment Configuration
ENVIRONMENT=${ENVIRONMENT}
AWS_REGION=${REGION}
EOF

echo -e "${GREEN}✅ .env file created: $(pwd)/../../../${ENV_FILE}${NC}"

print_section "🔧 ADDITIONAL CONFIGURATION"

# Also create a CI/CD specific env file for integration scripts
cat > "../../../ci-cd/.env" << EOF
# CI/CD Integration Environment Variables
# Generated on: $(date)

# Nexus Configuration
NEXUS_URL=${NEXUS_URL}
NEXUS_ADMIN_USERNAME=admin
NEXUS_ADMIN_PASSWORD=${NEXUS_ADMIN_PASSWORD}

# Jenkins Configuration  
JENKINS_URL=${JENKINS_URL}
JENKINS_ADMIN_USERNAME=admin
JENKINS_SECRET_ARN=${JENKINS_SECRET_ARN}

# Environment
ENVIRONMENT=${ENVIRONMENT}
AWS_REGION=${REGION}
EOF

echo -e "${GREEN}✅ CI/CD .env file created: $(pwd)/../../../ci-cd/.env${NC}"

print_section "📋 CREDENTIAL SUMMARY"

echo -e "${GREEN}🎉 Credentials extracted successfully!${NC}"
echo -e "${GREEN}======================================${NC}"

echo -e "\n${BLUE}📦 Nexus Repository Manager:${NC}"
echo -e "  🌐 URL: ${NEXUS_URL}"
echo -e "  👤 Username: admin"
echo -e "  🔑 Password: [EXTRACTED FROM DEPLOYMENT]"

echo -e "\n${BLUE}🚀 Jenkins CI/CD Server:${NC}"  
echo -e "  🌐 URL: ${JENKINS_URL}"
echo -e "  👤 Username: admin"
echo -e "  🔗 Secret ARN: ${JENKINS_SECRET_ARN}"

echo -e "\n${YELLOW}📁 Files Created:${NC}"
echo -e "  • $(pwd)/../../../${ENV_FILE}"
echo -e "  • $(pwd)/../../../ci-cd/.env"

echo -e "\n${YELLOW}🔧 Next Steps:${NC}"
echo -e "  1. Update NEWRELIC_LICENSE_KEY in ${ENV_FILE} with your actual license key"
echo -e "  2. Source the .env file: source ${ENV_FILE}"
echo -e "  3. Run integration scripts: ./ci-cd/jenkins/scripts/jenkins-nexus-integration-complete.sh"
echo -e "  4. Deploy New Relic monitoring: ./k8s/envs/dev/monitoring/deploy-newrelic.sh"
echo -e "  5. Scripts will now use extracted credentials instead of hardcoded values"

echo -e "\n${GREEN}✅ Your credentials are now properly managed!${NC}" 