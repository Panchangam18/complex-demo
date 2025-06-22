# Terraform Multicloud DevOps Stack Makefile

.PHONY: help init plan apply destroy fmt validate clean

# Default environment
ENV ?= dev
REGION ?= us-east-2
CLOUD ?= aws
# Note: REGION here refers to the directory name, not the AWS deployment region
# The actual AWS region is configured in terragrunt.hcl

# Terragrunt paths
TG_PATH = envs/$(ENV)/$(REGION)

help: ## Show this help message
	@echo "Terraform Multicloud DevOps Stack"
	@echo "================================="
	@echo ""
	@echo "Usage: make [target] ENV=<env> REGION=<region>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make init ENV=dev REGION=us-east-2"
	@echo "  make plan ENV=staging REGION=eu-west-1"
	@echo "  make apply ENV=prod REGION=us-west-2"

install-tools: ## Install required tools (terragrunt, tflint, etc.)
	@echo "Installing required tools..."
	@which terragrunt > /dev/null || (echo "Installing terragrunt..." && brew install terragrunt)
	@which tflint > /dev/null || (echo "Installing tflint..." && brew install tflint)
	@which checkov > /dev/null || (echo "Installing checkov..." && pip3 install checkov)
	@echo "Tools installed successfully!"

init: ## Initialize Terraform for the specified environment
	@echo "Initializing Terraform for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && terragrunt init

plan: ## Run Terraform plan for the specified environment
	@echo "Running Terraform plan for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && terragrunt plan

apply: ## Apply Terraform changes for the specified environment
	@echo "Applying Terraform changes for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && terragrunt apply -auto-approve

destroy: ## Destroy Terraform resources for the specified environment
	@echo "Destroying Terraform resources for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && terragrunt destroy -auto-approve

fmt: ## Format all Terraform files
	@echo "Formatting Terraform files..."
	@terraform fmt -recursive .

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	@cd $(TG_PATH) && terragrunt validate

lint: ## Run tflint on all modules
	@echo "Running tflint..."
	@find modules -name "*.tf" -exec dirname {} \; | sort -u | xargs -I {} sh -c 'cd {} && tflint'

security-scan: ## Run Checkov security scan
	@echo "Running security scan with Checkov..."
	@checkov -d . --framework terraform

clean: ## Clean up Terraform cache and lock files
	@echo "Cleaning up Terraform files..."
	@find . -type d -name ".terraform" -exec rm -rf {} +
	@find . -type f -name ".terraform.lock.hcl" -exec rm -f {} +
	@echo "Cleanup complete!"

show-outputs: ## Show outputs for the specified environment
	@echo "Showing outputs for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && terragrunt output

create-workspace: ## Create a new environment workspace
	@echo "Creating workspace structure for $(ENV)/$(REGION)..."
	@mkdir -p envs/$(ENV)/$(REGION)
	@cp envs/dev/us-east-2/terragrunt.hcl envs/$(ENV)/$(REGION)/
	@echo "Workspace created. Please update the configuration in envs/$(ENV)/$(REGION)/terragrunt.hcl"

graph: ## Generate dependency graph
	@echo "Generating dependency graph for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && terragrunt graph | dot -Tpng > ../../../docs/$(ENV)-$(REGION)-graph.png
	@echo "Graph saved to docs/$(ENV)-$(REGION)-graph.png"