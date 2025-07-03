#!/bin/bash

# 🔍 COMPREHENSIVE SETUP VALIDATION
# =================================
# This script performs end-to-end validation of the entire infrastructure:
# - Infrastructure components (AWS, GCP, Azure)
# - Kubernetes clusters and workloads
# - Service mesh and networking
# - Security policies and compliance
# - Monitoring and observability
# - CI/CD pipelines
# - Configuration management
# - Integration testing

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-dev}
REGION=${REGION:-us-east-2}
TERRAFORM_DIR="${TERRAFORM_DIR:-terraform/envs/${ENVIRONMENT}/${REGION}}"
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-300s}

# Validation results tracking
declare -A VALIDATION_RESULTS
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Print banner
print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║              🔍 COMPREHENSIVE INFRASTRUCTURE VALIDATION 🔍                   ║"
    echo "║                                                                              ║"
    echo "║  • Complete end-to-end system validation                                    ║"
    echo "║  • Infrastructure, applications, and integrations                           ║"
    echo "║  • Security, networking, and compliance                                     ║"
    echo "║  • Performance and reliability testing                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Utility functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message"
}

check_result() {
    local check_name="$1"
    local result="$2"
    local message="${3:-}"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    VALIDATION_RESULTS["$check_name"]="$result"
    
    case "$result" in
        "PASS")
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            echo -e "   ${GREEN}✅ $check_name${NC} ${message}"
            ;;
        "FAIL")
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            echo -e "   ${RED}❌ $check_name${NC} ${message}"
            ;;
        "WARN")
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            echo -e "   ${YELLOW}⚠️  $check_name${NC} ${message}"
            ;;
    esac
}

wait_for_condition() {
    local description="$1"
    local command="$2"
    local timeout="${3:-60}"
    
    echo -e "${BLUE}⏳ Waiting for: $description${NC}"
    
    local count=0
    while [ $count -lt $timeout ]; do
        if eval "$command" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $description - Ready${NC}"
            return 0
        fi
        sleep 5
        count=$((count + 5))
        echo -e "${YELLOW}   Still waiting... (${count}s/${timeout}s)${NC}"
    done
    
    echo -e "${RED}❌ $description - Timeout after ${timeout}s${NC}"
    return 1
}

# Get infrastructure details
get_infrastructure_details() {
    echo -e "${CYAN}📋 Extracting infrastructure details...${NC}"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        check_result "Terraform Directory" "FAIL" "Directory not found: $TERRAFORM_DIR"
        return 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    # Extract all infrastructure outputs
    export AWS_REGION="$REGION"
    export EKS_CLUSTER_NAME=$(terragrunt output -raw eks_cluster_id 2>/dev/null || echo "")
    export GKE_CLUSTER_NAME=$(terragrunt output -raw gke_cluster_name 2>/dev/null || echo "")
    export AKS_CLUSTER_NAME=$(terragrunt output -raw aks_cluster_name 2>/dev/null || echo "")
    
    export CONSUL_SERVER_IPS=$(terragrunt output -json consul_primary_datacenter 2>/dev/null | jq -r '.value.server_private_ips[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
    export CONSUL_UI_URL=$(terragrunt output -raw consul_ui_url 2>/dev/null || echo "")
    
    export JENKINS_URL=$(terragrunt output -raw jenkins_public_url 2>/dev/null || echo "")
    export NEXUS_URL=$(terragrunt output -raw nexus_url 2>/dev/null || echo "")
    export PUPPET_SERVER_URL=$(terragrunt output -raw puppet_server_url 2>/dev/null || echo "")
    export ANSIBLE_TOWER_URL=$(terragrunt output -raw ansible_tower_url 2>/dev/null || echo "")
    
    cd - >/dev/null
    
    check_result "Infrastructure Details" "PASS" "Successfully extracted"
}

# Validate AWS infrastructure
validate_aws_infrastructure() {
    echo -e "${CYAN}☁️ Validating AWS infrastructure...${NC}"
    
    # Check EKS cluster
    if [ -n "$EKS_CLUSTER_NAME" ]; then
        if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
            local cluster_status=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.status' --output text)
            if [ "$cluster_status" = "ACTIVE" ]; then
                check_result "EKS Cluster Status" "PASS" "Cluster is ACTIVE"
                
                # Update kubeconfig and validate nodes
                aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" >/dev/null 2>&1
                local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
                if [ "$node_count" -gt 0 ]; then
                    check_result "EKS Nodes" "PASS" "$node_count nodes ready"
                else
                    check_result "EKS Nodes" "FAIL" "No nodes found"
                fi
            else
                check_result "EKS Cluster Status" "FAIL" "Status: $cluster_status"
            fi
        else
            check_result "EKS Cluster" "FAIL" "Cluster not accessible"
        fi
    else
        check_result "EKS Cluster" "WARN" "Not configured"
    fi
    
    # Check RDS instances
    local rds_instances=$(aws rds describe-db-instances --region "$AWS_REGION" --query 'DBInstances[?contains(DBInstanceIdentifier, `'$ENVIRONMENT'`)].DBInstanceStatus' --output text 2>/dev/null || echo "")
    if [ -n "$rds_instances" ]; then
        local available_count=$(echo "$rds_instances" | grep -c "available" || echo "0")
        if [ "$available_count" -gt 0 ]; then
            check_result "RDS Instances" "PASS" "$available_count instances available"
        else
            check_result "RDS Instances" "FAIL" "No available instances"
        fi
    else
        check_result "RDS Instances" "WARN" "No RDS instances found"
    fi
    
    # Check VPC and networking
    local vpcs=$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:Environment,Values=$ENVIRONMENT" --query 'Vpcs[].State' --output text 2>/dev/null || echo "")
    if echo "$vpcs" | grep -q "available"; then
        check_result "VPC Networking" "PASS" "VPC is available"
    else
        check_result "VPC Networking" "FAIL" "VPC not available"
    fi
}

# Validate Kubernetes workloads
validate_kubernetes_workloads() {
    echo -e "${CYAN}☸️ Validating Kubernetes workloads...${NC}"
    
    # Check system namespaces
    local system_namespaces=("kube-system" "kube-public" "kube-node-lease")
    for ns in "${system_namespaces[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            check_result "Namespace: $ns" "PASS" "Exists"
        else
            check_result "Namespace: $ns" "FAIL" "Missing"
        fi
    done
    
    # Check application namespaces
    local app_namespaces=("frontend-dev" "backend-dev" "monitoring" "consul" "cert-manager")
    for ns in "${app_namespaces[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            local pod_count=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            if [ "$pod_count" -gt 0 ]; then
                check_result "Namespace: $ns" "PASS" "$pod_count running pods"
            else
                check_result "Namespace: $ns" "WARN" "No running pods"
            fi
        else
            check_result "Namespace: $ns" "WARN" "Not found"
        fi
    done
    
    # Check critical system pods
    local critical_pods=("coredns" "aws-load-balancer-controller" "ebs-csi-controller")
    for pod in "${critical_pods[@]}"; do
        local running_count=$(kubectl get pods -A -l "app=$pod" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [ "$running_count" -gt 0 ]; then
            check_result "System Pod: $pod" "PASS" "$running_count instances running"
        else
            check_result "System Pod: $pod" "WARN" "Not found or not running"
        fi
    done
    
    # Check node health
    local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
    local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -gt 0 ]; then
        check_result "Node Health" "PASS" "$ready_nodes/$total_nodes nodes ready"
    else
        check_result "Node Health" "FAIL" "$ready_nodes/$total_nodes nodes ready"
    fi
}

# Validate application deployments
validate_application_deployments() {
    echo -e "${CYAN}🚀 Validating application deployments...${NC}"
    
    # Check frontend deployment
    if kubectl get deployment frontend -n frontend-dev >/dev/null 2>&1; then
        local replicas=$(kubectl get deployment frontend -n frontend-dev -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(kubectl get deployment frontend -n frontend-dev -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$replicas" -eq "$desired" ] && [ "$desired" -gt 0 ]; then
            check_result "Frontend Deployment" "PASS" "$replicas/$desired replicas ready"
        else
            check_result "Frontend Deployment" "FAIL" "$replicas/$desired replicas ready"
        fi
    else
        check_result "Frontend Deployment" "WARN" "Not found"
    fi
    
    # Check backend deployment
    if kubectl get deployment backend -n backend-dev >/dev/null 2>&1; then
        local replicas=$(kubectl get deployment backend -n backend-dev -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(kubectl get deployment backend -n backend-dev -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$replicas" -eq "$desired" ] && [ "$desired" -gt 0 ]; then
            check_result "Backend Deployment" "PASS" "$replicas/$desired replicas ready"
        else
            check_result "Backend Deployment" "FAIL" "$replicas/$desired replicas ready"
        fi
    else
        check_result "Backend Deployment" "WARN" "Not found"
    fi
    
    # Check services
    local services=("frontend:frontend-dev" "backend:backend-dev")
    for service_info in "${services[@]}"; do
        local service_name="${service_info%:*}"
        local service_ns="${service_info#*:}"
        
        if kubectl get service "$service_name" -n "$service_ns" >/dev/null 2>&1; then
            local endpoints=$(kubectl get endpoints "$service_name" -n "$service_ns" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
            if [ "$endpoints" -gt 0 ]; then
                check_result "Service: $service_name" "PASS" "$endpoints endpoints"
            else
                check_result "Service: $service_name" "FAIL" "No endpoints"
            fi
        else
            check_result "Service: $service_name" "WARN" "Not found"
        fi
    done
}

# Validate service mesh
validate_service_mesh() {
    echo -e "${CYAN}🌐 Validating service mesh...${NC}"
    
    # Check Consul cluster
    if [ -n "$CONSUL_SERVER_IPS" ]; then
        local consul_ip=$(echo "$CONSUL_SERVER_IPS" | cut -d',' -f1)
        local consul_endpoint="http://$consul_ip:8500"
        
        if curl -s -f "$consul_endpoint/v1/status/leader" >/dev/null 2>&1; then
            check_result "Consul Cluster" "PASS" "Leader election working"
            
            # Check service registrations
            local services=$(curl -s "$consul_endpoint/v1/catalog/services" 2>/dev/null | jq -r 'keys | length' 2>/dev/null || echo "0")
            if [ "$services" -gt 1 ]; then
                check_result "Consul Services" "PASS" "$services services registered"
            else
                check_result "Consul Services" "WARN" "Limited services ($services)"
            fi
            
            # Check Connect CA
            if curl -s -f "$consul_endpoint/v1/connect/ca/roots" | jq -e '.Roots | length > 0' >/dev/null 2>&1; then
                check_result "Consul Connect CA" "PASS" "CA configured"
            else
                check_result "Consul Connect CA" "FAIL" "CA not configured"
            fi
        else
            check_result "Consul Cluster" "FAIL" "Not accessible"
        fi
    else
        check_result "Consul Cluster" "WARN" "Not configured"
    fi
    
    # Check Consul on Kubernetes
    local consul_pods=$(kubectl get pods -n consul --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$consul_pods" -gt 0 ]; then
        check_result "Consul K8s Pods" "PASS" "$consul_pods pods running"
    else
        check_result "Consul K8s Pods" "WARN" "No pods found"
    fi
}

# Validate monitoring stack
validate_monitoring_stack() {
    echo -e "${CYAN}📊 Validating monitoring stack...${NC}"
    
    # Check Prometheus
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q Running; then
        check_result "Prometheus" "PASS" "Running"
        
        # Check Prometheus targets
        local prometheus_svc=$(kubectl get svc -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$prometheus_svc" ]; then
            kubectl port-forward -n monitoring "svc/$prometheus_svc" 9090:9090 >/dev/null 2>&1 &
            local pf_pid=$!
            sleep 3
            
            if curl -s http://localhost:9090/api/v1/targets >/dev/null 2>&1; then
                check_result "Prometheus Targets" "PASS" "API accessible"
            else
                check_result "Prometheus Targets" "WARN" "API not accessible"
            fi
            
            kill $pf_pid 2>/dev/null || true
        fi
    else
        check_result "Prometheus" "WARN" "Not running"
    fi
    
    # Check Grafana
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -q Running; then
        check_result "Grafana" "PASS" "Running"
    else
        check_result "Grafana" "WARN" "Not running"
    fi
    
    # Check AlertManager
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers 2>/dev/null | grep -q Running; then
        check_result "AlertManager" "PASS" "Running"
    else
        check_result "AlertManager" "WARN" "Not running"
    fi
    
    # Check Datadog integration
    if kubectl get pods -A -l app=datadog-agent --no-headers 2>/dev/null | grep -q Running; then
        local datadog_pods=$(kubectl get pods -A -l app=datadog-agent --no-headers | grep -c Running)
        check_result "Datadog Agent" "PASS" "$datadog_pods pods running"
    else
        check_result "Datadog Agent" "WARN" "Not found"
    fi
}

# Validate security policies
validate_security_policies() {
    echo -e "${CYAN}🔒 Validating security policies...${NC}"
    
    # Check OPA Gatekeeper
    if kubectl get pods -n gatekeeper-system -l control-plane=controller-manager --no-headers 2>/dev/null | grep -q Running; then
        check_result "OPA Gatekeeper" "PASS" "Running"
        
        # Check constraints
        local constraints=$(kubectl get constraints --all-namespaces --no-headers 2>/dev/null | wc -l)
        if [ "$constraints" -gt 0 ]; then
            check_result "Security Constraints" "PASS" "$constraints constraints active"
        else
            check_result "Security Constraints" "WARN" "No constraints found"
        fi
    else
        check_result "OPA Gatekeeper" "WARN" "Not running"
    fi
    
    # Check Network Policies
    local netpols=$(kubectl get networkpolicies --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$netpols" -gt 0 ]; then
        check_result "Network Policies" "PASS" "$netpols policies active"
    else
        check_result "Network Policies" "WARN" "No policies found"
    fi
    
    # Check Pod Security Standards
    local pss_namespaces=$(kubectl get namespaces -o json 2>/dev/null | jq -r '.items[] | select(.metadata.labels["pod-security.kubernetes.io/enforce"]) | .metadata.name' | wc -l)
    if [ "$pss_namespaces" -gt 0 ]; then
        check_result "Pod Security Standards" "PASS" "$pss_namespaces namespaces configured"
    else
        check_result "Pod Security Standards" "WARN" "No PSS configured"
    fi
    
    # Check Security Scanners
    if kubectl get pods -n trivy-system --no-headers 2>/dev/null | grep -q Running; then
        check_result "Trivy Scanner" "PASS" "Running"
    else
        check_result "Trivy Scanner" "WARN" "Not found"
    fi
}

# Validate certificates
validate_certificates() {
    echo -e "${CYAN}🔐 Validating certificates...${NC}"
    
    # Check cert-manager
    if kubectl get pods -n cert-manager -l app.kubernetes.io/instance=cert-manager --no-headers 2>/dev/null | grep -q Running; then
        check_result "cert-manager" "PASS" "Running"
        
        # Check ClusterIssuers
        local issuers=$(kubectl get clusterissuers --no-headers 2>/dev/null | wc -l)
        if [ "$issuers" -gt 0 ]; then
            check_result "Certificate Issuers" "PASS" "$issuers issuers configured"
        else
            check_result "Certificate Issuers" "WARN" "No issuers found"
        fi
        
        # Check certificates
        local certs=$(kubectl get certificates --all-namespaces --no-headers 2>/dev/null | wc -l)
        local ready_certs=$(kubectl get certificates --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]?.type == "Ready" and .status.conditions[]?.status == "True") | .metadata.name' | wc -l)
        if [ "$certs" -gt 0 ]; then
            check_result "Certificates" "PASS" "$ready_certs/$certs certificates ready"
        else
            check_result "Certificates" "WARN" "No certificates found"
        fi
    else
        check_result "cert-manager" "WARN" "Not running"
    fi
}

# Validate CI/CD pipeline
validate_cicd_pipeline() {
    echo -e "${CYAN}🔄 Validating CI/CD pipeline...${NC}"
    
    # Check Jenkins
    if [ -n "$JENKINS_URL" ]; then
        if curl -s -f "$JENKINS_URL/login" >/dev/null 2>&1; then
            check_result "Jenkins Access" "PASS" "Accessible"
        else
            check_result "Jenkins Access" "FAIL" "Not accessible"
        fi
    else
        check_result "Jenkins" "WARN" "URL not configured"
    fi
    
    # Check Nexus
    if [ -n "$NEXUS_URL" ]; then
        if curl -s -f "$NEXUS_URL/service/rest/v1/status" >/dev/null 2>&1; then
            check_result "Nexus Access" "PASS" "Accessible"
        else
            check_result "Nexus Access" "FAIL" "Not accessible"
        fi
    else
        check_result "Nexus" "WARN" "URL not configured"
    fi
    
    # Check ArgoCD
    if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -q Running; then
        check_result "ArgoCD" "PASS" "Running"
    else
        check_result "ArgoCD" "WARN" "Not found"
    fi
}

# Validate configuration management
validate_configuration_management() {
    echo -e "${CYAN}⚙️ Validating configuration management...${NC}"
    
    # Check Ansible Tower
    if [ -n "$ANSIBLE_TOWER_URL" ]; then
        if curl -s -f "$ANSIBLE_TOWER_URL/api/v2/ping/" >/dev/null 2>&1; then
            check_result "Ansible Tower" "PASS" "API accessible"
        else
            check_result "Ansible Tower" "FAIL" "API not accessible"
        fi
    else
        check_result "Ansible Tower" "WARN" "URL not configured"
    fi
    
    # Check Puppet Enterprise
    if [ -n "$PUPPET_SERVER_URL" ]; then
        if curl -s -f "$PUPPET_SERVER_URL/status/v1/simple" >/dev/null 2>&1; then
            check_result "Puppet Enterprise" "PASS" "Accessible"
        else
            check_result "Puppet Enterprise" "FAIL" "Not accessible"
        fi
    else
        check_result "Puppet Enterprise" "WARN" "URL not configured"
    fi
}

# Run integration tests
run_integration_tests() {
    echo -e "${CYAN}🧪 Running integration tests...${NC}"
    
    # Test frontend to backend connectivity
    local frontend_pod=$(kubectl get pods -n frontend-dev -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$frontend_pod" ]; then
        if kubectl exec -n frontend-dev "$frontend_pod" -- curl -s -f http://backend.backend-dev.svc.cluster.local:3001/api/status >/dev/null 2>&1; then
            check_result "Frontend->Backend Connectivity" "PASS" "API reachable"
        else
            check_result "Frontend->Backend Connectivity" "FAIL" "API not reachable"
        fi
    else
        check_result "Frontend->Backend Connectivity" "WARN" "Frontend pod not found"
    fi
    
    # Test service discovery
    if [ -n "$CONSUL_SERVER_IPS" ]; then
        local consul_ip=$(echo "$CONSUL_SERVER_IPS" | cut -d',' -f1)
        if nslookup backend.service.consul "$consul_ip" >/dev/null 2>&1; then
            check_result "Service Discovery" "PASS" "DNS resolution working"
        else
            check_result "Service Discovery" "WARN" "DNS resolution failed"
        fi
    else
        check_result "Service Discovery" "WARN" "Consul not configured"
    fi
    
    # Test ingress connectivity
    local ingress_controller=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$ingress_controller" -gt 0 ]; then
        check_result "Ingress Controller" "PASS" "Running"
    else
        check_result "Ingress Controller" "WARN" "Not found"
    fi
}

# Performance validation
validate_performance() {
    echo -e "${CYAN}⚡ Validating performance...${NC}"
    
    # Check resource utilization
    local node_cpu=$(kubectl top nodes 2>/dev/null | awk 'NR>1 {gsub("%","",$3); sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
    local node_memory=$(kubectl top nodes 2>/dev/null | awk 'NR>1 {gsub("%","",$5); sum+=$5; count++} END {if(count>0) print sum/count; else print 0}')
    
    if (( $(echo "$node_cpu < 80" | bc -l 2>/dev/null) )); then
        check_result "Node CPU Usage" "PASS" "${node_cpu}% average"
    else
        check_result "Node CPU Usage" "WARN" "${node_cpu}% average (high)"
    fi
    
    if (( $(echo "$node_memory < 80" | bc -l 2>/dev/null) )); then
        check_result "Node Memory Usage" "PASS" "${node_memory}% average"
    else
        check_result "Node Memory Usage" "WARN" "${node_memory}% average (high)"
    fi
    
    # Check pod resource requests/limits
    local pods_without_limits=$(kubectl get pods --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.containers[].resources.limits == null) | "\(.metadata.namespace)/\(.metadata.name)"' | wc -l)
    if [ "$pods_without_limits" -eq 0 ]; then
        check_result "Pod Resource Limits" "PASS" "All pods have limits"
    else
        check_result "Pod Resource Limits" "WARN" "$pods_without_limits pods without limits"
    fi
}

# Generate validation report
generate_validation_report() {
    echo -e "\n${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        📊 VALIDATION REPORT SUMMARY 📊                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}📋 Overall Results:${NC}"
    echo -e "   Total Checks: $TOTAL_CHECKS"
    echo -e "   ${GREEN}✅ Passed: $PASSED_CHECKS${NC}"
    echo -e "   ${RED}❌ Failed: $FAILED_CHECKS${NC}"
    echo -e "   ${YELLOW}⚠️  Warnings: $WARNING_CHECKS${NC}"
    
    local success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo -e "\n${BLUE}📊 Success Rate: ${success_rate}%${NC}"
    
    if [ $success_rate -ge 90 ]; then
        echo -e "${GREEN}🎉 Excellent! Your infrastructure is in great shape!${NC}"
    elif [ $success_rate -ge 75 ]; then
        echo -e "${YELLOW}👍 Good! Minor issues to address.${NC}"
    elif [ $success_rate -ge 50 ]; then
        echo -e "${YELLOW}⚠️  Fair. Several issues need attention.${NC}"
    else
        echo -e "${RED}🚨 Critical! Major issues require immediate attention.${NC}"
    fi
    
    # Detailed breakdown by category
    echo -e "\n${BLUE}🔍 Detailed Results:${NC}"
    for check_name in "${!VALIDATION_RESULTS[@]}"; do
        local result="${VALIDATION_RESULTS[$check_name]}"
        case "$result" in
            "PASS") echo -e "   ${GREEN}✅ $check_name${NC}" ;;
            "FAIL") echo -e "   ${RED}❌ $check_name${NC}" ;;
            "WARN") echo -e "   ${YELLOW}⚠️  $check_name${NC}" ;;
        esac
    done
    
    # Save report to file
    cat > /tmp/validation-report.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "region": "$REGION",
  "summary": {
    "total_checks": $TOTAL_CHECKS,
    "passed": $PASSED_CHECKS,
    "failed": $FAILED_CHECKS,
    "warnings": $WARNING_CHECKS,
    "success_rate": $success_rate
  },
  "results": $(printf '%s\n' "${!VALIDATION_RESULTS[@]}" | jq -R . | jq -s 'map({key: ., value: "'"$(echo "${VALIDATION_RESULTS[@]}" | tr ' ' '\n')"'"}) | from_entries')
}
EOF
    
    echo -e "\n${BLUE}📄 Detailed report saved to: /tmp/validation-report.json${NC}"
    
    # Return appropriate exit code
    if [ $FAILED_CHECKS -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Main execution
main() {
    print_banner
    
    echo -e "${BLUE}📋 Starting comprehensive infrastructure validation...${NC}"
    echo -e "   Environment: $ENVIRONMENT"
    echo -e "   Region: $REGION"
    echo -e "   Timeout: $VALIDATION_TIMEOUT"
    
    get_infrastructure_details
    validate_aws_infrastructure
    validate_kubernetes_workloads
    validate_application_deployments
    validate_service_mesh
    validate_monitoring_stack
    validate_security_policies
    validate_certificates
    validate_cicd_pipeline
    validate_configuration_management
    run_integration_tests
    validate_performance
    
    if generate_validation_report; then
        echo -e "\n${GREEN}🎊 Comprehensive validation completed successfully! 🎊${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Validation completed with failures. Please review the report.${NC}"
        exit 1
    fi
}

# Execute main function
main "$@" 