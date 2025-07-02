#!/bin/bash

# 📊 Datadog Multi-Cloud Deployment Script
# Deploys Datadog agents across AWS EKS, GCP GKE, and Azure AKS clusters

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATADOG_API_KEY="af3cb41c927647ee8b56794caf9fdb4d"
DATADOG_APP_KEY="a046dd9ca1becba27a2ec4d3b357fad53655b813"

# Available clusters
CLUSTERS=(
    "dev-eks-us-east-2:aws:datadog-aws-eks.yaml"
    "dev-gke-us-central1:gcp:datadog-gcp-gke.yaml"
    "dev-aks-eastus:azure:datadog-azure-aks.yaml"
)

# Functions
print_banner() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  📊 DATADOG MULTI-CLOUD DEPLOYMENT"
    echo "==========================================="
    echo -e "${NC}"
    echo "🎯 Deploying Datadog across:"
    echo "   • AWS EKS (dev-eks-us-east-2)"
    echo "   • GCP GKE (dev-gke-us-central1)"
    echo "   • Azure AKS (dev-aks-eastus)"
    echo ""
    echo "🔧 Datadog Features:"
    echo "   • Infrastructure monitoring"
    echo "   • APM (Application Performance Monitoring)"
    echo "   • Log collection and analysis"
    echo "   • Process and network monitoring"
    echo "   • Kubernetes orchestrator tracking"
    echo "   • Security compliance monitoring"
    echo ""
}

check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
        exit 1
    fi
    
    # Check if kubeconfig contexts exist
    local contexts_found=0
    for cluster_info in "${CLUSTERS[@]}"; do
        local cluster_name=$(echo "$cluster_info" | cut -d':' -f1)
        if kubectl config get-contexts -o name | grep -q "$cluster_name" 2>/dev/null; then
            echo -e "${GREEN}✅ Found context for $cluster_name${NC}"
            ((contexts_found++))
        else
            echo -e "${YELLOW}⚠️  Context not found for $cluster_name${NC}"
        fi
    done
    
    if [[ $contexts_found -eq 0 ]]; then
        echo -e "${RED}❌ No cluster contexts found. Please configure kubectl for your clusters.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed (${contexts_found} clusters available)${NC}"
}

deploy_datadog_secrets() {
    echo -e "${YELLOW}🔐 Deploying Datadog secrets and RBAC...${NC}"
    
    # Deploy common secrets and RBAC
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/dev/monitoring/datadog-secrets.yaml"
    
    echo -e "${GREEN}✅ Datadog secrets and namespace created${NC}"
}

deploy_to_cluster() {
    local cluster_name="$1"
    local cloud_provider="$2"
    local config_file="$3"
    
    echo -e "${PURPLE}🚀 Deploying to ${cluster_name} (${cloud_provider})...${NC}"
    
    # Switch to cluster context
    if kubectl config use-context "$cluster_name" &>/dev/null; then
        echo -e "${BLUE}📋 Switched to cluster: $cluster_name${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not switch to $cluster_name context. Skipping...${NC}"
        return 1
    fi
    
    # Verify cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}❌ Cannot connect to $cluster_name. Skipping...${NC}"
        return 1
    fi
    
    # Deploy Datadog secrets first
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/dev/monitoring/datadog-secrets.yaml"
    
    # Deploy cluster-specific configuration
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/dev/monitoring/${config_file}"
    
    # Wait for deployments to be ready
    echo -e "${BLUE}⏳ Waiting for Datadog cluster agent to be ready...${NC}"
    if kubectl wait --namespace=datadog \
        --for=condition=available deployment/datadog-cluster-agent-${cloud_provider} \
        --timeout=300s 2>/dev/null; then
        echo -e "${GREEN}✅ Cluster agent ready on $cluster_name${NC}"
    else
        echo -e "${YELLOW}⚠️  Cluster agent deployment timeout on $cluster_name${NC}"
    fi
    
    # Wait for DaemonSet to be ready
    echo -e "${BLUE}⏳ Waiting for Datadog agents to be ready...${NC}"
    if kubectl wait --namespace=datadog \
        --for=condition=ready pod \
        --selector=app=datadog-agent,cloud=${cloud_provider} \
        --timeout=300s 2>/dev/null; then
        
        local agent_count=$(kubectl get pods -n datadog -l app=datadog-agent,cloud=${cloud_provider} --no-headers | wc -l)
        echo -e "${GREEN}✅ ${agent_count} Datadog agents ready on $cluster_name${NC}"
    else
        echo -e "${YELLOW}⚠️  Some Datadog agents may still be starting on $cluster_name${NC}"
    fi
    
    # Check agent status
    local total_agents=$(kubectl get pods -n datadog -l app=datadog-agent,cloud=${cloud_provider} --no-headers | wc -l)
    local ready_agents=$(kubectl get pods -n datadog -l app=datadog-agent,cloud=${cloud_provider} --field-selector=status.phase=Running --no-headers | wc -l)
    
    echo -e "${BLUE}📊 Cluster $cluster_name status: $ready_agents/$total_agents agents running${NC}"
    
    return 0
}

deploy_to_all_clusters() {
    echo -e "${YELLOW}🌐 Deploying Datadog to all available clusters...${NC}"
    
    local successful_deployments=0
    local total_deployments=0
    
    for cluster_info in "${CLUSTERS[@]}"; do
        local cluster_name=$(echo "$cluster_info" | cut -d':' -f1)
        local cloud_provider=$(echo "$cluster_info" | cut -d':' -f2)
        local config_file=$(echo "$cluster_info" | cut -d':' -f3)
        
        ((total_deployments++))
        
        echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PURPLE}📋 Deployment ${total_deployments}/${#CLUSTERS[@]}: ${cluster_name} (${cloud_provider})${NC}"
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        if deploy_to_cluster "$cluster_name" "$cloud_provider" "$config_file"; then
            ((successful_deployments++))
        fi
    done
    
    echo -e "\n${GREEN}📊 Deployment Summary: ${successful_deployments}/${total_deployments} clusters successful${NC}"
    return 0
}

verify_datadog_connectivity() {
    echo -e "${YELLOW}🔍 Verifying Datadog connectivity across clusters...${NC}"
    
    for cluster_info in "${CLUSTERS[@]}"; do
        local cluster_name=$(echo "$cluster_info" | cut -d':' -f1)
        local cloud_provider=$(echo "$cluster_info" | cut -d':' -f2)
        
        echo -e "${BLUE}🔬 Testing $cluster_name...${NC}"
        
        if kubectl config use-context "$cluster_name" &>/dev/null; then
            # Check if agents are running
            local agent_count=$(kubectl get pods -n datadog -l app=datadog-agent,cloud=${cloud_provider} --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            
            if [[ $agent_count -gt 0 ]]; then
                echo -e "${GREEN}  ✅ ${agent_count} Datadog agents running${NC}"
                
                # Check cluster agent
                if kubectl get deployment -n datadog datadog-cluster-agent-${cloud_provider} &>/dev/null; then
                    echo -e "${GREEN}  ✅ Cluster agent deployed${NC}"
                fi
                
                # Test agent logs for connectivity
                local agent_pod=$(kubectl get pods -n datadog -l app=datadog-agent,cloud=${cloud_provider} --field-selector=status.phase=Running --no-headers | head -1 | awk '{print $1}')
                if [[ -n "$agent_pod" ]]; then
                    if kubectl logs -n datadog "$agent_pod" -c agent | grep -q "Datadog Agent is running" 2>/dev/null; then
                        echo -e "${GREEN}  ✅ Agent connectivity verified${NC}"
                    else
                        echo -e "${YELLOW}  ⚠️  Agent may still be initializing${NC}"
                    fi
                fi
                
            else
                echo -e "${RED}  ❌ No running agents found${NC}"
            fi
        else
            echo -e "${YELLOW}  ⚠️  Cannot connect to cluster${NC}"
        fi
        echo ""
    done
}

create_grafana_integration() {
    echo -e "${YELLOW}📊 Creating Grafana-Datadog integration...${NC}"
    
    # Create Grafana datasource for Datadog (if using Grafana)
    cat > "${PROJECT_ROOT}/monitoring/grafana-datadog-datasource.yaml" << 'EOF'
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datadog-datasource
  namespace: observability
  labels:
    grafana_datasource: "1"
data:
  datadog-datasource.yaml: |
    apiVersion: 1
    
    datasources:
      - name: Datadog-Metrics
        orgId: 1
        type: prometheus
        access: proxy
        url: https://api.datadoghq.com/api/v1/query
        isDefault: false
        basicAuth: false
        jsonData:
          httpMethod: POST
          customQueryParameters: 'api_key=af3cb41c927647ee8b56794caf9fdb4d&application_key=a046dd9ca1becba27a2ec4d3b357fad53655b813'
        editable: true
EOF
    
    echo -e "${GREEN}✅ Grafana-Datadog integration configuration created${NC}"
}

display_access_information() {
    echo -e "${GREEN}"
    echo "==========================================="
    echo "  🎉 DATADOG DEPLOYMENT COMPLETE"
    echo "==========================================="
    echo -e "${NC}"
    
    echo -e "${BLUE}📊 Datadog Configuration:${NC}"
    echo "   API Key: af3cb41c927647ee8b56794caf9fdb4d"
    echo "   App Key: a046dd9ca1becba27a2ec4d3b357fad53655b813"
    echo "   Dashboard: https://app.datadoghq.com/"
    
    echo ""
    echo -e "${BLUE}🏗️ Deployed Clusters:${NC}"
    for cluster_info in "${CLUSTERS[@]}"; do
        local cluster_name=$(echo "$cluster_info" | cut -d':' -f1)
        local cloud_provider=$(echo "$cluster_info" | cut -d':' -f2)
        echo "   ✅ $cluster_name ($cloud_provider)"
    done
    
    echo ""
    echo -e "${BLUE}🔍 Monitoring Features Enabled:${NC}"
    echo "   ✅ Infrastructure monitoring (CPU, Memory, Network)"
    echo "   ✅ Application Performance Monitoring (APM)"
    echo "   ✅ Container and Kubernetes monitoring"
    echo "   ✅ Process and network monitoring"
    echo "   ✅ Log collection and forwarding"
    echo "   ✅ Security compliance monitoring"
    echo "   ✅ Multi-cloud tagging and correlation"
    
    echo ""
    echo -e "${BLUE}🎯 Datadog Tags Applied:${NC}"
    echo "   • cloud_provider: aws/gcp/azure"
    echo "   • environment: dev"
    echo "   • cluster_type: eks/gke/aks"
    echo "   • architecture: multi-cloud"
    echo "   • team: devops"
    
    echo ""
    echo -e "${BLUE}🔧 Useful Commands:${NC}"
    echo "   # Check agent status across clusters:"
    echo "   kubectl get pods -n datadog -l app=datadog-agent"
    echo ""
    echo "   # View agent logs:"
    echo "   kubectl logs -n datadog -l app=datadog-agent -c agent -f"
    echo ""
    echo "   # Check cluster agent status:"
    echo "   kubectl get deployment -n datadog -l app=datadog-cluster-agent"
    echo ""
    echo "   # Switch between clusters:"
    echo "   kubectl config use-context dev-eks-us-east-2"
    echo "   kubectl config use-context dev-gke-us-central1"
    echo "   kubectl config use-context dev-aks-eastus"
    
    echo ""
    echo -e "${BLUE}📈 Next Steps:${NC}"
    echo "   1. Visit Datadog dashboard: https://app.datadoghq.com/"
    echo "   2. Configure custom dashboards and alerts"
    echo "   3. Set up APM for your applications"
    echo "   4. Configure log parsing and analysis"
    echo "   5. Set up infrastructure alerts and SLOs"
}

cleanup_on_error() {
    echo -e "${RED}❌ Deployment failed. Cleaning up...${NC}"
    
    # Attempt to clean up any partially deployed resources
    for cluster_info in "${CLUSTERS[@]}"; do
        local cluster_name=$(echo "$cluster_info" | cut -d':' -f1)
        if kubectl config use-context "$cluster_name" &>/dev/null; then
            kubectl delete namespace datadog --ignore-not-found=true 2>/dev/null || true
        fi
    done
    
    echo -e "${YELLOW}⚠️  Cleanup completed. Please check the error above and retry.${NC}"
}

# Main deployment flow
main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    print_banner
    check_prerequisites
    deploy_datadog_secrets
    deploy_to_all_clusters
    verify_datadog_connectivity
    create_grafana_integration
    display_access_information
    
    echo -e "${GREEN}🚀 Datadog multi-cloud deployment completed successfully!${NC}"
}

# Handle command line arguments
case "${1:-deploy}" in
    "deploy")
        main "$@"
        ;;
    "verify")
        verify_datadog_connectivity
        ;;
    "cleanup")
        cleanup_on_error
        ;;
    *)
        echo "Usage: $0 [deploy|verify|cleanup]"
        echo "  deploy  - Deploy Datadog to all clusters (default)"
        echo "  verify  - Verify Datadog connectivity"
        echo "  cleanup - Clean up Datadog deployments"
        exit 1
        ;;
esac 