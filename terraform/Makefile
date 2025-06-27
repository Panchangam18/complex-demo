# Terraform Multicloud DevOps Stack Makefile

.PHONY: help init plan apply destroy fmt validate clean import

# Default environment
ENV ?= dev
REGION ?= us-east-2
CLOUD ?= aws
# Note: REGION here refers to the directory name, not the AWS deployment region
# The actual AWS region is configured in terragrunt.hcl

# Terragrunt paths
TG_PATH = envs/$(ENV)/$(REGION)

# AWS profile to use for authentication (override when needed, e.g. `make apply AWS_PROFILE=my-profile`)
AWS_PROFILE ?= default

# Common Terragrunt command prefix (non-interactive to avoid prompts)
TG_CMD = AWS_PROFILE=$(AWS_PROFILE) TG_NON_INTERACTIVE=true terragrunt

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
	@cd $(TG_PATH) && $(TG_CMD) init

plan: ## Run Terraform plan for the specified environment
	@echo "Running Terraform plan for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && $(TG_CMD) plan

apply: ## Apply Terraform changes for the specified environment
	@echo "Applying Terraform changes for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && $(TG_CMD) apply -auto-approve
	@echo ""
	@echo "🎉 Deployment Complete! Here are your infrastructure details:"
	@echo "=============================================================="
	@echo ""
	@echo "🔗 Consul Service Discovery & Service Mesh:"
	@cd $(TG_PATH) && $(TG_CMD) output consul_summary 2>/dev/null || echo "Consul deployment in progress..."
	@echo ""
	@echo "📊 Multi-Cloud Infrastructure:"
	@echo "- EKS Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw eks_cluster_id 2>/dev/null || echo 'Not deployed')"
	@echo "- GKE Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw gke_cluster_name 2>/dev/null || echo 'Not deployed')"
	@echo "- Consul UI: $$(cd $(TG_PATH) && $(TG_CMD) output -raw consul_ui_url 2>/dev/null || echo 'Not available')"
	@echo ""
	@echo "🚀 Next Steps:"
	@echo "- Check Consul status: make consul-status ENV=$(ENV) REGION=$(REGION)"
	@echo "- View all outputs: make show-outputs ENV=$(ENV) REGION=$(REGION)"

cleanup: ## Clean up cloud resources that might block Terraform destroy
	@echo "Running pre-destroy cleanup for $(ENV)/$(REGION)..."
	@AWS_PROFILE=$(AWS_PROFILE) ENV=$(ENV) AWS_REGION=$(REGION) ./scripts/pre-destroy-cleanup.sh

destroy: cleanup ## Destroy Terraform resources for the specified environment (with pre-cleanup)
	@echo "Destroying Terraform resources for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && $(TG_CMD) destroy -auto-approve

destroy-force: ## Destroy Terraform resources WITHOUT pre-cleanup (use with caution)
	@echo "Destroying Terraform resources for $(ENV)/$(REGION) WITHOUT cleanup..."
	@cd $(TG_PATH) && $(TG_CMD) destroy -auto-approve

fmt: ## Format all Terraform files
	@echo "Formatting Terraform files..."
	@terraform fmt -recursive .

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	@cd $(TG_PATH) && $(TG_CMD) validate

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
	@cd $(TG_PATH) && $(TG_CMD) output

consul-status: ## Check Consul multi-cloud deployment status
	@echo "Checking Consul status for $(ENV)/$(REGION)..."
	@./scripts/consul-status.sh $(ENV) $(REGION)

create-workspace: ## Create a new environment workspace
	@echo "Creating workspace structure for $(ENV)/$(REGION)..."
	@mkdir -p envs/$(ENV)/$(REGION)
	@cp envs/dev/us-east-2/terragrunt.hcl envs/$(ENV)/$(REGION)/
	@echo "Workspace created. Please update the configuration in envs/$(ENV)/$(REGION)/terragrunt.hcl"

graph: ## Generate dependency graph
	@echo "Generating dependency graph for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && $(TG_CMD) graph | dot -Tpng > ../../../docs/$(ENV)-$(REGION)-graph.png
	@echo "Graph saved to docs/$(ENV)-$(REGION)-graph.png"

# --------------------------------------------------
# Resource import helper
# --------------------------------------------------

import: ## Import an existing resource into the state (usage: make import ADDRESS=<addr> ID=<id>)
	@if [ -z "$(ADDRESS)" ] || [ -z "$(ID)" ]; then \
	  echo "ERROR: ADDRESS and ID variables are required."; \
	  echo "Example: make import ADDRESS=module.aws_vpc.aws_subnet.private[0] ID=subnet-012345"; \
	  exit 1; \
	fi
	@echo "Importing $(ADDRESS) (ID=$(ID)) into $(ENV)/$(REGION) using profile $(AWS_PROFILE)..."
	@cd $(TG_PATH) && $(TG_CMD) import '$(ADDRESS)' $(ID)