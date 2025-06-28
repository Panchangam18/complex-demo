#!/bin/bash

# Build and Push Script for JFrog Artifactory
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
required_vars=("ARTIFACTORY_URL" "ARTIFACTORY_USERNAME" "ARTIFACTORY_TOKEN" "ARTIFACTORY_DOCKER_REPO")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}❌ Missing required environment variable: $var${NC}"
        exit 1
    fi
done

# Set defaults
ENVIRONMENT=${ENVIRONMENT:-dev}
IMAGE_TAG=${IMAGE_TAG:-latest}
FRONTEND_IMAGE_NAME=${FRONTEND_IMAGE_NAME:-dev-frontend}
BACKEND_IMAGE_NAME=${BACKEND_IMAGE_NAME:-dev-backend}

# Construct image URLs (remove https:// for Docker tags)
ARTIFACTORY_REGISTRY=$(echo "${ARTIFACTORY_URL}" | sed 's|https://||')
FRONTEND_IMAGE_URL="${ARTIFACTORY_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/${FRONTEND_IMAGE_NAME}:${IMAGE_TAG}"
BACKEND_IMAGE_URL="${ARTIFACTORY_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/${BACKEND_IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${YELLOW}🚀 Starting build and push process...${NC}"
echo -e "${YELLOW}📋 Configuration:${NC}"
echo -e "  Registry: ${ARTIFACTORY_URL}"
echo -e "  Repository: ${ARTIFACTORY_DOCKER_REPO}"
echo -e "  Environment: ${ENVIRONMENT}"
echo -e "  Tag: ${IMAGE_TAG}"

# Docker login to JFrog Artifactory
echo -e "\n${YELLOW}🔐 Logging into JFrog Artifactory...${NC}"
echo "${ARTIFACTORY_TOKEN}" | docker login "${ARTIFACTORY_URL}" --username "${ARTIFACTORY_USERNAME}" --password-stdin

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to login to JFrog Artifactory${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Successfully logged into JFrog Artifactory${NC}"

# Build Frontend
echo -e "\n${YELLOW}🏗️  Building Frontend (Vue.js)...${NC}"
cd Code/client
docker build --platform linux/amd64 --no-cache -t "${FRONTEND_IMAGE_URL}" .
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Frontend build failed${NC}"
    exit 1
fi

# Push Frontend
echo -e "\n${YELLOW}📤 Pushing Frontend to JFrog...${NC}"
docker push "${FRONTEND_IMAGE_URL}"
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Frontend push failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Frontend pushed successfully: ${FRONTEND_IMAGE_URL}${NC}"

# Build Backend
echo -e "\n${YELLOW}🏗️  Building Backend (Node.js)...${NC}"
cd ../server
docker build --platform linux/amd64 --no-cache -t "${BACKEND_IMAGE_URL}" .
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Backend build failed${NC}"
    exit 1
fi

# Push Backend
echo -e "\n${YELLOW}📤 Pushing Backend to JFrog...${NC}"
docker push "${BACKEND_IMAGE_URL}"
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Backend push failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Backend pushed successfully: ${BACKEND_IMAGE_URL}${NC}"

# Summary
echo -e "\n${GREEN}🎉 Build and push completed successfully!${NC}"
echo -e "${GREEN}📋 Images pushed:${NC}"
echo -e "  Frontend: ${FRONTEND_IMAGE_URL}"
echo -e "  Backend:  ${BACKEND_IMAGE_URL}"

# Return to root directory
cd ../../

echo -e "\n${YELLOW}📝 Next steps:${NC}"
echo -e "  1. Update Kubernetes deployments to use new image URLs"
echo -e "  2. Create image pull secrets in Kubernetes clusters"
echo -e "  3. Deploy via ArgoCD" 