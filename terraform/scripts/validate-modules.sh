#!/bin/bash
# Script to validate all Terraform modules

set -e

echo "🔍 Validating Terraform Modules"
echo "==============================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to validate a module
validate_module() {
    local module_path=$1
    local module_name=$(basename $module_path)
    
    echo -n "Validating $module_name... "
    
    cd "$module_path"
    
    # Initialize without backend
    if terraform init -backend=false > /dev/null 2>&1; then
        if terraform validate > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Valid${NC}"
            return 0
        else
            echo -e "${RED}✗ Invalid${NC}"
            terraform validate
            return 1
        fi
    else
        echo -e "${RED}✗ Init failed${NC}"
        return 1
    fi
}

# Find all module directories
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MODULES_DIR="$SCRIPT_DIR/../modules"

# Validate each module
FAILED=0
for provider in aws gcp azure; do
    echo ""
    echo "Provider: $provider"
    echo "-------------------"
    
    if [ -d "$MODULES_DIR/$provider" ]; then
        for module in "$MODULES_DIR/$provider"/*; do
            if [ -d "$module" ]; then
                validate_module "$module" || FAILED=$((FAILED + 1))
            fi
        done
    fi
done

echo ""
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All modules are valid!${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED module(s) failed validation${NC}"
    exit 1
fi