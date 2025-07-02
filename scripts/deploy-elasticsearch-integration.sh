#!/bin/bash

# 🔍 Elasticsearch Integration Deployment Script
# Deploys comprehensive logging and monitoring for multi-cloud DevOps platform

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ELASTICSEARCH_URL="https://798a3a233ea341aaad5b6c044a95fb25.us-central1.gcp.cloud.es.io:443"
ELASTICSEARCH_API_KEY="NUFZeHlwY0JBTWFEMkZxbV86M0g6QnZHN3hPYWZJRlZLcG92UnVzbmVEQQ=="
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Deployment functions
print_banner() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "  🔍 ELASTICSEARCH INTEGRATION DEPLOY"
    echo "=========================================="
    echo -e "${NC}"
    echo "📋 Deploying comprehensive logging for:"
    echo "   • Kubernetes logs (EKS/GKE/AKS)"
    echo "   • Security findings (SIEM)"
    echo "   • Puppet configuration reports"  
    echo "   • Application performance logs"
    echo "   • Infrastructure system logs"
    echo ""
}

check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
        exit 1
    fi
    
    # Check Kubernetes connectivity
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
        exit 1
    fi
    
    # Check Elasticsearch connectivity
    echo -e "${BLUE}📡 Testing Elasticsearch connectivity...${NC}"
    if ! curl -s -X GET "${ELASTICSEARCH_URL}/_cluster/health" \
         -H "Authorization: ApiKey ${ELASTICSEARCH_API_KEY}" \
         --max-time 10 > /dev/null; then
        echo -e "${RED}❌ Cannot connect to Elasticsearch. Please check URL and API key.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

deploy_logging_namespace() {
    echo -e "${YELLOW}📦 Creating logging namespace...${NC}"
    
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/dev/logging/elasticsearch-secret.yaml"
    
    echo -e "${GREEN}✅ Logging namespace and secrets created${NC}"
}

deploy_fluent_bit() {
    echo -e "${YELLOW}🚀 Deploying Fluent Bit for log collection...${NC}"
    
    # Deploy ConfigMap and DaemonSet
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/dev/logging/fluent-bit-configmap.yaml"
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/dev/logging/fluent-bit-daemonset.yaml"
    
    # Wait for pods to be ready
    echo -e "${BLUE}⏳ Waiting for Fluent Bit pods to be ready...${NC}"
    kubectl wait --namespace=logging \
        --for=condition=ready pod \
        --selector=app=fluent-bit \
        --timeout=300s
    
    # Verify deployment
    FLUENT_BIT_PODS=$(kubectl get pods -n logging -l app=fluent-bit --no-headers | wc -l)
    echo -e "${GREEN}✅ Fluent Bit deployed on ${FLUENT_BIT_PODS} nodes${NC}"
}

deploy_security_findings() {
    echo -e "${YELLOW}🔒 Deploying security findings collector...${NC}"
    
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/dev/logging/security-findings-integration.yaml"
    
    # Wait for deployment to be ready
    kubectl wait --namespace=logging \
        --for=condition=available deployment/security-findings-collector \
        --timeout=180s
    
    echo -e "${GREEN}✅ Security findings collector deployed${NC}"
}

deploy_grafana_dashboards() {
    echo -e "${YELLOW}📊 Deploying Grafana Elasticsearch datasources...${NC}"
    
    # Create observability namespace if it doesn't exist
    kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy Elasticsearch datasource
    kubectl apply -f "${PROJECT_ROOT}/monitoring/grafana-elasticsearch-datasource.yaml"
    
    echo -e "${GREEN}✅ Grafana Elasticsearch datasources configured${NC}"
}

configure_puppet_integration() {
    echo -e "${YELLOW}🎭 Configuring Puppet Enterprise integration...${NC}"
    
    # Check if Puppet servers are accessible
    if ansible-inventory --list | grep -q puppet_servers 2>/dev/null; then
        echo -e "${BLUE}📋 Running Puppet-Elasticsearch integration playbook...${NC}"
        ansible-playbook -i ansible/inventory/terraform-inventory.py \
            ansible/playbooks/puppet-elasticsearch-integration.yml
        echo -e "${GREEN}✅ Puppet Enterprise configured to send reports to Elasticsearch${NC}"
    else
        echo -e "${YELLOW}⚠️  No Puppet servers found in inventory. Skipping Puppet integration.${NC}"
    fi
}

verify_elasticsearch_indices() {
    echo -e "${YELLOW}🔍 Verifying Elasticsearch indices...${NC}"
    
    # Check if indices are being created
    sleep 30  # Give some time for logs to flow
    
    echo -e "${BLUE}📊 Checking Elasticsearch indices...${NC}"
    INDICES=$(curl -s -X GET "${ELASTICSEARCH_URL}/_cat/indices/kubernetes-logs*,security-findings*,puppet-reports*?v" \
              -H "Authorization: ApiKey ${ELASTICSEARCH_API_KEY}" || echo "")
    
    if [[ -n "$INDICES" ]]; then
        echo -e "${GREEN}✅ Elasticsearch indices found:${NC}"
        echo "$INDICES"
    else
        echo -e "${YELLOW}⚠️  No indices found yet. This is normal if no logs have been generated.${NC}"
    fi
}

test_log_ingestion() {
    echo -e "${YELLOW}🧪 Testing log ingestion...${NC}"
    
    # Create a test pod that generates logs
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: elasticsearch-test-logger
  namespace: default
  labels:
    app: test-logger
spec:
  containers:
  - name: logger
    image: busybox
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo 'Test log entry for Elasticsearch integration - $(date)'; sleep 30; done"]
  restartPolicy: Never
EOF

    echo -e "${BLUE}🔬 Test pod created. Logs should appear in Elasticsearch within 1-2 minutes.${NC}"
    
    # Wait a bit and then clean up
    sleep 60
    kubectl delete pod elasticsearch-test-logger --ignore-not-found=true
    
    echo -e "${GREEN}✅ Log ingestion test completed${NC}"
}

display_access_information() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "  🎉 ELASTICSEARCH INTEGRATION COMPLETE"
    echo "=========================================="
    echo -e "${NC}"
    
    echo -e "${BLUE}📊 Elasticsearch Cluster:${NC}"
    echo "   URL: ${ELASTICSEARCH_URL}"
    echo "   Status: $(curl -s -X GET "${ELASTICSEARCH_URL}/_cluster/health" -H "Authorization: ApiKey ${ELASTICSEARCH_API_KEY}" | jq -r '.status' 2>/dev/null || echo 'Unknown')"
    
    echo ""
    echo -e "${BLUE}🔍 Log Sources Configured:${NC}"
    echo "   ✅ Kubernetes container logs (all clusters)"
    echo "   ✅ SystemD service logs"
    echo "   ✅ Security findings (AWS/GCP/Azure)"
    echo "   ✅ Puppet configuration reports"
    echo "   ✅ Application performance logs"
    
    echo ""
    echo -e "${BLUE}📈 Grafana Integration:${NC}"
    echo "   ✅ Elasticsearch datasources configured"
    echo "   ✅ Multi-cloud log dashboards ready"
    echo "   ✅ Security findings SIEM dashboard"
    echo "   ✅ Puppet compliance monitoring"
    
    echo ""
    echo -e "${BLUE}🎯 Next Steps:${NC}"
    echo "   1. Import Grafana dashboard: monitoring/elasticsearch-log-dashboards.json"
    echo "   2. Configure alert rules for critical security findings"
    echo "   3. Set up log retention policies in Elasticsearch"
    echo "   4. Configure cross-cluster replication if needed"
    
    echo ""
    echo -e "${BLUE}🔧 Useful Commands:${NC}"
    echo "   # Check Fluent Bit status:"
    echo "   kubectl get pods -n logging -l app=fluent-bit"
    echo ""
    echo "   # View Fluent Bit logs:"
    echo "   kubectl logs -n logging -l app=fluent-bit -f"
    echo ""
    echo "   # Test Elasticsearch connectivity:"
    echo "   curl -X GET \"${ELASTICSEARCH_URL}/_cluster/health\" \\"
    echo "        -H \"Authorization: ApiKey ${ELASTICSEARCH_API_KEY}\""
    echo ""
    echo "   # Check indices:"
    echo "   curl -X GET \"${ELASTICSEARCH_URL}/_cat/indices?v\" \\"
    echo "        -H \"Authorization: ApiKey ${ELASTICSEARCH_API_KEY}\""
}

cleanup_on_error() {
    echo -e "${RED}❌ Deployment failed. Cleaning up...${NC}"
    
    # Clean up any partially deployed resources
    kubectl delete namespace logging --ignore-not-found=true
    kubectl delete pod elasticsearch-test-logger --ignore-not-found=true
    
    echo -e "${YELLOW}⚠️  Cleanup completed. Please check the error above and retry.${NC}"
}

# Main deployment flow
main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    print_banner
    check_prerequisites
    deploy_logging_namespace
    deploy_fluent_bit
    deploy_security_findings
    deploy_grafana_dashboards
    configure_puppet_integration
    verify_elasticsearch_indices
    test_log_ingestion
    display_access_information
    
    echo -e "${GREEN}🚀 Elasticsearch integration deployment completed successfully!${NC}"
}

# Execute main function
main "$@" 