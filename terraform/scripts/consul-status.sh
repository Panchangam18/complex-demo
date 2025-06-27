#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV=${1:-dev}
REGION=${2:-us-east-2}
AWS_PROFILE=${AWS_PROFILE:-default}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}    Consul Multi-Cloud Status Check        ${NC}"
echo -e "${BLUE}============================================${NC}"

# Navigate to the environment directory
cd "$(dirname "$0")/../envs/${ENV}/${REGION}"

echo -e "${YELLOW}Checking Terraform state...${NC}"
if ! terragrunt plan -detailed-exitcode > /dev/null 2>&1; then
    echo -e "${RED}❌ Terraform state is not clean. Run 'make apply' first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Getting infrastructure outputs...${NC}"

# Get Consul UI URL
CONSUL_UI_URL=$(terragrunt output -raw consul_ui_url 2>/dev/null || echo "Not available")

echo -e "\n${YELLOW}Consul UI:${NC} ${GREEN}${CONSUL_UI_URL}${NC}"
echo -e "${GREEN}Consul multi-cloud deployment check complete!${NC}" 