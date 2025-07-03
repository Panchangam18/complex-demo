# 🚀 Unified Multi-Cloud DevOps Platform Deployment Guide

This guide explains how to use the unified `deploy.sh` script to deploy your entire multi-cloud DevOps platform with all integrations in a single command.

## 📋 Overview

The `deploy.sh` script consolidates all your deployment logic into a single, comprehensive automation that:

- ✅ **Validates prerequisites** and credentials
- ✅ **Deploys infrastructure** via Terraform (AWS, GCP, Azure)
- ✅ **Configures management** via Ansible Tower and Puppet Enterprise
- ✅ **Sets up observability** with DataDog, Elasticsearch, and New Relic
- ✅ **Deploys CI/CD pipeline** with Jenkins, Nexus, and ArgoCD
- ✅ **Builds and deploys applications** with automated GitOps
- ✅ **Validates deployment** and provides comprehensive summary

## 🔐 Required External Service Credentials

Before running the deployment, you'll need credentials for these external services:

### 1. Elasticsearch Cloud
```bash
# Get from: https://cloud.elastic.co/
ELASTICSEARCH_URL="https://your-deployment-id.region.cloud.es.io:443"
ELASTICSEARCH_API_KEY="your-base64-encoded-api-key"
```

### 2. DataDog
```bash
# Get from: https://app.datadoghq.com/organization-settings/api-keys
DATADOG_API_KEY="your-32-char-api-key"
DATADOG_APP_KEY="your-40-char-application-key"
```

### 3. New Relic
```bash
# Get from: https://one.newrelic.com/api-keys
NEWRELIC_LICENSE_KEY="your-40-char-license-key"
```

### 4. JFrog Artifactory
```bash
# Your JFrog SaaS or self-hosted instance
ARTIFACTORY_URL="https://your-company.jfrog.io"
ARTIFACTORY_USERNAME="your-username"
ARTIFACTORY_PASSWORD="your-password-or-api-token"
```

## 🚀 Quick Start

### 1. Full Production Deployment

```bash
./deploy.sh \
    --elasticsearch-url "https://your-deployment.es.io:443" \
    --elasticsearch-api-key "your-es-api-key" \
    --datadog-api-key "your-dd-api-key" \
    --datadog-app-key "your-dd-app-key" \
    --newrelic-license "your-nr-license" \
    --artifactory-url "https://your-company.jfrog.io" \
    --artifactory-username "your-username" \
    --artifactory-password "your-password" \
    --env dev \
    --region us-east-2
```

### 2. Dry Run (See What Would Be Deployed)

```bash
./deploy.sh --dry-run \
    --elasticsearch-url "https://your-deployment.es.io:443" \
    --elasticsearch-api-key "your-es-api-key" \
    --datadog-api-key "your-dd-api-key" \
    --datadog-app-key "your-dd-app-key" \
    --newrelic-license "your-nr-license" \
    --artifactory-url "https://your-company.jfrog.io" \
    --artifactory-username "your-username" \
    --artifactory-password "your-password"
```

### 3. Infrastructure Only

```bash
./deploy.sh \
    --skip-observability \
    --skip-cicd \
    --skip-applications \
    [your-credentials...]
```

### 4. Multi-Cloud Production Environment

```bash
./deploy.sh \
    --env prod \
    --region us-west-2 \
    --gcp-project-id "your-gcp-project" \
    --azure-subscription-id "your-azure-sub" \
    [your-credentials...]
```

## 🏗️ Deployment Phases

The script executes these phases in order:

### Phase 1: Prerequisites Validation
- ✅ Validates required tools (terraform, kubectl, docker, etc.)
- ✅ Checks cloud credentials (AWS, GCP, Azure)
- ✅ Validates external service credentials

### Phase 2: Infrastructure Deployment
- ✅ Deploys AWS EKS, RDS, ECR, VPC
- ✅ Deploys GCP GKE, VPC, Cloud Storage
- ✅ Deploys Azure AKS, VNet, Container Registry
- ✅ Sets up multi-cloud networking and security

### Phase 3: Configuration Management
- ✅ Configures Ansible Tower with dynamic inventory
- ✅ Runs Day-0 provisioning (OS hardening, Consul agents)
- ✅ Sets up Puppet Enterprise for Day-2 operations
- ✅ Configures drift detection and compliance

### Phase 4: Observability Stack
- ✅ Deploys DataDog agents to all clusters
- ✅ Configures Elasticsearch with Fluent Bit logging
- ✅ Sets up New Relic monitoring
- ✅ Deploys Prometheus/Grafana stack
- ✅ Creates unified dashboards and alerting

### Phase 5: CI/CD Pipeline
- ✅ Deploys Nexus Repository Manager
- ✅ Configures Jenkins with Nexus integration
- ✅ Sets up ArgoCD for GitOps deployments
- ✅ Creates automated CI/CD workflows

### Phase 6: Application Deployment
- ✅ Builds Vue.js frontend and Node.js backend
- ✅ Pushes images to Artifactory
- ✅ Updates Kubernetes manifests
- ✅ Triggers ArgoCD sync for multi-cluster deployment

### Phase 7: Validation & Summary
- ✅ Validates all services are running
- ✅ Checks connectivity and health
- ✅ Provides access URLs and next steps

## 🎛️ Control Options

### Environment Selection
```bash
# Deploy to different environments
--env dev          # Development (default)
--env staging      # Staging environment  
--env prod         # Production environment
```

### Regional Deployment
```bash
# Deploy to different AWS regions
--region us-east-2    # Default
--region us-west-2    # Alternative region
--region eu-west-1    # European region
```

### Skip Specific Phases
```bash
--skip-terraform      # Skip infrastructure deployment
--skip-config-mgmt    # Skip configuration management
--skip-observability  # Skip monitoring/logging setup
--skip-cicd          # Skip CI/CD pipeline
--skip-applications  # Skip application deployment
```

### Cloud Provider Selection
```bash
# Multi-cloud deployment
--gcp-project-id "your-project"           # Enable GCP
--azure-subscription-id "your-sub-id"     # Enable Azure
# AWS is always enabled via --profile
```

## 📊 What Gets Deployed

### Infrastructure Components
- **AWS**: EKS cluster, RDS PostgreSQL, ECR repositories, S3 buckets
- **GCP**: GKE cluster, VPC network, Cloud Storage
- **Azure**: AKS cluster, Virtual Network, Container Registry
- **Cross-Cloud**: VPN connections, service mesh, load balancers

### Service Mesh & Discovery
- **Consul**: Multi-datacenter service discovery
- **mTLS**: Automatic service-to-service encryption
- **Health Checks**: Automated service monitoring
- **DNS**: Service discovery via DNS

### Observability Stack
- **DataDog**: Infrastructure, APM, logs, security monitoring
- **Elasticsearch**: Centralized logging with Fluent Bit
- **New Relic**: Application performance monitoring
- **Prometheus/Grafana**: Custom metrics and dashboards

### CI/CD Pipeline
- **Jenkins**: Automated builds and testing
- **Nexus**: Artifact and dependency management
- **ArgoCD**: GitOps deployments to multiple clusters
- **GitHub Actions**: Code quality and security scanning

### Applications
- **Frontend**: Vue.js SPA with Bootstrap UI
- **Backend**: Node.js API with Swagger documentation
- **Databases**: PostgreSQL with automated backups
- **Caching**: Redis for session and application caching

## 🔧 Troubleshooting

### Common Issues

1. **Credential Validation Fails**
   ```bash
   # Test individual services
   curl -H "Authorization: ApiKey $ELASTICSEARCH_API_KEY" "$ELASTICSEARCH_URL/_cluster/health"
   curl -H "DD-API-KEY: $DATADOG_API_KEY" "https://api.datadoghq.com/api/v1/validate"
   ```

2. **Cloud Authentication Issues**
   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity --profile your-profile
   
   # Verify GCP credentials
   gcloud auth application-default print-access-token
   
   # Verify Azure credentials
   az account show
   ```

3. **Terraform State Issues**
   ```bash
   # Reset Terraform state if needed
   cd terraform
   make clean ENV=dev REGION=us-east-2
   make init ENV=dev REGION=us-east-2
   ```

4. **Deployment Failures**
   ```bash
   # Check deployment logs
   tail -f deployment-YYYYMMDD-HHMMSS.log
   
   # Validate Kubernetes connectivity
   kubectl cluster-info
   kubectl get nodes
   ```

### Log Analysis

The deployment script creates detailed logs at:
```
deployment-YYYYMMDD-HHMMSS.log
```

Search for specific issues:
```bash
# Find errors
grep "ERROR" deployment-*.log

# Find failed phases  
grep "Failed phase" deployment-*.log

# Find warnings
grep "WARNING" deployment-*.log
```

## 🎯 Post-Deployment

### Access URLs

After successful deployment, you'll have access to:

- **DataDog Dashboard**: https://app.datadoghq.com/
- **Elasticsearch**: Your provided Elasticsearch URL
- **New Relic**: https://one.newrelic.com/
- **Artifactory**: Your provided Artifactory URL
- **Jenkins**: Auto-discovered LoadBalancer URL
- **Nexus**: Auto-discovered LoadBalancer URL
- **Consul UI**: Auto-discovered LoadBalancer URL

### Next Steps

1. **Configure Monitoring Alerts**
   - Set up DataDog alerts for critical services
   - Configure Elasticsearch log-based alerts
   - Set up New Relic SLI/SLO monitoring

2. **Access Management**
   - Configure team access to all services
   - Set up SSO integration where available
   - Configure RBAC policies

3. **Application Customization**
   - Customize Vue.js frontend branding
   - Add business-specific API endpoints
   - Configure application-specific monitoring

4. **Scale to Additional Environments**
   ```bash
   # Deploy staging environment
   ./deploy.sh --env staging [credentials...]
   
   # Deploy production environment
   ./deploy.sh --env prod --region us-west-2 [credentials...]
   ```

## 🔐 Security Best Practices

### Credential Management
- Store credentials in your organization's secret management system
- Use environment variables for automation
- Rotate credentials regularly
- Use least-privilege access policies

### Example with Environment Variables
```bash
export ELASTICSEARCH_URL="https://your-deployment.es.io:443"
export ELASTICSEARCH_API_KEY="your-api-key"
export DATADOG_API_KEY="your-dd-api-key"
export DATADOG_APP_KEY="your-dd-app-key"
export NEWRELIC_LICENSE_KEY="your-nr-license"
export ARTIFACTORY_URL="https://your-company.jfrog.io"
export ARTIFACTORY_USERNAME="your-username"
export ARTIFACTORY_PASSWORD="your-password"

./deploy.sh \
    --elasticsearch-url "$ELASTICSEARCH_URL" \
    --elasticsearch-api-key "$ELASTICSEARCH_API_KEY" \
    --datadog-api-key "$DATADOG_API_KEY" \
    --datadog-app-key "$DATADOG_APP_KEY" \
    --newrelic-license "$NEWRELIC_LICENSE_KEY" \
    --artifactory-url "$ARTIFACTORY_URL" \
    --artifactory-username "$ARTIFACTORY_USERNAME" \
    --artifactory-password "$ARTIFACTORY_PASSWORD"
```

## 🎉 Success!

With this unified deployment script, you now have:

- ✅ **One-command deployment** of your entire multi-cloud platform
- ✅ **Comprehensive validation** at every step
- ✅ **Detailed logging** for troubleshooting
- ✅ **Flexible control** over deployment phases
- ✅ **Enterprise-grade** infrastructure and monitoring
- ✅ **Production-ready** CI/CD pipeline
- ✅ **Automated application** deployment

Your multi-cloud DevOps platform is now fully automated and ready to scale! 🚀 