#!/bin/bash

# Jenkins-Nexus Integration Demo Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from .env file
if [ -f "../.env" ]; then
    echo "Loading environment variables from ci-cd/.env"
    set -a  # automatically export all variables
    source "../.env"
    set +a  # stop automatically exporting
elif [ -f "../../.env" ]; then
    echo "Loading environment variables from project .env"
    set -a
    source "../../.env"
    set +a
else
    echo -e "${RED}❌ No .env file found. Please run scripts/extract-credentials-to-env.sh first${NC}"
    exit 1
fi

# Validate required environment variables
if [ -z "$NEXUS_URL" ] || [ -z "$NEXUS_ADMIN_PASSWORD" ] || [ -z "$JENKINS_URL" ] || [ -z "$JENKINS_SECRET_ARN" ]; then
    echo -e "${RED}❌ Missing required environment variables${NC}"
    echo -e "${YELLOW}Required variables: NEXUS_URL, NEXUS_ADMIN_PASSWORD, JENKINS_URL, JENKINS_SECRET_ARN${NC}"
    echo -e "${YELLOW}Please run: scripts/extract-credentials-to-env.sh${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 Jenkins-Nexus Integration Demo${NC}"
echo -e "${BLUE}=================================${NC}"
echo -e "Jenkins URL: ${JENKINS_URL}"
echo -e "Nexus URL: ${NEXUS_URL}"
echo -e "Environment: ${ENVIRONMENT:-dev}"
echo -e "Region: ${AWS_REGION:-us-east-2}"

# Test Nexus connectivity
echo -e "\n${YELLOW}🔧 Testing Nexus connectivity...${NC}"
if curl -s -u "admin:${NEXUS_ADMIN_PASSWORD}" \
     "${NEXUS_URL}/service/rest/v1/status" > /dev/null; then
    echo -e "${GREEN}✅ Nexus is accessible${NC}"
else
    echo -e "${RED}❌ Cannot connect to Nexus${NC}"
    exit 1
fi

# Test Jenkins connectivity  
echo -e "\n${YELLOW}🔧 Testing Jenkins connectivity...${NC}"
if curl -s -f "${JENKINS_URL}/login" > /dev/null; then
    echo -e "${GREEN}✅ Jenkins is accessible${NC}"
else
    echo -e "${RED}❌ Cannot connect to Jenkins${NC}"
    exit 1
fi

echo -e "\n${GREEN}🎉 Jenkins-Nexus integration demo completed successfully!${NC}"
echo -e "${YELLOW}💡 Use jenkins-nexus-integration-complete.sh for full setup${NC}" 