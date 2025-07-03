#!/bin/bash

# 🔐 COMPREHENSIVE SSL/TLS CERTIFICATE MANAGEMENT
# ==============================================
# This script configures complete certificate management including:
# - cert-manager for automated certificate provisioning
# - Let's Encrypt integration for public certificates
# - Custom CA for internal services
# - Certificate rotation and monitoring

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-dev}
REGION=${REGION:-us-east-2}
DOMAIN=${DOMAIN:-example.com}
EMAIL=${EMAIL:-admin@example.com}

# Print banner
print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║              🔐 COMPREHENSIVE SSL/TLS CERTIFICATE SETUP 🔐                  ║"
    echo "║                                                                              ║"
    echo "║  • cert-manager for automated provisioning                                  ║"
    echo "║  • Let's Encrypt for public certificates                                    ║"
    echo "║  • Custom CA for internal services                                          ║"
    echo "║  • Certificate monitoring and rotation                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Install cert-manager
install_cert_manager() {
    echo -e "${BLUE}📜 Installing cert-manager...${NC}"
    
    # Create cert-manager namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Add cert-manager Helm repository
    helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    
    # Install cert-manager
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.13.2 \
        --set installCRDs=true \
        --set webhook.timeoutSeconds=4 \
        --wait --timeout=600s
    
    # Wait for cert-manager to be ready
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=300s
    
    echo -e "${GREEN}✅ cert-manager installed${NC}"
}

# Configure Let's Encrypt ClusterIssuers
configure_letsencrypt_issuers() {
    echo -e "${BLUE}🌐 Configuring Let's Encrypt certificate issuers...${NC}"
    
    # Let's Encrypt staging issuer
    kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
    - dns01:
        route53:
          region: $REGION
          hostedZoneID: HOSTED_ZONE_ID  # Replace with actual hosted zone ID
          role: arn:aws:iam::ACCOUNT_ID:role/cert-manager-route53-role
EOF

    # Let's Encrypt production issuer
    kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
    - dns01:
        route53:
          region: $REGION
          hostedZoneID: HOSTED_ZONE_ID  # Replace with actual hosted zone ID
          role: arn:aws:iam::ACCOUNT_ID:role/cert-manager-route53-role
EOF

    echo -e "${GREEN}✅ Let's Encrypt issuers configured${NC}"
}

# Create custom CA for internal services
create_custom_ca() {
    echo -e "${BLUE}🏛️ Creating custom CA for internal services...${NC}"
    
    # Create CA private key
    openssl genrsa -out /tmp/ca-key.pem 4096
    
    # Create CA certificate
    openssl req -new -x509 -sha256 -key /tmp/ca-key.pem -out /tmp/ca-cert.pem -days 3650 \
        -subj "/C=US/ST=CA/L=San Francisco/O=Internal CA/CN=Internal Root CA"
    
    # Create CA secret in Kubernetes
    kubectl create secret tls internal-ca-secret \
        --cert=/tmp/ca-cert.pem \
        --key=/tmp/ca-key.pem \
        --namespace=cert-manager \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create internal CA issuer
    kubectl apply -f - << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca-issuer
spec:
  ca:
    secretName: internal-ca-secret
EOF

    # Cleanup temporary files
    rm -f /tmp/ca-key.pem /tmp/ca-cert.pem
    
    echo -e "${GREEN}✅ Custom CA created${NC}"
}

# Configure certificates for applications
configure_application_certificates() {
    echo -e "${BLUE}🚀 Configuring application certificates...${NC}"
    
    # Frontend certificate (public)
    kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: frontend-tls
  namespace: frontend-dev
spec:
  secretName: frontend-tls-secret
  dnsNames:
  - frontend.$DOMAIN
  - www.frontend.$DOMAIN
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

    # Backend certificate (internal)
    kubectl apply -f - << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: backend-tls
  namespace: backend-dev
spec:
  secretName: backend-tls-secret
  dnsNames:
  - backend.internal
  - backend.backend-dev.svc.cluster.local
  - api.internal
  issuerRef:
    name: internal-ca-issuer
    kind: ClusterIssuer
  usages:
  - digital signature
  - key encipherment
  - server auth
  - client auth
EOF

    # Consul certificates for service mesh
    kubectl apply -f - << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: consul-server-tls
  namespace: consul
spec:
  secretName: consul-server-tls-secret
  dnsNames:
  - consul-server
  - consul-server.consul.svc.cluster.local
  - "*.consul-server.consul.svc.cluster.local"
  - consul.service.consul
  - server.aws-dev-us-east-2.consul
  ipAddresses:
  - 127.0.0.1
  issuerRef:
    name: internal-ca-issuer
    kind: ClusterIssuer
  usages:
  - digital signature
  - key encipherment
  - server auth
  - client auth
EOF

    # Jenkins certificate
    kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: jenkins-tls
  namespace: ci-cd
spec:
  secretName: jenkins-tls-secret
  dnsNames:
  - jenkins.$DOMAIN
  - ci.$DOMAIN
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

    # Nexus certificate
    kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nexus-tls
  namespace: ci-cd
spec:
  secretName: nexus-tls-secret
  dnsNames:
  - nexus.$DOMAIN
  - artifacts.$DOMAIN
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

    # Monitoring certificates
    kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: prometheus-tls
  namespace: monitoring
spec:
  secretName: prometheus-tls-secret
  dnsNames:
  - prometheus.$DOMAIN
  - metrics.$DOMAIN
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  usages:
  - digital signature
  - key encipherment
  - server auth
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: grafana-tls
  namespace: monitoring
spec:
  secretName: grafana-tls-secret
  dnsNames:
  - grafana.$DOMAIN
  - dashboards.$DOMAIN
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

    echo -e "${GREEN}✅ Application certificates configured${NC}"
}

# Configure certificate monitoring
configure_certificate_monitoring() {
    echo -e "${BLUE}📊 Configuring certificate monitoring...${NC}"
    
    # Create ServiceMonitor for cert-manager metrics
    kubectl apply -f - << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cert-manager-metrics
  namespace: cert-manager
  labels:
    app.kubernetes.io/name: cert-manager
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: cert-manager
      app.kubernetes.io/component: controller
  endpoints:
  - port: tcp-prometheus-servicemonitor
    interval: 60s
    path: /metrics
EOF

    # Create PrometheusRule for certificate alerts
    kubectl apply -f - << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cert-manager-alerts
  namespace: cert-manager
  labels:
    app: cert-manager
spec:
  groups:
  - name: cert-manager
    rules:
    - alert: CertManagerCertificateExpiration
      expr: (certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 30
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Certificate will expire soon"
        description: "Certificate {{ $labels.name }} in namespace {{ $labels.namespace }} will expire in {{ $value }} days."
    
    - alert: CertManagerCertificateNotReady
      expr: certmanager_certificate_ready_status == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Certificate not ready"
        description: "Certificate {{ $labels.name }} in namespace {{ $labels.namespace }} is not ready."
    
    - alert: CertManagerACMEAccountRegistrationFailed
      expr: increase(certmanager_acme_client_request_count{status="failure"}[5m]) > 0
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "ACME account registration failed"
        description: "ACME account registration has failed for issuer {{ $labels.name }}."
EOF

    # Create certificate expiry dashboard
    kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: certificate-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  certificate-dashboard.json: |
    {
      "dashboard": {
        "title": "Certificate Management Dashboard",
        "panels": [
          {
            "title": "Certificate Expiry Timeline",
            "type": "graph",
            "targets": [
              {
                "expr": "(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400",
                "legendFormat": "{{namespace}}/{{name}}"
              }
            ],
            "yAxes": [
              {
                "label": "Days until expiry"
              }
            ]
          },
          {
            "title": "Certificate Status",
            "type": "stat",
            "targets": [
              {
                "expr": "sum(certmanager_certificate_ready_status)",
                "legendFormat": "Ready Certificates"
              }
            ]
          },
          {
            "title": "ACME Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(certmanager_acme_client_request_count[5m])",
                "legendFormat": "{{status}}"
              }
            ]
          }
        ]
      }
    }
EOF

    echo -e "${GREEN}✅ Certificate monitoring configured${NC}"
}

# Configure automatic certificate renewal
configure_certificate_renewal() {
    echo -e "${BLUE}🔄 Configuring automatic certificate renewal...${NC}"
    
    # Create CronJob for certificate health checks
    kubectl apply -f - << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: certificate-health-check
  namespace: cert-manager
spec:
  schedule: "0 8 * * *"  # Daily at 8 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cert-checker
            image: quay.io/jetstack/cert-manager-ctl:v1.13.2
            command:
            - /bin/sh
            - -c
            - |
              echo "Checking certificate health..."
              kubectl get certificates --all-namespaces -o json | \
              jq -r '.items[] | select(.status.conditions[]?.type == "Ready" and .status.conditions[]?.status != "True") | "\(.metadata.namespace)/\(.metadata.name)"' | \
              while read cert; do
                echo "Certificate $cert is not ready, investigating..."
                kubectl describe certificate $cert
              done
          restartPolicy: OnFailure
EOF

    # Configure certificate renewal webhook
    kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cert-renewal-webhook
  namespace: cert-manager
data:
  webhook.sh: |
    #!/bin/bash
    # Certificate renewal webhook
    CERT_NAME=$1
    NAMESPACE=$2
    
    echo "Certificate $CERT_NAME in namespace $NAMESPACE has been renewed"
    
    # Send notification (customize as needed)
    curl -X POST "$WEBHOOK_URL" \
         -H "Content-Type: application/json" \
         -d "{\"text\": \"Certificate $CERT_NAME in $NAMESPACE has been renewed\"}"
EOF

    echo -e "${GREEN}✅ Certificate renewal configured${NC}"
}

# Validate certificate setup
validate_certificate_setup() {
    echo -e "${BLUE}🔍 Validating certificate setup...${NC}"
    
    local validation_passed=true
    
    # Check cert-manager status
    if kubectl get pods -n cert-manager -l app.kubernetes.io/instance=cert-manager --no-headers 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✅ cert-manager is running${NC}"
    else
        echo -e "${RED}❌ cert-manager is not running${NC}"
        validation_passed=false
    fi
    
    # Check ClusterIssuers
    local issuers=$(kubectl get clusterissuers --no-headers 2>/dev/null | wc -l)
    if [ "$issuers" -gt 0 ]; then
        echo -e "${GREEN}✅ $issuers ClusterIssuers configured${NC}"
    else
        echo -e "${RED}❌ No ClusterIssuers found${NC}"
        validation_passed=false
    fi
    
    # Check certificates
    local certs=$(kubectl get certificates --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$certs" -gt 0 ]; then
        echo -e "${GREEN}✅ $certs certificates configured${NC}"
        
        # Check certificate readiness
        local ready_certs=$(kubectl get certificates --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]?.type == "Ready" and .status.conditions[]?.status == "True") | .metadata.name' | wc -l)
        echo -e "${GREEN}   └─ $ready_certs certificates ready${NC}"
    else
        echo -e "${YELLOW}⚠️  No certificates found${NC}"
    fi
    
    # Check certificate secrets
    local cert_secrets=$(kubectl get secrets --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.type == "kubernetes.io/tls") | .metadata.name' | wc -l)
    if [ "$cert_secrets" -gt 0 ]; then
        echo -e "${GREEN}✅ $cert_secrets TLS secrets created${NC}"
    else
        echo -e "${YELLOW}⚠️  No TLS secrets found${NC}"
    fi
    
    if [ "$validation_passed" = true ]; then
        echo -e "${GREEN}✅ Certificate setup validation passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Certificate setup validation failed${NC}"
        return 1
    fi
}

# Display summary
display_summary() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  🎉 SSL/TLS CERTIFICATE SETUP COMPLETE 🎉                   ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}🔐 Certificate Management Summary:${NC}"
    echo -e "   📜 cert-manager: Automated certificate provisioning"
    echo -e "   🌐 Let's Encrypt: Public domain certificates"
    echo -e "   🏛️  Internal CA: Private service certificates"
    echo -e "   📊 Monitoring: Certificate expiry tracking"
    echo -e "   🔄 Renewal: Automatic certificate rotation"
    
    echo -e "\n${BLUE}🔧 What Was Configured:${NC}"
    echo -e "   ✅ cert-manager with CRDs and webhook"
    echo -e "   ✅ Let's Encrypt staging and production issuers"
    echo -e "   ✅ Custom internal CA for service mesh"
    echo -e "   ✅ Application certificates (frontend, backend, CI/CD)"
    echo -e "   ✅ Certificate monitoring and alerting"
    echo -e "   ✅ Automatic renewal and health checks"
    
    echo -e "\n${BLUE}📜 Certificate Issuers:${NC}"
    echo -e "   • letsencrypt-staging: For testing public certificates"
    echo -e "   • letsencrypt-prod: For production public certificates"
    echo -e "   • internal-ca-issuer: For internal service certificates"
    
    echo -e "\n${BLUE}🔗 Management Commands:${NC}"
    echo -e "   # Check certificate status:"
    echo -e "   kubectl get certificates -A"
    echo -e ""
    echo -e "   # Check ClusterIssuers:"
    echo -e "   kubectl get clusterissuers"
    echo -e ""
    echo -e "   # Debug certificate issues:"
    echo -e "   kubectl describe certificate <cert-name> -n <namespace>"
    echo -e ""
    echo -e "   # Check cert-manager logs:"
    echo -e "   kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager"
    
    echo -e "\n${BLUE}📊 Monitoring:${NC}"
    echo -e "   • Certificate expiry alerts configured"
    echo -e "   • Grafana dashboard for certificate metrics"
    echo -e "   • Daily health check CronJob"
    echo -e "   • Renewal webhook notifications"
    
    echo -e "\n${GREEN}🎊 Your SSL/TLS certificate management is fully automated! 🎊${NC}"
}

# Main execution
main() {
    print_banner
    
    echo -e "${BLUE}📋 Starting comprehensive SSL/TLS certificate setup...${NC}"
    echo -e "   Environment: $ENVIRONMENT"
    echo -e "   Region: $REGION"
    echo -e "   Domain: $DOMAIN"
    echo -e "   Email: $EMAIL"
    
    install_cert_manager
    configure_letsencrypt_issuers
    create_custom_ca
    configure_application_certificates
    configure_certificate_monitoring
    configure_certificate_renewal
    validate_certificate_setup
    display_summary
    
    echo -e "${GREEN}✅ SSL/TLS certificate setup completed successfully!${NC}"
}

# Execute main function
main "$@" 