#!/bin/bash

# Update Load Test URLs Script
# =============================
# This script dynamically retrieves load balancer URLs from the current
# Kubernetes deployment and updates Artillery load test configuration files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
ENV=${ENV:-dev}
REGION=${REGION:-us-east-2}
TIMEOUT=${TIMEOUT:-300}

echo -e "${BLUE}🎯 Updating Load Test URLs for Environment: $ENV${NC}"
echo "=============================================="

# Function to get load balancer URL with retry logic
get_loadbalancer_url() {
    local service_name=$1
    local namespace=$2
    local max_attempts=10
    local attempt=1
    
    echo -e "${YELLOW}⏳ Getting load balancer URL for $service_name in $namespace...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        # Get the load balancer hostname/IP
        local lb_hostname=$(kubectl get svc "$service_name" -n "$namespace" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        local lb_ip=$(kubectl get svc "$service_name" -n "$namespace" \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$lb_hostname" ]; then
            echo "http://$lb_hostname"
            return 0
        elif [ -n "$lb_ip" ]; then
            echo "http://$lb_ip"
            return 0
        fi
        
        echo -e "${YELLOW}   Attempt $attempt/$max_attempts: Load balancer not ready yet...${NC}"
        sleep 30
        ((attempt++))
    done
    
    echo -e "${RED}❌ Failed to get load balancer URL for $service_name after $max_attempts attempts${NC}"
    return 1
}

# Function to check if service exists
check_service_exists() {
    local service_name=$1
    local namespace=$2
    
    if kubectl get svc "$service_name" -n "$namespace" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to update Artillery configuration file
update_artillery_config() {
    local config_file=$1
    local new_target_url=$2
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Artillery config file not found: $config_file${NC}"
        return 1
    fi
    
    echo -e "${BLUE}📝 Updating $config_file with URL: $new_target_url${NC}"
    
    # Create backup
    cp "$config_file" "$config_file.backup"
    
    # Update the target URL using sed
    sed -i.tmp "s|target: \"http://[^\"]*\"|target: \"$new_target_url\"|g" "$config_file"
    rm -f "$config_file.tmp"
    
    # Verify the update
    if grep -q "$new_target_url" "$config_file"; then
        echo -e "${GREEN}✅ Successfully updated $config_file${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to update $config_file${NC}"
        # Restore backup
        cp "$config_file.backup" "$config_file"
        return 1
    fi
}

# Function to get URLs from Terraform outputs (alternative method)
get_terraform_urls() {
    echo -e "${BLUE}🏗️ Attempting to get URLs from Terraform outputs...${NC}"
    
    local terraform_dir="terraform/envs/$ENV/$REGION"
    if [ -d "$terraform_dir" ]; then
        cd "$terraform_dir"
        
        # Try to get Jenkins URL (as example of external service)
        local jenkins_url=$(terragrunt output -raw jenkins_url 2>/dev/null || echo "")
        if [ -n "$jenkins_url" ]; then
            echo -e "${GREEN}✅ Jenkins URL from Terraform: $jenkins_url${NC}"
        fi
        
        # Try to get Nexus URL
        local nexus_url=$(terragrunt output -raw nexus_url 2>/dev/null || echo "")
        if [ -n "$nexus_url" ]; then
            echo -e "${GREEN}✅ Nexus URL from Terraform: $nexus_url${NC}"
        fi
        
        cd - > /dev/null
    else
        echo -e "${YELLOW}⚠️  Terraform directory not found: $terraform_dir${NC}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Checking Kubernetes connectivity...${NC}"
    
    # Check if kubectl is configured
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}❌ kubectl is not configured or cluster is not accessible${NC}"
        echo -e "${YELLOW}💡 Run: aws eks update-kubeconfig --region $REGION --name $ENV-eks-$REGION${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Kubernetes cluster accessible${NC}"
    echo ""
    
    # Check if namespaces exist
    echo -e "${BLUE}🔍 Checking application namespaces...${NC}"
    
    local frontend_ns="frontend-$ENV"
    local backend_ns="backend-$ENV"
    
    if ! kubectl get namespace "$frontend_ns" &>/dev/null; then
        echo -e "${YELLOW}⚠️  Frontend namespace '$frontend_ns' not found${NC}"
        echo -e "${YELLOW}💡 Deploy applications first: make deploy-apps-only${NC}"
    fi
    
    if ! kubectl get namespace "$backend_ns" &>/dev/null; then
        echo -e "${YELLOW}⚠️  Backend namespace '$backend_ns' not found${NC}"
        echo -e "${YELLOW}💡 Deploy applications first: make deploy-apps-only${NC}"
    fi
    
    echo ""
    
    # Get backend service URL
    echo -e "${BLUE}🎯 Getting Backend Service URL...${NC}"
    if check_service_exists "backend-service" "$backend_ns"; then
        local backend_url=$(get_loadbalancer_url "backend-service" "$backend_ns")
        if [ -n "$backend_url" ]; then
            echo -e "${GREEN}✅ Backend URL: $backend_url${NC}"
            
            # Update backend load test configs
            local backend_configs=(
                "Code/server/src/tests/stresstests/stress_server.yml"
                "Code/server/src/tests/stresstests/stress_server_intensive.yml"
            )
            
            for config in "${backend_configs[@]}"; do
                if update_artillery_config "$config" "$backend_url"; then
                    echo -e "${GREEN}   ✅ Updated $config${NC}"
                else
                    echo -e "${RED}   ❌ Failed to update $config${NC}"
                fi
            done
        else
            echo -e "${RED}❌ Could not retrieve backend load balancer URL${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Backend service not found in namespace $backend_ns${NC}"
    fi
    
    echo ""
    
    # Get frontend service URL
    echo -e "${BLUE}🎯 Getting Frontend Service URL...${NC}"
    if check_service_exists "frontend-service" "$frontend_ns"; then
        local frontend_url=$(get_loadbalancer_url "frontend-service" "$frontend_ns")
        if [ -n "$frontend_url" ]; then
            echo -e "${GREEN}✅ Frontend URL: $frontend_url${NC}"
            
            # Update frontend load test configs
            local frontend_configs=(
                "Code/client/src/tests/stresstests/stress_client.yml"
                "Code/client/src/tests/stresstests/stress_client_realistic.yml"
            )
            
            for config in "${frontend_configs[@]}"; do
                if update_artillery_config "$config" "$frontend_url"; then
                    echo -e "${GREEN}   ✅ Updated $config${NC}"
                else
                    echo -e "${RED}   ❌ Failed to update $config${NC}"
                fi
            done
        else
            echo -e "${RED}❌ Could not retrieve frontend load balancer URL${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Frontend service not found in namespace $frontend_ns${NC}"
    fi
    
    echo ""
    
    # Show Terraform URLs for reference
    get_terraform_urls
    
    echo ""
    echo -e "${GREEN}🎉 Load test URL update completed!${NC}"
    echo ""
    echo -e "${BLUE}📋 Summary of Updated Files:${NC}"
    echo "  • Code/server/src/tests/stresstests/stress_server.yml"
    echo "  • Code/server/src/tests/stresstests/stress_server_intensive.yml"
    echo "  • Code/client/src/tests/stresstests/stress_client.yml"
    echo "  • Code/client/src/tests/stresstests/stress_client_realistic.yml"
    echo ""
    echo -e "${BLUE}🚀 How to run load tests:${NC}"
    echo "  # Install Artillery (if not already installed)"
    echo "  npm install -g artillery"
    echo ""
    echo "  # Run backend load tests"
    echo "  cd Code/server/src/tests/stresstests/"
    echo "  artillery run stress_server_intensive.yml"
    echo ""
    echo "  # Run frontend load tests"
    echo "  cd Code/client/src/tests/stresstests/"
    echo "  artillery run stress_client_realistic.yml"
    echo ""
    echo -e "${BLUE}🔧 Alternative: Use Makefile targets${NC}"
    echo "  make run-load-tests"
    echo ""
    echo -e "${YELLOW}💡 Backup files created with .backup extension${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  -e, --env ENV        Environment (default: dev)"
            echo "  -r, --region REGION  AWS region (default: us-east-2)"
            echo "  -t, --timeout SEC    Timeout in seconds (default: 300)"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0                   # Update URLs for dev environment"
            echo "  $0 -e prod -r us-west-2"
            echo "  $0 --env staging --region us-east-1"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main 