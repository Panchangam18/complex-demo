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

apply: ## Complete pipeline: Build → Push → Deploy infrastructure & applications
	@echo "🚀 Starting complete deployment pipeline for $(ENV)/$(REGION)..."
	@echo "======================================================================"
	@echo "Phase 1: Building and pushing application images to JFrog Artifactory"
	@echo "======================================================================"
	@cd .. && ./scripts/build-and-push.sh
	@echo ""
	@echo "======================================================================"
	@echo "Phase 2: Applying Terraform infrastructure changes"
	@echo "======================================================================"
	@cd $(TG_PATH) && $(TG_CMD) apply -auto-approve
	@echo ""
	@echo "======================================================================"
	@echo "Phase 3: Deploying applications to Kubernetes"
	@echo "======================================================================"
	@echo "Restarting deployments to pick up new images..."
	@kubectl rollout restart deployment/frontend -n frontend-dev 2>/dev/null || echo "Frontend deployment not found (will be created)"
	@kubectl rollout restart deployment/backend -n backend-dev 2>/dev/null || echo "Backend deployment not found (will be created)"
	@echo "Waiting for deployments to complete..."
	@kubectl rollout status deployment/frontend -n frontend-dev --timeout=300s 2>/dev/null || echo "Frontend deployment status check skipped"
	@kubectl rollout status deployment/backend -n backend-dev --timeout=300s 2>/dev/null || echo "Backend deployment status check skipped"
	@echo ""
	@echo "🎉 Complete Deployment Pipeline Finished!"
	@echo "=========================================="
	@echo ""
	@echo "🌐 Application URLs:"
	@echo "- Frontend: $$(kubectl get svc frontend-service -n frontend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null | sed 's/^/http:\/\//' || echo 'Load balancer provisioning...')"
	@echo "- Backend:  $$(kubectl get svc backend-service -n backend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null | sed 's/^/http:\/\//' || echo 'Load balancer provisioning...')"
	@echo ""
	@echo "📊 Infrastructure:"
	@echo "- EKS Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw eks_cluster_id 2>/dev/null || echo 'Not deployed')"
	@echo "- GKE Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw gke_cluster_name 2>/dev/null || echo 'Not deployed')"
	@echo "- Consul UI: $$(cd $(TG_PATH) && $(TG_CMD) output -raw consul_ui_url 2>/dev/null || echo 'Not available')"
	@echo ""
	@echo "🔍 Monitoring:"
	@echo "- Check app status: make status ENV=$(ENV) REGION=$(REGION)"
	@echo "- View logs: make logs ENV=$(ENV) REGION=$(REGION)"
	@echo "- Full stack status: make deploy-full-stack ENV=$(ENV) REGION=$(REGION)"

apply-infra-only: ## Apply only Terraform infrastructure changes (no app rebuild)
	@echo "Applying Terraform changes for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && $(TG_CMD) apply -auto-approve
	@echo ""
	@echo "🎉 Infrastructure Deployment Complete!"
	@echo "======================================"
	@echo ""
	@echo "📊 Infrastructure Details:"
	@echo "- EKS Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw eks_cluster_id 2>/dev/null || echo 'Not deployed')"
	@echo "- GKE Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw gke_cluster_name 2>/dev/null || echo 'Not deployed')"
	@echo "- Consul UI: $$(cd $(TG_PATH) && $(TG_CMD) output -raw consul_ui_url 2>/dev/null || echo 'Not available')"

deploy-full-stack: ## Deploy infrastructure + applications + images (full stack)
	@echo "🚀 Starting full stack deployment for $(ENV)/$(REGION)..."
	@cd .. && ./scripts/deploy-full-stack.sh -e $(ENV) -r $(REGION) -p $(AWS_PROFILE)

deploy-apps-only: ## Deploy only applications (skip infrastructure)
	@echo "🐳 Deploying applications only for $(ENV)/$(REGION)..."
	@cd .. && ./scripts/deploy-full-stack.sh -e $(ENV) -r $(REGION) -p $(AWS_PROFILE) --skip-terraform

deploy-infra-only: ## Deploy only infrastructure (skip applications)
	@echo "🏗️  Deploying infrastructure only for $(ENV)/$(REGION)..."
	@cd .. && ./scripts/deploy-full-stack.sh -e $(ENV) -r $(REGION) -p $(AWS_PROFILE) --skip-images --skip-k8s-update

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

# --------------------------------------------------
# Application Management Targets
# --------------------------------------------------

build-push: ## Build and push application images to JFrog Artifactory
	@echo "🐳 Building and pushing application images..."
	@cd .. && ./scripts/build-and-push.sh

deploy-apps: ## Deploy applications to Kubernetes (restart deployments)
	@echo "🚀 Deploying applications to Kubernetes..."
	@echo "Restarting deployments to pick up latest images..."
	@kubectl rollout restart deployment/frontend -n frontend-dev
	@kubectl rollout restart deployment/backend -n backend-dev
	@echo "Waiting for deployments to complete..."
	@kubectl rollout status deployment/frontend -n frontend-dev --timeout=300s
	@kubectl rollout status deployment/backend -n backend-dev --timeout=300s
	@echo "✅ Application deployment complete!"

status: ## Check application and infrastructure status
	@echo "📊 Application & Infrastructure Status"
	@echo "====================================="
	@echo ""
	@echo "🌐 Application URLs:"
	@echo "- Frontend: $$(kubectl get svc frontend-service -n frontend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null | sed 's/^/http:\/\//' || echo 'Load balancer not ready')"
	@echo "- Backend:  $$(kubectl get svc backend-service -n backend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null | sed 's/^/http:\/\//' || echo 'Load balancer not ready')"
	@echo ""
	@echo "🚀 Pod Status:"
	@kubectl get pods -n frontend-dev -o wide 2>/dev/null || echo "Frontend namespace not found"
	@kubectl get pods -n backend-dev -o wide 2>/dev/null || echo "Backend namespace not found"
	@echo ""
	@echo "🔗 Service Status:"
	@kubectl get svc -n frontend-dev 2>/dev/null || echo "Frontend services not found"
	@kubectl get svc -n backend-dev 2>/dev/null || echo "Backend services not found"

logs: ## View application logs
	@echo "📝 Application Logs"
	@echo "=================="
	@echo ""
	@echo "🖥️  Frontend Logs:"
	@kubectl logs -l app=frontend -n frontend-dev --tail=20 2>/dev/null || echo "No frontend logs available"
	@echo ""
	@echo "⚙️  Backend Logs:"
	@kubectl logs -l app=backend -n backend-dev --tail=20 2>/dev/null || echo "No backend logs available"

logs-follow: ## Follow application logs in real-time
	@echo "📝 Following application logs (Ctrl+C to stop)..."
	@echo "Frontend logs will appear below:"
	@kubectl logs -f -l app=frontend -n frontend-dev 2>/dev/null &
	@echo "Backend logs will appear below:"
	@kubectl logs -f -l app=backend -n backend-dev 2>/dev/null

test-apps: ## Test application endpoints
	@echo "🧪 Testing Application Endpoints"
	@echo "==============================="
	@echo ""
	@echo "Testing Frontend..."
	@FRONTEND_URL=$$(kubectl get svc frontend-service -n frontend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ ! -z "$$FRONTEND_URL" ]; then \
		curl -s -o /dev/null -w "Frontend Status: %{http_code}\n" http://$$FRONTEND_URL || echo "Frontend test failed"; \
	else \
		echo "Frontend URL not available yet"; \
	fi
	@echo ""
	@echo "Testing Backend..."
	@BACKEND_URL=$$(kubectl get svc backend-service -n backend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ ! -z "$$BACKEND_URL" ]; then \
		curl -s -o /dev/null -w "Backend Status: %{http_code}\n" http://$$BACKEND_URL/status || echo "Backend test failed"; \
	else \
		echo "Backend URL not available yet"; \
	fi

scale: ## Scale applications (usage: make scale FRONTEND_REPLICAS=3 BACKEND_REPLICAS=5)
	@FRONTEND_REPLICAS=$${FRONTEND_REPLICAS:-2}; \
	BACKEND_REPLICAS=$${BACKEND_REPLICAS:-3}; \
	echo "📈 Scaling applications..."; \
	echo "Frontend: $$FRONTEND_REPLICAS replicas"; \
	echo "Backend: $$BACKEND_REPLICAS replicas"; \
	kubectl scale deployment frontend --replicas=$$FRONTEND_REPLICAS -n frontend-dev; \
	kubectl scale deployment backend --replicas=$$BACKEND_REPLICAS -n backend-dev; \
	echo "✅ Scaling complete!"

quick-deploy: ## Quick app-only deployment (build → push → deploy)
	@echo "⚡ Quick Application Deployment"
	@echo "=============================="
	@make build-push
	@make deploy-apps
	@make status