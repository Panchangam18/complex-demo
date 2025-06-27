#!/bin/bash

# Update Kubernetes Images Script for JFrog Artifactory
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

# Set defaults
ENVIRONMENT=${ENVIRONMENT:-dev}
IMAGE_TAG=${IMAGE_TAG:-latest}
FRONTEND_IMAGE_NAME=${FRONTEND_IMAGE_NAME:-dev-frontend}
BACKEND_IMAGE_NAME=${BACKEND_IMAGE_NAME:-dev-backend}

# Construct new image URLs (remove https:// for Docker tags)
ARTIFACTORY_REGISTRY=$(echo "${ARTIFACTORY_URL}" | sed 's|https://||')
FRONTEND_IMAGE_URL="${ARTIFACTORY_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/${FRONTEND_IMAGE_NAME}:${IMAGE_TAG}"
BACKEND_IMAGE_URL="${ARTIFACTORY_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/${BACKEND_IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${YELLOW}🔄 Updating Kubernetes deployments to use JFrog Artifactory...${NC}"
echo -e "${YELLOW}📋 Configuration:${NC}"
echo -e "  Frontend Image: ${FRONTEND_IMAGE_URL}"
echo -e "  Backend Image:  ${BACKEND_IMAGE_URL}"

# Update frontend deployment
echo -e "\n${YELLOW}🔧 Updating frontend deployment...${NC}"
FRONTEND_DEPLOYMENT="k8s/envs/dev/frontend/deployment.yaml"
if [ -f "$FRONTEND_DEPLOYMENT" ]; then
    sed -i.bak "s|image:.*|image: ${FRONTEND_IMAGE_URL}|g" "$FRONTEND_DEPLOYMENT"
    echo -e "${GREEN}✅ Updated: ${FRONTEND_DEPLOYMENT}${NC}"
else
    echo -e "${RED}❌ Frontend deployment file not found: ${FRONTEND_DEPLOYMENT}${NC}"
fi

# Update backend deployment
echo -e "\n${YELLOW}🔧 Updating backend deployment...${NC}"
BACKEND_DEPLOYMENT="k8s/envs/dev/backend/deployment.yaml"
if [ -f "$BACKEND_DEPLOYMENT" ]; then
    sed -i.bak "s|image:.*|image: ${BACKEND_IMAGE_URL}|g" "$BACKEND_DEPLOYMENT"
    echo -e "${GREEN}✅ Updated: ${BACKEND_DEPLOYMENT}${NC}"
else
    echo -e "${RED}❌ Backend deployment file not found: ${BACKEND_DEPLOYMENT}${NC}"
fi

# Clean up backup files
rm -f k8s/envs/dev/*/deployment.yaml.bak

echo -e "\n${GREEN}🎉 Kubernetes deployments updated successfully!${NC}"
echo -e "\n${YELLOW}📝 Next steps:${NC}"
echo -e "  1. Create image pull secret in Kubernetes clusters"
echo -e "  2. Commit and push the updated deployment files"
echo -e "  3. ArgoCD will automatically sync the changes" 