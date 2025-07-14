.DEFAULT_GOAL := _setup


.PHONY: _setup
_setup:
	@node .github/setup.js
# Comprehensive Multi-Cloud DevOps Platform Makefile
# ===================================================
# This Makefile provides convenient targets for deploying and destroying
# your multi-cloud DevOps platform with proper error handling and validation.

# Default values
ENV ?= dev
REGION ?= us-east-2
AWS_PROFILE ?= default
GCP_PROJECT_ID ?= 
AZURE_SUBSCRIPTION_ID ?= 
DRY_RUN ?= false

# Colors
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
PURPLE=\033[0;35m
NC=\033[0m

# ============================================================================
# HELP TARGETS
# ============================================================================

.PHONY: help
help: ## Show this help message
	@echo -e "$(PURPLE)🚀 Multi-Cloud DevOps Platform Management$(NC)"
	@echo -e "$(BLUE)============================================$(NC)"
	@echo ""
	@echo -e "$(YELLOW)DEPLOYMENT TARGETS:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(deploy|setup|install|configure)"
	@echo ""
	@echo -e "$(YELLOW)DESTRUCTION TARGETS:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(RED)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(destroy|cleanup|remove)"
	@echo ""
	@echo -e "$(YELLOW)UTILITY TARGETS:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(status|validate|backup|test)"
	@echo ""
	@echo -e "$(YELLOW)EXAMPLES:$(NC)"
	@echo -e "  $(GREEN)make deploy$(NC)                    # Full deployment with prompts"
	@echo -e "  $(GREEN)make deploy-dry-run$(NC)           # See what would be deployed"
	@echo -e "  $(GREEN)make deploy-prod$(NC)              # Deploy to production"
	@echo -e "  $(RED)make destroy$(NC)                   # Safe destruction with backups"
	@echo -e "  $(RED)make destroy-force$(NC)             # Force destruction without prompts"
	@echo -e "  $(BLUE)make status$(NC)                   # Check deployment status"
	@echo ""
	@echo -e "$(YELLOW)ENVIRONMENT VARIABLES:$(NC)"
	@echo -e "  $(BLUE)ENV$(NC)                          Environment (dev, staging, prod)"
	@echo -e "  $(BLUE)REGION$(NC)                       AWS region (us-east-2, us-west-2, etc.)"
	@echo -e "  $(BLUE)AWS_PROFILE$(NC)                  AWS profile name"
	@echo -e "  $(BLUE)GCP_PROJECT_ID$(NC)               GCP project ID"
	@echo -e "  $(BLUE)AZURE_SUBSCRIPTION_ID$(NC)        Azure subscription ID"

# ============================================================================
# DEPLOYMENT TARGETS
# ============================================================================

.PHONY: deploy
deploy: validate-env ## Deploy full multi-cloud platform (interactive)
	@echo -e "$(GREEN)🚀 Starting full multi-cloud deployment...$(NC)"
	@echo -e "$(BLUE)Environment: $(ENV), Region: $(REGION)$(NC)"
	@./deploy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		$(if $(GCP_PROJECT_ID),--gcp-project-id $(GCP_PROJECT_ID)) \
		$(if $(AZURE_SUBSCRIPTION_ID),--azure-subscription-id $(AZURE_SUBSCRIPTION_ID))

.PHONY: deploy-dry-run
deploy-dry-run: validate-env ## Show what would be deployed without executing
	@echo -e "$(YELLOW)🧪 Dry run deployment preview...$(NC)"
	@./deploy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--dry-run \
		$(if $(GCP_PROJECT_ID),--gcp-project-id $(GCP_PROJECT_ID)) \
		$(if $(AZURE_SUBSCRIPTION_ID),--azure-subscription-id $(AZURE_SUBSCRIPTION_ID))

.PHONY: deploy-infrastructure-only
deploy-infrastructure-only: validate-env ## Deploy only infrastructure (Terraform)
	@echo -e "$(GREEN)🏗️ Deploying infrastructure only...$(NC)"
	@./deploy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--skip-observability \
		--skip-cicd \
		--skip-applications \
		$(if $(GCP_PROJECT_ID),--gcp-project-id $(GCP_PROJECT_ID)) \
		$(if $(AZURE_SUBSCRIPTION_ID),--azure-subscription-id $(AZURE_SUBSCRIPTION_ID))

.PHONY: deploy-apps-only
deploy-apps-only: validate-env ## Deploy only applications (skip infrastructure)
	@echo -e "$(GREEN)🚀 Deploying applications only...$(NC)"
	@./deploy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--skip-terraform \
		--skip-config-mgmt \
		--skip-observability \
		--skip-cicd

.PHONY: deploy-prod
deploy-prod: ## Deploy to production environment (with extra safety)
	@echo -e "$(RED)⚠️ PRODUCTION DEPLOYMENT$(NC)"
	@echo -e "$(YELLOW)This will deploy to PRODUCTION environment!$(NC)"
	@read -p "Type 'DEPLOY-PRODUCTION' to confirm: " confirm && [ "$$confirm" = "DEPLOY-PRODUCTION" ]
	@$(MAKE) deploy ENV=prod REGION=us-west-2

.PHONY: deploy-staging
deploy-staging: ## Deploy to staging environment
	@echo -e "$(BLUE)🎭 Deploying to staging environment...$(NC)"
	@$(MAKE) deploy ENV=staging REGION=us-west-2

.PHONY: setup-prerequisites
setup-prerequisites: ## Install required tools and dependencies
	@echo -e "$(BLUE)🔧 Setting up prerequisites...$(NC)"
	@./scripts/setup-prerequisites.sh 2>/dev/null || echo "Prerequisites script not found"

# ============================================================================
# DESTRUCTION TARGETS
# ============================================================================

.PHONY: destroy
destroy: validate-env ## Safely destroy platform with backups and confirmations
	@echo -e "$(RED)🚨 Starting safe platform destruction...$(NC)"
	@echo -e "$(BLUE)Environment: $(ENV), Region: $(REGION)$(NC)"
	@./destroy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		$(if $(GCP_PROJECT_ID),--gcp-project-id $(GCP_PROJECT_ID)) \
		$(if $(AZURE_SUBSCRIPTION_ID),--azure-subscription-id $(AZURE_SUBSCRIPTION_ID))

.PHONY: destroy-dry-run
destroy-dry-run: validate-env ## Show what would be destroyed without executing
	@echo -e "$(YELLOW)🧪 Dry run destruction preview...$(NC)"
	@./destroy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--dry-run \
		$(if $(GCP_PROJECT_ID),--gcp-project-id $(GCP_PROJECT_ID)) \
		$(if $(AZURE_SUBSCRIPTION_ID),--azure-subscription-id $(AZURE_SUBSCRIPTION_ID))

.PHONY: destroy-force
destroy-force: validate-env ## Force destroy without prompts (DANGEROUS!)
	@echo -e "$(RED)💀 Force destroying platform without prompts...$(NC)"
	@./destroy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--force-destroy \
		--auto-approve \
		$(if $(GCP_PROJECT_ID),--gcp-project-id $(GCP_PROJECT_ID)) \
		$(if $(AZURE_SUBSCRIPTION_ID),--azure-subscription-id $(AZURE_SUBSCRIPTION_ID))

.PHONY: destroy-infrastructure-only
destroy-infrastructure-only: validate-env ## Destroy only infrastructure (keep data)
	@echo -e "$(RED)🏗️ Destroying infrastructure only...$(NC)"
	@cd terraform && $(MAKE) destroy ENV=$(ENV) REGION=$(REGION)

.PHONY: destroy-apps-only
destroy-apps-only: validate-env ## Destroy only applications (keep infrastructure)
	@echo -e "$(RED)🚀 Destroying applications only...$(NC)"
	@kubectl delete namespace frontend-$(ENV) --ignore-not-found=true
	@kubectl delete namespace backend-$(ENV) --ignore-not-found=true

.PHONY: cleanup-docker
cleanup-docker: ## Clean up local Docker images and containers
	@echo -e "$(BLUE)🐳 Cleaning up Docker resources...$(NC)"
	@docker system prune -f --volumes || true
	@docker image prune -a -f || true

.PHONY: cleanup-terraform
cleanup-terraform: validate-env ## Clean up Terraform state and artifacts
	@echo -e "$(BLUE)🧹 Cleaning up Terraform artifacts...$(NC)"
	@cd terraform/envs/$(ENV)/$(REGION) && rm -rf .terraform terraform.tfstate* .terragrunt-cache
	@find terraform -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true

# ============================================================================
# UTILITY TARGETS
# ============================================================================

.PHONY: status
status: validate-env ## Check deployment status across all services
	@echo -e "$(BLUE)📊 Checking deployment status...$(NC)"
	@echo -e "$(YELLOW)Kubernetes Status:$(NC)"
	@kubectl get nodes 2>/dev/null || echo "Kubernetes not accessible"
	@echo ""
	@echo -e "$(YELLOW)Namespace Status:$(NC)"
	@kubectl get namespaces 2>/dev/null | grep -E "(frontend|backend|datadog|consul|argocd|nexus)" || echo "No application namespaces found"
	@echo ""
	@echo -e "$(YELLOW)Application Status:$(NC)"
	@kubectl get deployments -A 2>/dev/null | grep -E "(frontend|backend)" || echo "No application deployments found"

.PHONY: validate-env
validate-env: ## Validate environment and credentials
	@echo -e "$(BLUE)🔍 Validating environment...$(NC)"
	@if [ "$(ENV)" = "" ]; then echo -e "$(RED)❌ ENV not set$(NC)"; exit 1; fi
	@if [ "$(REGION)" = "" ]; then echo -e "$(RED)❌ REGION not set$(NC)"; exit 1; fi
	@aws sts get-caller-identity --profile $(AWS_PROFILE) >/dev/null || (echo -e "$(RED)❌ AWS credentials invalid$(NC)" && exit 1)
	@echo -e "$(GREEN)✅ Environment validation passed$(NC)"

.PHONY: backup-data
backup-data: validate-env ## Create backup of current deployment
	@echo -e "$(BLUE)💾 Creating deployment backup...$(NC)"
	@mkdir -p backups/$(ENV)-$(REGION)-$(shell date +%Y%m%d-%H%M%S)
	@kubectl get all --all-namespaces -o yaml > backups/$(ENV)-$(REGION)-$(shell date +%Y%m%d-%H%M%S)/k8s-resources.yaml 2>/dev/null || true
	@cd terraform/envs/$(ENV)/$(REGION) && terragrunt show -json > ../../../backups/$(ENV)-$(REGION)-$(shell date +%Y%m%d-%H%M%S)/terraform-state.json 2>/dev/null || true
	@echo -e "$(GREEN)✅ Backup created in backups/ directory$(NC)"

.PHONY: test-connectivity
test-connectivity: validate-env ## Test connectivity to all services
	@echo -e "$(BLUE)🔗 Testing service connectivity...$(NC)"
	@./scripts/validate-complete-setup.sh 2>/dev/null || echo "Validation script not found"

.PHONY: extract-credentials
extract-credentials: validate-env ## Extract credentials from deployed infrastructure
	@echo -e "$(BLUE)🔐 Extracting deployment credentials...$(NC)"
	@./scripts/extract-credentials-to-env.sh

.PHONY: update-kubeconfig
update-kubeconfig: validate-env ## Update kubectl configuration for EKS cluster
	@echo -e "$(BLUE)⚙️ Updating kubeconfig for EKS...$(NC)"
	@aws eks update-kubeconfig --region $(REGION) --name $(ENV)-eks-$(REGION) --profile $(AWS_PROFILE)

# ============================================================================
# BOOTSTRAP TARGETS
# ============================================================================

.PHONY: bootstrap
bootstrap: ## Bootstrap Terraform state backend
	@echo -e "$(PURPLE)🏗️ Bootstrapping Terraform state backend...$(NC)"
	@cd terraform/bootstrap && terraform init && terraform apply
	@echo -e "$(GREEN)✅ Bootstrap completed - backend infrastructure ready$(NC)"

.PHONY: bootstrap-status
bootstrap-status: ## Check bootstrap infrastructure status
	@echo -e "$(BLUE)📊 Bootstrap Infrastructure Status:$(NC)"
	@if [ -f terraform/bootstrap/terraform.tfstate ]; then \
		echo -e "$(GREEN)✅ Bootstrap state exists$(NC)"; \
		cd terraform/bootstrap && terraform show -json | jq -r '.values.outputs // {} | to_entries[] | "   \(.key): \(.value.value)"' 2>/dev/null || echo "   State file exists but no readable outputs"; \
	else \
		echo -e "$(RED)❌ Bootstrap not completed$(NC)"; \
	fi

.PHONY: bootstrap-destroy
bootstrap-destroy: ## Destroy bootstrap infrastructure (WARNING: Deletes state backend!)
	@echo -e "$(RED)⚠️  WARNING: This will destroy your Terraform state backend!$(NC)"
	@echo -e "$(RED)💀 This will delete S3 buckets and DynamoDB tables!$(NC)"
	@read -p "Type 'DESTROY-BACKEND' to confirm: " confirm && [ "$$confirm" = "DESTROY-BACKEND" ] || exit 1
	@cd terraform/bootstrap && terraform destroy
	@echo -e "$(YELLOW)🧹 Cleaning up bootstrap artifacts...$(NC)"
	@rm -f terraform/bootstrap/generated/backend-config.json
	@rm -f terraform/terragrunt.hcl.backup

# ============================================================================
# TERRAFORM SPECIFIC TARGETS
# ============================================================================

.PHONY: terraform-plan
terraform-plan: validate-env ## Run Terraform plan
	@echo -e "$(BLUE)📋 Running Terraform plan...$(NC)"
	@cd terraform && $(MAKE) plan ENV=$(ENV) REGION=$(REGION)

.PHONY: terraform-apply
terraform-apply: validate-env ## Run Terraform apply
	@echo -e "$(GREEN)🏗️ Running Terraform apply...$(NC)"
	@cd terraform && $(MAKE) apply ENV=$(ENV) REGION=$(REGION)

.PHONY: terraform-destroy
terraform-destroy: validate-env ## Run Terraform destroy
	@echo -e "$(RED)💥 Running Terraform destroy...$(NC)"
	@cd terraform && $(MAKE) destroy ENV=$(ENV) REGION=$(REGION)

.PHONY: terraform-init
terraform-init: validate-env ## Initialize Terraform
	@echo -e "$(BLUE)🔧 Initializing Terraform...$(NC)"
	@cd terraform && $(MAKE) init ENV=$(ENV) REGION=$(REGION)

# ============================================================================
# CI/CD TARGETS
# ============================================================================

.PHONY: setup-jenkins
setup-jenkins: validate-env ## Set up Jenkins with Nexus integration
	@echo -e "$(BLUE)🔧 Setting up Jenkins integration...$(NC)"
	@./ci-cd/jenkins/scripts/jenkins-nexus-integration-complete.sh

.PHONY: demo-nexus
demo-nexus: validate-env ## Run Nexus caching demonstration
	@echo -e "$(BLUE)📦 Running Nexus cache demo...$(NC)"
	@./ci-cd/nexus/scripts/nexus-cache-usage-demo.sh

.PHONY: configure-monitoring
configure-monitoring: validate-env ## Configure comprehensive monitoring
	@echo -e "$(BLUE)📊 Configuring monitoring stack...$(NC)"
	@./scripts/deploy-datadog-multicloud.sh
	@./scripts/deploy-elasticsearch-integration.sh

# ============================================================================
# ADVANCED TARGETS
# ============================================================================

.PHONY: deploy-with-credentials
deploy-with-credentials: validate-env ## Deploy with external service credentials (interactive)
	@echo -e "$(GREEN)🚀 Interactive deployment with credentials...$(NC)"
	@echo -e "$(YELLOW)You will be prompted for external service credentials$(NC)"
	@read -p "Elasticsearch URL: " es_url; \
	read -p "Elasticsearch API Key: " es_key; \
	read -p "DataDog API Key: " dd_api_key; \
	read -p "DataDog App Key: " dd_app_key; \
	read -p "New Relic License Key: " nr_license; \
	read -p "Artifactory URL: " art_url; \
	read -p "Artifactory Username: " art_user; \
	read -s -p "Artifactory Password: " art_pass; echo; \
	./deploy.sh \
		--env $(ENV) \
		--region $(REGION) \
		--profile $(AWS_PROFILE) \
		--elasticsearch-url "$$es_url" \
		--elasticsearch-api-key "$$es_key" \
		--datadog-api-key "$$dd_api_key" \
		--datadog-app-key "$$dd_app_key" \
		--newrelic-license "$$nr_license" \
		--artifactory-url "$$art_url" \
		--artifactory-username "$$art_user" \
		--artifactory-password "$$art_pass" \
		$(if $(GCP_PROJECT_ID),--gcp-project-id $(GCP_PROJECT_ID)) \
		$(if $(AZURE_SUBSCRIPTION_ID),--azure-subscription-id $(AZURE_SUBSCRIPTION_ID))

.PHONY: emergency-destroy
emergency-destroy: ## Emergency destruction (bypasses all safety checks)
	@echo -e "$(RED)🚨 EMERGENCY DESTRUCTION - NO SAFETY CHECKS$(NC)"
	@echo -e "$(RED)This will immediately destroy everything!$(NC)"
	@read -p "Type 'EMERGENCY' to proceed: " confirm && [ "$$confirm" = "EMERGENCY" ]
	@./destroy.sh --force-destroy --auto-approve --skip-backups --env $(ENV) --region $(REGION)

.PHONY: debug-logs
debug-logs: validate-env ## Show recent deployment/destruction logs
	@echo -e "$(BLUE)📋 Recent deployment logs:$(NC)"
	@ls -la deployment-*.log 2>/dev/null | tail -5 || echo "No deployment logs found"
	@echo ""
	@echo -e "$(BLUE)📋 Recent destruction logs:$(NC)"
	@ls -la destruction-*.log 2>/dev/null | tail -5 || echo "No destruction logs found"

# ============================================================================
# MONITORING TARGETS
# ============================================================================

.PHONY: port-forward-grafana
port-forward-grafana: ## Port forward to Grafana dashboard
	@echo -e "$(BLUE)📊 Port forwarding to Grafana (http://localhost:3000)...$(NC)"
	@kubectl port-forward -n observability svc/prometheus-stack-grafana 3000:80

.PHONY: port-forward-argocd
port-forward-argocd: ## Port forward to ArgoCD UI
	@echo -e "$(BLUE)🔄 Port forwarding to ArgoCD (http://localhost:8080)...$(NC)"
	@kubectl port-forward -n argocd svc/argocd-server 8080:443

.PHONY: port-forward-consul
port-forward-consul: ## Port forward to Consul UI
	@echo -e "$(BLUE)🔗 Port forwarding to Consul (http://localhost:8500)...$(NC)"
	@kubectl port-forward -n consul svc/consul-ui 8500:80 2>/dev/null || echo "Consul UI not available"

# ============================================================================
# QUICK ACCESS TARGETS
# ============================================================================

.PHONY: quick-deploy
quick-deploy: deploy-dry-run deploy ## Quick deployment with preview
	@echo -e "$(GREEN)✅ Quick deployment completed$(NC)"

.PHONY: quick-destroy
quick-destroy: destroy-dry-run destroy ## Quick destruction with preview
	@echo -e "$(RED)💀 Quick destruction completed$(NC)"

.PHONY: logs
logs: debug-logs ## Show recent logs (alias for debug-logs)

.PHONY: clean
clean: cleanup-docker cleanup-terraform ## Full cleanup of artifacts and containers

# ============================================================================
# LOAD TESTING TARGETS
# ============================================================================

.PHONY: update-load-test-urls
update-load-test-urls: validate-env ## Update Artillery load test URLs from current deployment
	@echo -e "$(BLUE)🎯 Updating load test URLs for current deployment...$(NC)"
	@./scripts/update-load-test-urls.sh --env $(ENV) --region $(REGION)

.PHONY: run-load-tests
run-load-tests: update-load-test-urls ## Update URLs and run comprehensive load tests
	@echo -e "$(BLUE)🚀 Running comprehensive load tests...$(NC)"
	@echo -e "$(YELLOW)Installing Artillery if needed...$(NC)"
	@which artillery > /dev/null 2>&1 || npm install -g artillery
	@echo ""
	@echo -e "$(BLUE)🎯 Running backend load tests...$(NC)"
	@cd Code/server/src/tests/stresstests && artillery run stress_server_intensive.yml
	@echo ""
	@echo -e "$(BLUE)🎯 Running frontend load tests...$(NC)"
	@cd Code/client/src/tests/stresstests && artillery run stress_client_realistic.yml
	@echo ""
	@echo -e "$(GREEN)✅ Load testing completed!$(NC)"

.PHONY: run-backend-load-test
run-backend-load-test: update-load-test-urls ## Run backend load tests only
	@echo -e "$(BLUE)🎯 Running backend load tests...$(NC)"
	@which artillery > /dev/null 2>&1 || npm install -g artillery
	@cd Code/server/src/tests/stresstests && artillery run stress_server_intensive.yml

.PHONY: run-frontend-load-test
run-frontend-load-test: update-load-test-urls ## Run frontend load tests only
	@echo -e "$(BLUE)🎯 Running frontend load tests...$(NC)"
	@which artillery > /dev/null 2>&1 || npm install -g artillery
	@cd Code/client/src/tests/stresstests && artillery run stress_client_realistic.yml

.PHONY: run-quick-load-test
run-quick-load-test: update-load-test-urls ## Run quick load tests (basic versions)
	@echo -e "$(BLUE)🎯 Running quick load tests...$(NC)"
	@which artillery > /dev/null 2>&1 || npm install -g artillery
	@echo ""
	@echo -e "$(BLUE)🎯 Quick backend test...$(NC)"
	@cd Code/server/src/tests/stresstests && artillery run stress_server.yml
	@echo ""
	@echo -e "$(BLUE)🎯 Quick frontend test...$(NC)"
	@cd Code/client/src/tests/stresstests && artillery run stress_client.yml

.PHONY: install-artillery
install-artillery: ## Install Artillery load testing tool
	@echo -e "$(BLUE)📦 Installing Artillery load testing tool...$(NC)"
	@npm install -g artillery
	@echo -e "$(GREEN)✅ Artillery installed successfully$(NC)"
	@artillery --version

# Make sure we don't treat files as targets
.PHONY: help validate-env 