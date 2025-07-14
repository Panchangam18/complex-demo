# Terraform Multicloud DevOps Stack Makefile

.PHONY: help init plan apply destroy fmt validate clean import

# Default environment
ENV ?= dev
REGION ?= us-east-2
GCP_REGION ?= us-east1
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
	@NEW_TAG=$$(date +%Y%m%d-%H%M%S); \
	cd .. && IMAGE_TAG=$$NEW_TAG ./scripts/build-and-push.sh; \
	echo "Built images with tag: $$NEW_TAG"
	@echo ""
	@echo "======================================================================"
	@echo "Phase 2: Deploying infrastructure using two-stage approach"
	@echo "======================================================================"
	@$(MAKE) apply-infra-and-k8s ENV=$(ENV) REGION=$(REGION) AWS_PROFILE=$(AWS_PROFILE)
	@echo ""
	@echo "======================================================================"
	@echo "Phase 3: Deploying applications via ArgoCD and testing endpoints"
	@echo "======================================================================"
	@echo "⏳ Waiting for ArgoCD to sync applications..."
	@for i in {1..12}; do \
		if kubectl get application frontend-dev -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q "Synced"; then \
			echo "✅ Frontend application synced"; \
			break; \
		fi; \
		echo "🔄 Waiting for frontend application to sync ($$i/12)..."; \
		sleep 5; \
	done
	@for i in {1..12}; do \
		if kubectl get application backend-dev -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q "Synced"; then \
			echo "✅ Backend application synced"; \
			break; \
		fi; \
		echo "🔄 Waiting for backend application to sync ($$i/12)..."; \
		sleep 5; \
	done
	@echo "⏳ Waiting for LoadBalancer services to get external IPs..."
	@for i in {1..15}; do \
		FRONTEND_URL=$$(kubectl get svc frontend-service -n frontend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
		BACKEND_URL=$$(kubectl get svc backend-service -n backend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
		if [ ! -z "$$FRONTEND_URL" ] && [ ! -z "$$BACKEND_URL" ]; then \
			echo "✅ LoadBalancer URLs are ready"; \
			break; \
		fi; \
		echo "🔄 Waiting for LoadBalancer IPs ($$i/15)..."; \
		sleep 5; \
	done
	@echo ""
	@echo "🧪 Testing all endpoints..."
	@FRONTEND_URL=$$(kubectl get svc frontend-service -n frontend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	BACKEND_URL=$$(kubectl get svc backend-service -n backend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	ARGOCD_URL=$$(cd $(TG_PATH) && $(TG_CMD) output -raw argocd_url 2>/dev/null | sed 's/http:\/\///'); \
	GRAFANA_URL=$$(cd $(TG_PATH) && $(TG_CMD) output -raw grafana_url 2>/dev/null | sed 's/http:\/\///'); \
	PROMETHEUS_URL=$$(cd $(TG_PATH) && $(TG_CMD) output -raw prometheus_url 2>/dev/null | sed 's/http:\/\///'); \
	JENKINS_URL=$$(cd $(TG_PATH) && $(TG_CMD) output -raw jenkins_url 2>/dev/null); \
	CONSUL_URL=$$(cd $(TG_PATH) && $(TG_CMD) output -raw consul_ui_url 2>/dev/null); \
	NEXUS_URL=$$(kubectl get svc nexus-terraform-nexus3 -n nexus-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	echo "Frontend ($$FRONTEND_URL):"; \
	if [ ! -z "$$FRONTEND_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" http://$$FRONTEND_URL --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi; \
	echo "Backend ($$BACKEND_URL):"; \
	if [ ! -z "$$BACKEND_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" http://$$BACKEND_URL/status --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi; \
	echo "ArgoCD ($$ARGOCD_URL):"; \
	if [ ! -z "$$ARGOCD_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" http://$$ARGOCD_URL --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi; \
	echo "Grafana ($$GRAFANA_URL):"; \
	if [ ! -z "$$GRAFANA_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" http://$$GRAFANA_URL --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi; \
	echo "Prometheus ($$PROMETHEUS_URL):"; \
	if [ ! -z "$$PROMETHEUS_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" http://$$PROMETHEUS_URL --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi; \
	echo "Jenkins ($$JENKINS_URL):"; \
	if [ ! -z "$$JENKINS_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" $$JENKINS_URL --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi; \
	echo "Consul ($$CONSUL_URL):"; \
	if [ ! -z "$$CONSUL_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" $$CONSUL_URL --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi; \
	echo "Nexus ($$NEXUS_URL):"; \
	if [ ! -z "$$NEXUS_URL" ]; then curl -s -o /dev/null -w "  Status: %{http_code}\n" http://$$NEXUS_URL:8081 --max-time 10 || echo "  Status: Connection failed"; else echo "  Status: URL not available"; fi
	@echo ""
	@echo "🎉 Complete Deployment Pipeline Finished!"
	@echo "=========================================="
	@echo ""
	@echo "🌐 Application URLs:"
	@FRONTEND_URL=$$(kubectl get svc frontend-service -n frontend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ ! -z "$$FRONTEND_URL" ]; then echo "- Frontend: http://$$FRONTEND_URL"; else echo "- Frontend: Not available yet"; fi
	@BACKEND_URL=$$(kubectl get svc backend-service -n backend-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ ! -z "$$BACKEND_URL" ]; then echo "- Backend:  http://$$BACKEND_URL"; else echo "- Backend: Not available yet"; fi
	@echo ""
	@echo "🔄 GitOps & CI/CD:"
	@cd $(TG_PATH) && $(TG_CMD) output -raw argocd_url 2>/dev/null | sed 's/^/- ArgoCD:    /' || echo "- ArgoCD: Not available"
	@cd $(TG_PATH) && $(TG_CMD) output -raw jenkins_url 2>/dev/null | sed 's/^/- Jenkins:   /' || echo "- Jenkins: Not available"
	@echo ""
	@echo "📊 Monitoring:"
	@cd $(TG_PATH) && $(TG_CMD) output -raw grafana_url 2>/dev/null | sed 's/^/- Grafana:   /' || echo "- Grafana: Not available"
	@cd $(TG_PATH) && $(TG_CMD) output -raw prometheus_url 2>/dev/null | sed 's/^/- Prometheus: /' || echo "- Prometheus: Not available"
	@echo ""
	@echo "🏗️ Infrastructure:"
	@cd $(TG_PATH) && $(TG_CMD) output -raw consul_ui_url 2>/dev/null | sed 's/^/- Consul UI: /' || echo "- Consul UI: Not available"
	@NEXUS_URL=$$(kubectl get svc nexus-terraform-nexus3 -n nexus-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ ! -z "$$NEXUS_URL" ]; then echo "- Nexus:     http://$$NEXUS_URL:8081"; else echo "- Nexus: Not available yet"; fi
	@echo "- EKS Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw eks_cluster_id 2>/dev/null || echo 'Not deployed')"
	@echo "- GKE Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw gke_cluster_name 2>/dev/null || echo 'Not deployed')"

apply-infra-only: ## Apply only Terraform infrastructure changes (no app rebuild)
	@echo "Applying Terraform changes for $(ENV)/$(REGION)..."
	@cd $(TG_PATH) && $(TG_CMD) init -reconfigure && $(TG_CMD) apply -auto-approve
	@echo ""
	@echo "🎉 Infrastructure Deployment Complete!"
	@echo "======================================"
	@echo ""
	@echo "📊 Infrastructure Details:"
	@echo "- EKS Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw eks_cluster_id 2>/dev/null || echo 'Not deployed')"
	@echo "- GKE Cluster: $$(cd $(TG_PATH) && $(TG_CMD) output -raw gke_cluster_name 2>/dev/null || echo 'Not deployed')"
	@echo "- Consul UI: $$(cd $(TG_PATH) && $(TG_CMD) output -raw consul_ui_url 2>/dev/null || echo 'Not available')"

apply-core-infra: ## Apply all cloud infrastructure (VPC, RDS, EKS, GKE) and ArgoCD
	@echo "🏗️  Applying core cloud infrastructure and ArgoCD"
	@cd $(TG_PATH) && $(TG_CMD) apply -auto-approve \
		-target=module.aws_vpc \
		-target=module.gcp_vpc \
		-target=module.aws_eks \
		-target=module.gcp_gke \
		-target=module.consul_primary \
		-target=module.aws_rds \
		-target=module.aws_ecr \
		-target=module.azure_vnet \
		-target=module.azure_aks \
		-target=module.azure_ansible_controller \
		-target=module.jenkins \
		-target=module.puppet_enterprise \
		-target=module.argocd \
		-target=random_password.consul_gossip_key \
		-target=random_password.consul_wan_federation_secret \
		-target=null_resource.wait_for_cluster

apply-infra-and-k8s: ## Two-stage apply: cloud infra first, then Kubernetes/Helm add-ons
	@echo "🚀 Phase 1 – core cloud infrastructure"
	@$(MAKE) apply-core-infra ENV=$(ENV) REGION=$(REGION) AWS_PROFILE=$(AWS_PROFILE)
	@echo "✅ Core infrastructure deployed"
	@echo "🚀 Phase 2 – Kubernetes & Helm add-ons"
	@cd $(TG_PATH) && $(TG_CMD) apply -auto-approve
	@echo "🎉 Full infrastructure + Kubernetes add-ons deployed"

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
	@cd .. && IMAGE_TAG=$$(date +%Y%m%d-%H%M%S) ./scripts/build-and-push.sh

deploy-apps: ## Deploy applications to Kubernetes (restart deployments)
	@echo "🚀 Deploying applications to Kubernetes..."
	@echo "Forcing fresh deployment with latest images..."
	@kubectl delete pod -l app=frontend -n frontend-dev
	@kubectl delete pod -l app=backend -n backend-dev
	@echo "Waiting for new pods to start..."
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

fix-loadbalancers: ## Fix load balancer connectivity issues
	@echo "🔧 Fixing Load Balancer Connectivity Issues"
	@echo "==========================================="
	@echo "📝 Detected issue: Load balancers cannot reach worker nodes"
	@echo "🛠️  Applying fix..."
	@echo ""
	@echo "Step 1: Delete and recreate all LoadBalancer services to reset them"
	@kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}' 2>/dev/null || echo "ArgoCD already NodePort"
	@kubectl patch svc prometheus-prometheus -n observability -p '{"spec":{"type":"NodePort"}}' 2>/dev/null || echo "Prometheus already NodePort"
	@kubectl patch svc prometheus-stack-grafana -n observability -p '{"spec":{"type":"NodePort"}}' 2>/dev/null || echo "Grafana already NodePort"
	@kubectl patch svc frontend-service -n frontend-dev -p '{"spec":{"type":"NodePort"}}' 2>/dev/null || echo "Frontend already NodePort"
	@kubectl patch svc backend-service -n backend-dev -p '{"spec":{"type":"NodePort"}}' 2>/dev/null || echo "Backend already NodePort"
	@echo "⏳ Waiting 10 seconds for old load balancers to terminate..."
	@sleep 10
	@echo ""
	@echo "Step 2: Recreate as LoadBalancer services"
	@kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || echo "ArgoCD LoadBalancer update failed"
	@kubectl patch svc prometheus-prometheus -n observability -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || echo "Prometheus LoadBalancer update failed"
	@kubectl patch svc prometheus-stack-grafana -n observability -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || echo "Grafana LoadBalancer update failed"
	@kubectl patch svc frontend-service -n frontend-dev -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || echo "Frontend LoadBalancer update failed"
	@kubectl patch svc backend-service -n backend-dev -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || echo "Backend LoadBalancer update failed"
	@echo ""
	@echo "⏳ Waiting 60 seconds for new load balancers to provision..."
	@sleep 60
	@echo ""
	@echo "🧪 Testing connectivity..."
	@make test-apps
	@echo ""
	@echo "✅ Load balancer fix completed!"
	@echo "📝 If issues persist, the problem may be with AWS security groups."
	@echo "💡 Try accessing via NodePort: kubectl get svc -A | grep NodePort"

configure-nexus: ## Configure Nexus repositories after deployment
	@echo "📦 Configuring Nexus Repository Manager"
	@echo "======================================"
	@cd .. && ./scripts/configure-nexus.sh
	@echo ""
	@echo "✅ Nexus configuration complete!"
	@echo "📝 Repository URLs available in Terraform outputs:"
	@echo "   make show-outputs | grep nexus"

nexus-status: ## Check Nexus deployment status
	@echo "📊 Nexus Repository Manager Status"
	@echo "=================================="
	@echo ""
	@echo "🚀 Pod Status:"
	@kubectl get pods -n nexus-$(ENV) -l app=nexus 2>/dev/null || echo "Nexus not deployed yet"
	@echo ""
	@echo "🔗 Service Status:"
	@kubectl get svc -n nexus-$(ENV) 2>/dev/null || echo "Nexus services not found"
	@echo ""
	@echo "📋 Repository Information:"
	@cd $(TG_PATH) && $(TG_CMD) output nexus_url 2>/dev/null || echo "Nexus outputs not available"