#!/bin/bash

# Deploy Datadog Integration Script
# Uses environment variables from .env file for secure credential management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from .env file
if [ -f ".env" ]; then
    echo "Loading environment variables from .env"
    set -a  # automatically export all variables
    source .env
    set +a  # stop automatically exporting
else
    echo -e "${RED}❌ No .env file found. Please create it with DATADOG_API_KEY and DATADOG_APP_KEY${NC}"
    exit 1
fi

# Validate required environment variables
if [ -z "${DATADOG_API_KEY:-}" ] || [ -z "${DATADOG_APP_KEY:-}" ]; then
    echo -e "${RED}❌ Missing required environment variables${NC}"
    echo -e "${YELLOW}Required variables: DATADOG_API_KEY, DATADOG_APP_KEY${NC}"
    echo -e "${YELLOW}Please add them to your .env file${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Deploying Datadog Multi-Cloud Integration${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "API Key: ${DATADOG_API_KEY:0:10}... (truncated)"
echo -e "App Key: ${DATADOG_APP_KEY:0:10}... (truncated)"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ kubectl not configured or cluster not accessible${NC}"
    echo -e "${YELLOW}💡 Run this command to connect to your EKS cluster:${NC}"
    echo -e "   aws eks update-kubeconfig --region us-east-2 --name dev-eks-us-east-2"
    exit 1
fi

echo -e "\n${YELLOW}🔧 Applying Datadog secrets...${NC}"

# Use envsubst to substitute environment variables and apply to cluster
envsubst < k8s/envs/dev/monitoring/datadog-secrets.yaml | kubectl apply -f -

echo -e "\n${YELLOW}🚀 Deploying Datadog agents to all clusters...${NC}"

# Apply Datadog configurations for each cloud provider
for config in k8s/envs/dev/monitoring/datadog-*.yaml; do
    if [[ "$config" != *"secrets"* ]]; then
        echo -e "${BLUE}📦 Applying $(basename "$config")...${NC}"
        envsubst < "$config" | kubectl apply -f -
    fi
done

echo -e "\n${YELLOW}⏳ Waiting for Datadog agents to be ready...${NC}"

# Wait for deployments to be ready
kubectl wait --namespace=datadog \
    --for=condition=available deployment \
    --all \
    --timeout=300s

echo -e "\n${GREEN}✅ Datadog integration deployed successfully!${NC}"

echo -e "\n${BLUE}📋 Deployment Summary:${NC}"
echo -e "   • Namespace: datadog"
echo -e "   • API Key: ${DATADOG_API_KEY:0:10}... (from .env)"
echo -e "   • App Key: ${DATADOG_APP_KEY:0:10}... (from .env)"
echo -e "   • Dashboard: https://app.datadoghq.com/"

echo -e "\n${BLUE}🔧 Useful Commands:${NC}"
echo -e "   # Check agent status:"
echo -e "   kubectl get pods -n datadog"
echo -e ""
echo -e "   # View agent logs:"
echo -e "   kubectl logs -n datadog -l app=datadog-agent -c agent -f"
echo -e ""
echo -e "   # Check cluster agent status:"
echo -e "   kubectl get deployment -n datadog" 