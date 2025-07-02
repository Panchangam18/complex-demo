# CI/CD Infrastructure Organization

This directory contains all CI/CD related configurations, scripts, and pipelines for the complex-demo project.

## 📁 Directory Structure

```
ci-cd/
├── jenkins/           # Jenkins CI/CD components
│   ├── pipelines/     # Jenkins pipeline definitions
│   ├── scripts/       # Jenkins automation scripts
│   └── configs/       # Jenkins configuration files
├── nexus/             # Nexus Repository Manager components
│   ├── scripts/       # Nexus automation scripts
│   └── configs/       # Nexus configuration files
└── circleci/          # CircleCI configurations
```

## 🔧 Jenkins Components

### Pipelines (jenkins/pipelines/)
- **jenkins-nexus-integration.groovy** - Main Jenkins pipeline for building Vue.js frontend and Node.js backend with Nexus dependency caching

### Scripts (jenkins/scripts/)
- **configure-jenkins-triggers.sh** - Configures Jenkins job with scheduled triggers (nightly builds, weekly cleanup, SCM polling)
- **jenkins-nexus-integration-complete.sh** - Complete Jenkins-Nexus integration setup script
- **jenkins-nexus-demo.sh** - Jenkins-Nexus integration demonstration script
- **demo-jenkins-nexus-value.sh** - Demonstrates business value of Jenkins-Nexus integration

### Triggers Configuration
- **Daily builds**: 2:00 AM (nightly application builds)
- **Weekly cleanup**: Sunday 1:00 AM (artifact cleanup)  
- **SCM polling**: Every 15 minutes (Git repository changes)
- **Manual triggers**: Via Jenkins UI or API

## 📦 Nexus Components

### Scripts (nexus/scripts/)
- **nexus-cache-usage-demo.sh** - Demonstrates Nexus dependency caching benefits
- **demo-nexus-performance.sh** - Performance benchmarking script for Nexus

### Configurations (nexus/configs/)
- **nexus-consul-registration.yaml** - Consul service registration for Nexus
- **nexus-monitoring.yaml** - Monitoring configuration for Nexus

## 🔄 CircleCI Components

### Configuration (circleci/)
- **circleci-nexus-integration.yml** - CircleCI pipeline configuration with Nexus integration
- **Note**: Main .circleci/ directory remains at project root (required by CircleCI)

## 🚀 Usage

### Jenkins Setup
```bash
# Configure Jenkins with triggers
cd ci-cd/jenkins/scripts
./configure-jenkins-triggers.sh

# Run Jenkins demo
./jenkins-nexus-demo.sh
```

### Nexus Demo
```bash
# Demonstrate Nexus caching
cd ci-cd/nexus/scripts
./nexus-cache-usage-demo.sh
```

## 📊 Benefits

### Build Performance
- **5x faster builds** with Nexus dependency caching
- **Bandwidth savings**: 40MB → 5-10MB per build
- **Reliability**: Builds work even when npmjs.org is down

## 🔗 Integration Points

### With Infrastructure
- **Kubernetes**: Deploys to EKS, GKE, AKS clusters
- **Consul**: Service discovery integration
- **Prometheus**: Build metrics and monitoring
- **Nexus**: Centralized artifact repository

### With Applications
- **Frontend**: Vue.js application (Code/client)
- **Backend**: Node.js application (Code/server)
- **Docker**: Containerized deployments

## 📚 Documentation

See docs/ci-cd/ for detailed documentation:
- docs/ci-cd/jenkins/ - Jenkins setup guides and explanations
- docs/ci-cd/nexus/ - Nexus configuration and usage

## 🔧 Configuration

### Repository URLs
- **Git Repository**: https://github.com/Panchangam18/complex-demo.git
- **Branch**: main
- **Pipeline Path**: ci-cd/jenkins/pipelines/jenkins-nexus-integration.groovy
