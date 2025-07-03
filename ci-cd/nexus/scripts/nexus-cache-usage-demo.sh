#!/bin/bash

# Nexus Cache Usage Demo Script
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
if [ -z "$NEXUS_URL" ] || [ -z "$NEXUS_ADMIN_PASSWORD" ]; then
    echo -e "${RED}❌ Missing required environment variables${NC}"
    echo -e "${YELLOW}Required variables: NEXUS_URL, NEXUS_ADMIN_PASSWORD${NC}"
    echo -e "${YELLOW}Please run: scripts/extract-credentials-to-env.sh${NC}"
    exit 1
fi

echo -e "${BLUE}📦 Nexus Cache Usage Demo${NC}"
echo -e "${BLUE}========================${NC}"
echo -e "Nexus URL: ${NEXUS_URL}"
echo -e "Environment: ${ENVIRONMENT:-dev}"
echo -e "Region: ${AWS_REGION:-us-east-2}"

# Test Nexus connectivity and show cache usage
echo -e "\n${YELLOW}🔧 Testing Nexus cache usage...${NC}"
if curl -s -u "admin:${NEXUS_ADMIN_PASSWORD}" \
     "${NEXUS_URL}/service/rest/v1/repositories" | jq -r '.[].name' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Nexus repositories accessible${NC}"
    
    echo -e "\n${BLUE}📋 Available repositories:${NC}"
    curl -s -u "admin:${NEXUS_ADMIN_PASSWORD}" \
         "${NEXUS_URL}/service/rest/v1/repositories" | jq -r '.[].name' | while read repo; do
        echo -e "  • $repo"
    done
else
    echo -e "${RED}❌ Cannot access Nexus repositories${NC}"
    exit 1
fi

echo -e "\n${YELLOW}📊 Cache Usage URLs:${NC}"
echo -e "  NPM Registry: ${NEXUS_URL}/repository/npm-public/"
echo -e "  Maven Repository: ${NEXUS_URL}/repository/maven-public/"
echo -e "  PyPI Index: ${NEXUS_URL}/repository/pypi-public/simple/"
echo -e "  Docker Registry: ${NEXUS_URL%:*}:8086"

echo -e "\n${GREEN}🎉 Nexus cache usage demo completed!${NC}" 