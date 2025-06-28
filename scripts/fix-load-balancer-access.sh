#!/bin/bash

# Fix Load Balancer Access Script
# This script fixes security group rules to allow AWS Load Balancers to reach EKS worker nodes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔧 Fixing Load Balancer Access to EKS Worker Nodes...${NC}"

# Get EKS cluster name and region
CLUSTER_NAME="dev-eks-us-east-2"
REGION="us-east-2"

echo -e "${YELLOW}📋 Configuration:${NC}"
echo -e "  Cluster: ${CLUSTER_NAME}"
echo -e "  Region: ${REGION}"

# Get worker node security group
echo -e "\n${YELLOW}🔍 Finding worker node security group...${NC}"

# Try multiple methods to find the security group
WORKER_SG=$(aws ec2 describe-instances \
  --region ${REGION} \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
  --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' \
  --output text 2>/dev/null | tr '\t' '\n' | grep -E '^sg-' | head -1)

if [ -z "$WORKER_SG" ]; then
    # Try finding by EKS node group name
    WORKER_SG=$(aws ec2 describe-instances \
      --region ${REGION} \
      --filters "Name=tag:Name,Values=*eks*" \
      --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' \
      --output text 2>/dev/null | tr '\t' '\n' | grep -E '^sg-' | head -1)
fi

if [ -z "$WORKER_SG" ]; then
    # Get instance IDs from kubectl and find their security groups
    INSTANCE_IDS=$(kubectl get nodes -o jsonpath='{.items[*].spec.providerID}' | sed 's|.*\/||g')
    if [ ! -z "$INSTANCE_IDS" ]; then
        WORKER_SG=$(aws ec2 describe-instances \
          --region ${REGION} \
          --instance-ids $INSTANCE_IDS \
          --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' \
          --output text 2>/dev/null | tr '\t' '\n' | grep -E '^sg-' | head -1)
    fi
fi

if [ -z "$WORKER_SG" ]; then
    echo -e "${RED}❌ Could not find worker node security group${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found worker security group: ${WORKER_SG}${NC}"

# Add rules to allow load balancer traffic
echo -e "\n${YELLOW}🛡️  Adding security group rules...${NC}"

# Allow NodePort range (30000-32767) from anywhere (load balancers)
echo -e "Adding NodePort range access (30000-32767)..."
aws ec2 authorize-security-group-ingress \
  --region ${REGION} \
  --group-id ${WORKER_SG} \
  --protocol tcp \
  --port 30000-32767 \
  --cidr 0.0.0.0/0 \
  --output text 2>/dev/null || echo "Rule may already exist"

# Allow HTTP (80) from anywhere
echo -e "Adding HTTP access (port 80)..."
aws ec2 authorize-security-group-ingress \
  --region ${REGION} \
  --group-id ${WORKER_SG} \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --output text 2>/dev/null || echo "Rule may already exist"

# Allow HTTPS (443) from anywhere  
echo -e "Adding HTTPS access (port 443)..."
aws ec2 authorize-security-group-ingress \
  --region ${REGION} \
  --group-id ${WORKER_SG} \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --output text 2>/dev/null || echo "Rule may already exist"

# Allow port 8080 (ArgoCD, Prometheus)
echo -e "Adding port 8080 access..."
aws ec2 authorize-security-group-ingress \
  --region ${REGION} \
  --group-id ${WORKER_SG} \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0 \
  --output text 2>/dev/null || echo "Rule may already exist"

echo -e "\n${GREEN}✅ Security group rules updated!${NC}"

# Restart load balancer services to pick up changes
echo -e "\n${YELLOW}🔄 Restarting load balancer services...${NC}"

# Change ArgoCD back to LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"LoadBalancer"}}' || echo "ArgoCD service update failed"

# Wait a moment for changes to propagate
echo -e "\n${YELLOW}⏳ Waiting for changes to propagate (30 seconds)...${NC}"
sleep 30

# Test connectivity
echo -e "\n${YELLOW}🧪 Testing connectivity...${NC}"

# Test ArgoCD
echo -e "Testing ArgoCD..."
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ ! -z "$ARGOCD_URL" ]; then
    curl -I --connect-timeout 10 http://$ARGOCD_URL 2>/dev/null && echo -e "${GREEN}✅ ArgoCD accessible${NC}" || echo -e "${RED}❌ ArgoCD still not accessible${NC}"
else
    echo -e "${YELLOW}⏳ ArgoCD load balancer not ready yet${NC}"
fi

# Test Grafana
echo -e "Testing Grafana..."
GRAFANA_URL=$(kubectl get svc prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ ! -z "$GRAFANA_URL" ]; then
    curl -I --connect-timeout 10 http://$GRAFANA_URL 2>/dev/null && echo -e "${GREEN}✅ Grafana accessible${NC}" || echo -e "${RED}❌ Grafana still not accessible${NC}"
else
    echo -e "${YELLOW}⏳ Grafana load balancer not ready yet${NC}"
fi

# Test our applications
echo -e "Testing Frontend..."
FRONTEND_URL=$(kubectl get svc frontend-service -n frontend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ ! -z "$FRONTEND_URL" ]; then
    curl -I --connect-timeout 10 http://$FRONTEND_URL 2>/dev/null && echo -e "${GREEN}✅ Frontend accessible${NC}" || echo -e "${RED}❌ Frontend still not accessible${NC}"
else
    echo -e "${YELLOW}⏳ Frontend load balancer not ready yet${NC}"
fi

echo -e "\n${GREEN}🎉 Load balancer access fix completed!${NC}"
echo -e "${YELLOW}📝 Note: It may take a few more minutes for all load balancers to become fully operational.${NC}"
echo -e "${YELLOW}💡 If issues persist, try running this script again in 5 minutes.${NC}" 