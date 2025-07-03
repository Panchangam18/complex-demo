#!/bin/bash

# New Relic Lightweight Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from .env file
if [ -f "../../../../.env" ]; then
    echo "Loading environment variables from project .env"
    set -a  # automatically export all variables
    source "../../../../.env"
    set +a  # stop automatically exporting
elif [ -f "../../../.env" ]; then
    echo "Loading environment variables from .env"
    set -a
    source "../../../.env" 
    set +a
else
    echo -e "${RED}❌ No .env file found. Please run scripts/extract-credentials-to-env.sh first${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 Deploying New Relic Lightweight Monitoring${NC}"
echo -e "${BLUE}=============================================${NC}"

# Validate required environment variables
if [ -z "$NEWRELIC_LICENSE_KEY" ]; then
    echo -e "${RED}❌ NEWRELIC_LICENSE_KEY not found in .env file${NC}"
    echo -e "${YELLOW}Please add NEWRELIC_LICENSE_KEY to your .env file${NC}"
    exit 1
fi

echo -e "Environment: ${ENVIRONMENT:-dev}"
echo -e "Region: ${AWS_REGION:-us-east-2}"
echo -e "License Key: ${NEWRELIC_LICENSE_KEY:0:10}... (truncated)"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ kubectl not configured or cluster not accessible${NC}"
    echo -e "${YELLOW}💡 Run this command to connect to your EKS cluster:${NC}"
    echo -e "   aws eks update-kubeconfig --region ${AWS_REGION:-us-east-2} --name ${ENVIRONMENT:-dev}-eks-${AWS_REGION:-us-east-2}"
    exit 1
fi

echo -e "\n${YELLOW}🔧 Applying New Relic configuration...${NC}"

# Use envsubst to substitute environment variables and apply to cluster
envsubst < newrelic-lightweight.yaml | kubectl apply -f -

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ New Relic deployed successfully${NC}"
    
    echo -e "\n${BLUE}📋 Deployment Summary:${NC}"
    echo -e "  • Namespace: newrelic"
    echo -e "  • DaemonSet: newrelic-infrastructure (runs on all nodes)"
    echo -e "  • Deployment: newrelic-k8s-events (1 replica)"
    echo -e "  • Secret: newrelic-license-key (from .env)"
    
    echo -e "\n${YELLOW}🔍 Check deployment status:${NC}"
    echo -e "  kubectl get pods -n newrelic"
    echo -e "  kubectl logs -f daemonset/newrelic-infrastructure -n newrelic"
    
    echo -e "\n${YELLOW}📊 Monitor in New Relic:${NC}"
    echo -e "  https://one.newrelic.com/launcher/k8s-cluster-explorer"
    
else
    echo -e "${RED}❌ Failed to deploy New Relic${NC}"
    exit 1
fi 