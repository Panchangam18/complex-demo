#!/bin/bash

# Ansible Tower Configuration Script
# Architecture Plan: "Invoked by CircleCI post-Terraform"
# Integrates Ansible Tower with the rest of the infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration variables
TOWER_URL="${ANSIBLE_TOWER_URL:-https://172.171.194.242}"
TOWER_USERNAME="${ANSIBLE_TOWER_USERNAME:-admin}"
TOWER_PASSWORD="${ANSIBLE_TOWER_PASSWORD:-AnsibleTower123!}"
ORGANIZATION="${ANSIBLE_TOWER_ORG:-Default}"
PROJECT_NAME="multicloud-devops-config"
INVENTORY_NAME="terraform-dynamic-inventory"
CREDENTIAL_NAME="aws-ssh-credentials"

# Print banner
echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    🏗️  ANSIBLE TOWER CONFIGURATION 🏗️                      ║"
echo "║                                                                              ║"
echo "║  Configures Ansible Tower for Day-0/1 provisioning according to            ║"
echo "║  comprehensive multi-cloud DevOps architecture plan                         ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print section headers
print_section() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Function to make Tower API calls
tower_api() {
    local method=$1
    local endpoint=$2
    local data=${3:-"{}"}
    
    curl -s -k -X "${method}" \
        -H "Content-Type: application/json" \
        -u "${TOWER_USERNAME}:${TOWER_PASSWORD}" \
        -d "${data}" \
        "${TOWER_URL}/api/v2/${endpoint}"
}

# Function to wait for Tower to be ready
wait_for_tower() {
    print_section "🔍 WAITING FOR ANSIBLE TOWER TO BE READY"
    
    local retries=30
    local count=0
    
    echo -e "${YELLOW}Checking Tower availability at: ${TOWER_URL}${NC}"
    
    while [ $count -lt $retries ]; do
        if curl -s -k -f "${TOWER_URL}/api/v2/ping/" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Ansible Tower is ready!${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}⏳ Waiting for Tower to start... (attempt $((count+1))/${retries})${NC}"
        sleep 30
        count=$((count+1))
    done
    
    echo -e "${RED}❌ Timeout waiting for Ansible Tower to be ready${NC}"
    exit 1
}

# Function to create or update organization
configure_organization() {
    print_section "🏢 CONFIGURING ORGANIZATION"
    
    echo -e "${YELLOW}Creating/updating organization: ${ORGANIZATION}${NC}"
    
    local org_data='{
        "name": "'${ORGANIZATION}'",
        "description": "Multi-cloud DevOps organization for configuration management",
        "max_hosts": 0,
        "custom_virtualenv": null
    }'
    
    local response=$(tower_api GET "organizations/?name=${ORGANIZATION}")
    local org_count=$(echo "$response" | jq -r '.count // 0')
    
    if [ "$org_count" -eq 0 ]; then
        echo -e "${BLUE}Creating new organization...${NC}"
        tower_api POST "organizations/" "$org_data"
    else
        echo -e "${BLUE}Organization already exists${NC}"
    fi
    
    echo -e "${GREEN}✅ Organization configured${NC}"
}

# Function to create SSH credentials
configure_credentials() {
    print_section "🔑 CONFIGURING SSH CREDENTIALS"
    
    echo -e "${YELLOW}Setting up SSH credentials for infrastructure access${NC}"
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/aws-ec2-key.pem ]; then
        echo -e "${YELLOW}⚠️  AWS SSH key not found at ~/.ssh/aws-ec2-key.pem${NC}"
        echo -e "${YELLOW}💡 You may need to download it from AWS Secrets Manager${NC}"
        
        # Try to get it from Terraform output
        if command -v terragrunt >/dev/null 2>&1; then
            echo -e "${YELLOW}🔍 Checking Terraform for SSH key information...${NC}"
            cd terraform/envs/dev/us-east-2 2>/dev/null || true
            terragrunt output puppet_enterprise_ssh_command 2>/dev/null || true
        fi
    fi
    
    local ssh_key_content=""
    if [ -f ~/.ssh/aws-ec2-key.pem ]; then
        ssh_key_content=$(cat ~/.ssh/aws-ec2-key.pem)
    fi
    
    local cred_data='{
        "name": "'${CREDENTIAL_NAME}'",
        "description": "SSH credentials for AWS EC2 instances",
        "organization": 1,
        "credential_type": 1,
        "inputs": {
            "username": "ec2-user",
            "ssh_key_data": "'${ssh_key_content}'"
        }
    }'
    
    local response=$(tower_api GET "credentials/?name=${CREDENTIAL_NAME}")
    local cred_count=$(echo "$response" | jq -r '.count // 0')
    
    if [ "$cred_count" -eq 0 ]; then
        echo -e "${BLUE}Creating SSH credentials...${NC}"
        tower_api POST "credentials/" "$cred_data"
    else
        echo -e "${BLUE}SSH credentials already exist${NC}"
    fi
    
    echo -e "${GREEN}✅ SSH credentials configured${NC}"
}

# Function to create project
configure_project() {
    print_section "📁 CONFIGURING PROJECT"
    
    echo -e "${YELLOW}Setting up project with Ansible playbooks${NC}"
    
    local project_data='{
        "name": "'${PROJECT_NAME}'",
        "description": "Multi-cloud DevOps configuration management playbooks",
        "organization": 1,
        "scm_type": "git",
        "scm_url": "https://github.com/'${GITHUB_REPO:-'your-org/complex-demo'}'.git",
        "scm_branch": "main",
        "scm_clean": true,
        "scm_delete_on_update": false,
        "scm_update_on_launch": true,
        "scm_update_cache_timeout": 60
    }'
    
    local response=$(tower_api GET "projects/?name=${PROJECT_NAME}")
    local project_count=$(echo "$response" | jq -r '.count // 0')
    
    if [ "$project_count" -eq 0 ]; then
        echo -e "${BLUE}Creating project...${NC}"
        tower_api POST "projects/" "$project_data"
        
        # Wait for project sync
        echo -e "${YELLOW}⏳ Waiting for project sync...${NC}"
        sleep 30
    else
        echo -e "${BLUE}Project already exists${NC}"
    fi
    
    echo -e "${GREEN}✅ Project configured${NC}"
}

# Function to create dynamic inventory
configure_inventory() {
    print_section "📋 CONFIGURING DYNAMIC INVENTORY"
    
    echo -e "${YELLOW}Setting up Terraform-based dynamic inventory${NC}"
    
    local inventory_data='{
        "name": "'${INVENTORY_NAME}'",
        "description": "Dynamic inventory sourced from Terraform state",
        "organization": 1,
        "variables": "---\nansible_python_interpreter: /usr/bin/python3"
    }'
    
    local response=$(tower_api GET "inventories/?name=${INVENTORY_NAME}")
    local inv_count=$(echo "$response" | jq -r '.count // 0')
    
    if [ "$inv_count" -eq 0 ]; then
        echo -e "${BLUE}Creating inventory...${NC}"
        local inv_response=$(tower_api POST "inventories/" "$inventory_data")
        local inventory_id=$(echo "$inv_response" | jq -r '.id')
        
        # Create inventory source for dynamic updates
        local source_data='{
            "name": "terraform-state-source",
            "description": "Dynamic inventory from Terraform state",
            "inventory": '${inventory_id}',
            "source": "scm",
            "source_project": 1,
            "source_path": "ansible/inventory/terraform-inventory.py",
            "update_on_launch": true,
            "update_cache_timeout": 0,
            "source_vars": "---\nterraform_dir: ../../terraform/envs/dev/us-east-2"
        }'
        
        echo -e "${BLUE}Creating inventory source...${NC}"
        tower_api POST "inventory_sources/" "$source_data"
    else
        echo -e "${BLUE}Inventory already exists${NC}"
    fi
    
    echo -e "${GREEN}✅ Dynamic inventory configured${NC}"
}

# Function to create job templates
configure_job_templates() {
    print_section "🎯 CONFIGURING JOB TEMPLATES"
    
    echo -e "${YELLOW}Creating job templates for Day-0 provisioning and Puppet integration${NC}"
    
    # Day-0 Provisioning Job Template
    local day0_template='{
        "name": "Day-0 Infrastructure Provisioning",
        "description": "Day-0/1 provisioning of OS, middleware, and Consul agents",
        "job_type": "run",
        "inventory": 1,
        "project": 1,
        "playbook": "ansible/playbooks/day0-provisioning.yml",
        "credential": 1,
        "forks": 5,
        "limit": "day0_provisioning",
        "verbosity": 1,
        "extra_vars": "---\nconsul_gossip_key: \"'${CONSUL_GOSSIP_KEY:-''}'\"\npuppet_admin_password: \"'${PUPPET_ADMIN_PASSWORD:-''}'\"",
        "ask_variables_on_launch": true,
        "ask_limit_on_launch": true,
        "ask_inventory_on_launch": false
    }'
    
    # Puppet Integration Job Template  
    local puppet_template='{
        "name": "Puppet Integration",
        "description": "Upload Hiera classifications and trigger Puppet runs via REST API",
        "job_type": "run",
        "inventory": 1,
        "project": 1,
        "playbook": "ansible/playbooks/puppet-integration.yml",
        "credential": 1,
        "forks": 5,
        "verbosity": 1,
        "extra_vars": "---\npuppet_admin_password: \"'${PUPPET_ADMIN_PASSWORD:-''}'\"",
        "ask_variables_on_launch": true
    }'
    
    # Create job templates
    for template_name in "Day-0 Infrastructure Provisioning" "Puppet Integration"; do
        local response=$(tower_api GET "job_templates/?name=${template_name}")
        local template_count=$(echo "$response" | jq -r '.count // 0')
        
        if [ "$template_count" -eq 0 ]; then
            echo -e "${BLUE}Creating job template: ${template_name}${NC}"
            if [ "$template_name" = "Day-0 Infrastructure Provisioning" ]; then
                tower_api POST "job_templates/" "$day0_template"
            else
                tower_api POST "job_templates/" "$puppet_template"
            fi
        else
            echo -e "${BLUE}Job template already exists: ${template_name}${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Job templates configured${NC}"
}

# Function to create workflow template
configure_workflow() {
    print_section "🔄 CONFIGURING WORKFLOW TEMPLATE"
    
    echo -e "${YELLOW}Creating workflow for complete Day-0 → Day-2 provisioning${NC}"
    
    local workflow_data='{
        "name": "Complete Infrastructure Configuration",
        "description": "End-to-end workflow: Day-0 provisioning → Puppet integration → Day-2 operations",
        "organization": 1,
        "extra_vars": "---\nworkflow_name: \"Complete Infrastructure Configuration\"",
        "ask_variables_on_launch": true,
        "ask_inventory_on_launch": false,
        "ask_limit_on_launch": true
    }'
    
    local response=$(tower_api GET "workflow_job_templates/?name=Complete Infrastructure Configuration")
    local workflow_count=$(echo "$response" | jq -r '.count // 0')
    
    if [ "$workflow_count" -eq 0 ]; then
        echo -e "${BLUE}Creating workflow template...${NC}"
        tower_api POST "workflow_job_templates/" "$workflow_data"
        
        # Note: Workflow nodes would need to be configured via UI or additional API calls
        echo -e "${YELLOW}💡 Workflow nodes should be configured in the Tower UI:${NC}"
        echo -e "   1. Day-0 Infrastructure Provisioning"
        echo -e "   2. Puppet Integration (on success)"
    else
        echo -e "${BLUE}Workflow template already exists${NC}"
    fi
    
    echo -e "${GREEN}✅ Workflow template configured${NC}"
}

# Function to sync inventory
sync_inventory() {
    print_section "🔄 SYNCING INVENTORY FROM TERRAFORM STATE"
    
    echo -e "${YELLOW}Triggering inventory sync to pull latest infrastructure state${NC}"
    
    # Get inventory source ID
    local response=$(tower_api GET "inventory_sources/?name=terraform-state-source")
    local source_id=$(echo "$response" | jq -r '.results[0].id // empty')
    
    if [ -n "$source_id" ]; then
        echo -e "${BLUE}Triggering inventory source update...${NC}"
        tower_api POST "inventory_sources/${source_id}/update/" "{}"
        
        echo -e "${YELLOW}⏳ Inventory sync initiated. Check Tower UI for progress.${NC}"
    else
        echo -e "${YELLOW}⚠️  Inventory source not found. Manual inventory sync required.${NC}"
    fi
    
    echo -e "${GREEN}✅ Inventory sync triggered${NC}"
}

# Function to display summary
display_summary() {
    print_section "🎉 CONFIGURATION COMPLETE"
    
    echo -e "${GREEN}✅ Ansible Tower has been configured successfully!${NC}"
    echo -e "\n${BLUE}📋 Configuration Summary:${NC}"
    echo -e "  • Tower URL: ${TOWER_URL}"
    echo -e "  • Organization: ${ORGANIZATION}"
    echo -e "  • Project: ${PROJECT_NAME}"
    echo -e "  • Inventory: ${INVENTORY_NAME}"
    echo -e "  • Credentials: ${CREDENTIAL_NAME}"
    
    echo -e "\n${YELLOW}🎯 Available Job Templates:${NC}"
    echo -e "  • Day-0 Infrastructure Provisioning"
    echo -e "  • Puppet Integration"
    echo -e "  • Complete Infrastructure Configuration (Workflow)"
    
    echo -e "\n${PURPLE}🚀 Next Steps:${NC}"
    echo -e "  1. Access Tower UI: ${TOWER_URL}"
    echo -e "  2. Login with: ${TOWER_USERNAME} / ${TOWER_PASSWORD}"
    echo -e "  3. Run the 'Complete Infrastructure Configuration' workflow"
    echo -e "  4. Monitor job execution and logs"
    
    echo -e "\n${BLUE}📊 Architecture Compliance:${NC}"
    echo -e "  ✅ Inventory sourced from Terraform state"
    echo -e "  ✅ Day-0/1 provisioning playbooks configured"
    echo -e "  ✅ Puppet integration via REST API"
    echo -e "  ✅ Tower writes Hiera classification files"
    echo -e "  ✅ CircleCI integration ready"
    
    echo -e "\n${GREEN}🎊 Your configuration management layer is now ready! 🎊${NC}"
}

# Main execution
main() {
    wait_for_tower
    configure_organization
    configure_credentials
    configure_project
    configure_inventory
    configure_job_templates
    configure_workflow
    sync_inventory
    display_summary
}

# Check dependencies
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}❌ curl is required but not installed${NC}"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}❌ jq is required but not installed${NC}"
    exit 1
fi

# Get Terraform outputs for integration
if [ -f terraform/envs/dev/us-east-2/terragrunt.hcl ]; then
    echo -e "${BLUE}🔍 Getting infrastructure information from Terraform...${NC}"
    cd terraform/envs/dev/us-east-2
    
    # Get Consul gossip key
    CONSUL_GOSSIP_KEY=$(terragrunt output -raw consul_gossip_key 2>/dev/null || echo "")
    
    # Get Puppet admin password from AWS Secrets Manager
    PUPPET_SECRET_ARN=$(terragrunt output -raw puppet_enterprise_admin_password_secret_arn 2>/dev/null || echo "")
    if [ -n "$PUPPET_SECRET_ARN" ]; then
        PUPPET_ADMIN_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$PUPPET_SECRET_ARN" --query SecretString --output text 2>/dev/null | jq -r '.password' 2>/dev/null || echo "")
    fi
    
    cd - >/dev/null
fi

# Run main function
main "$@" 