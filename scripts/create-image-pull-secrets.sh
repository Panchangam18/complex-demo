#!/bin/bash

# Create JFrog Image Pull Secrets Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}❌ .env file not found! Please create it with your JFrog credentials.${NC}"
    exit 1
fi

# Check required environment variables
required_vars=("ARTIFACTORY_URL" "ARTIFACTORY_USERNAME" "ARTIFACTORY_TOKEN")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}❌ Missing required environment variable: $var${NC}"
        exit 1
    fi
done

echo -e "${YELLOW}🔐 Creating JFrog image pull secrets for Kubernetes clusters...${NC}"

# Namespaces that need the pull secret
NAMESPACES=("frontend-dev" "backend-dev" "observability")

# Function to create secret in a namespace
create_secret_in_namespace() {
    local namespace=$1
    echo -e "\n${YELLOW}📦 Creating secret in namespace: ${namespace}${NC}"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Delete existing secret if it exists (to update it)
    kubectl delete secret jfrog-pull-secret -n "${namespace}" --ignore-not-found=true
    
    # Create the docker registry secret
    kubectl create secret docker-registry jfrog-pull-secret \
        --docker-server="${ARTIFACTORY_URL}" \
        --docker-username="${ARTIFACTORY_USERNAME}" \
        --docker-password="${ARTIFACTORY_TOKEN}" \
        --namespace="${namespace}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Secret created successfully in namespace: ${namespace}${NC}"
    else
        echo -e "${RED}❌ Failed to create secret in namespace: ${namespace}${NC}"
        return 1
    fi
}

# Function to patch default service account to use the pull secret
patch_service_account() {
    local namespace=$1
    echo -e "${YELLOW}🔧 Patching default service account in: ${namespace}${NC}"
    
    kubectl patch serviceaccount default -n "${namespace}" \
        -p '{"imagePullSecrets": [{"name": "jfrog-pull-secret"}]}'
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Service account patched in namespace: ${namespace}${NC}"
    else
        echo -e "${RED}❌ Failed to patch service account in namespace: ${namespace}${NC}"
        return 1
    fi
}

# Main execution
echo -e "\n${YELLOW}🎯 Target namespaces: ${NAMESPACES[*]}${NC}"

# Check if kubectl is available and configured
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    echo -e "${YELLOW}💡 Make sure you're connected to your EKS cluster:${NC}"
    echo -e "   aws eks update-kubeconfig --region us-east-2 --name dev-eks-us-east-2"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"

# Create secrets in all namespaces
for namespace in "${NAMESPACES[@]}"; do
    create_secret_in_namespace "${namespace}"
    patch_service_account "${namespace}"
done

echo -e "\n${GREEN}🎉 All image pull secrets created successfully!${NC}"
echo -e "\n${YELLOW}📝 Next steps:${NC}"
echo -e "  1. Update your deployment YAML files to reference the secret:"
echo -e "     spec:"
echo -e "       imagePullSecrets:"
echo -e "       - name: jfrog-pull-secret"
echo -e "  2. Or the default service account will automatically use it"
echo -e "  3. Deploy your applications with the new JFrog image URLs"

# Verify the secrets
echo -e "\n${YELLOW}🔍 Verifying created secrets:${NC}"
for namespace in "${NAMESPACES[@]}"; do
    echo -e "\n📋 Namespace: ${namespace}"
    kubectl get secrets jfrog-pull-secret -n "${namespace}" -o yaml | grep -A 1 "name: jfrog-pull-secret" || true
done 