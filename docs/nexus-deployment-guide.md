# 📦 Nexus Repository Manager Deployment Guide

This guide covers deploying and configuring Nexus Repository Manager as your artifact management solution, following your comprehensive architecture plan.

## 🎯 Why Nexus First?

Based on your architecture plan, **Nexus Repository** is the optimal next step because:

### **Immediate Benefits**
- ✅ **Dependency Caching**: NPM, PyPI, Go modules cached locally
- ✅ **Faster Builds**: Eliminate repeated downloads from public registries  
- ✅ **Bandwidth Optimization**: Reduce external traffic costs
- ✅ **Offline Capability**: Builds continue even if upstream registries are unavailable

### **Strategic Foundation**
- 🏗️ **Prepares for Jenkins**: Artifact management ready for legacy builds
- 🔄 **CI/CD Evolution**: Foundation for your comprehensive pipeline
- 📦 **Multi-Language Support**: Vue.js, Node.js, Python, Go dependencies
- 🌐 **Multi-Cloud Ready**: Can be deployed on any Kubernetes cluster

## 🚀 Deployment Steps

### **Step 1: Deploy Nexus Infrastructure**

```bash
# Deploy Nexus to your EKS cluster
cd terraform
make apply ENV=dev REGION=us-east-2
```

This will:
- ✅ Create `nexus-dev` namespace
- ✅ Deploy Nexus with persistent storage (200Gi)
- ✅ Configure LoadBalancer service
- ✅ Set up Prometheus monitoring
- ✅ Allocate appropriate resources (4Gi RAM, 2 CPU)

### **Step 2: Wait for Deployment**

```bash
# Check deployment status
make nexus-status ENV=dev REGION=us-east-2

# Watch pods come online
kubectl get pods -n nexus-dev -w
```

**Expected Timeline**: 5-10 minutes for full startup

### **Step 3: Configure Repositories**

```bash
# Run automated repository configuration
make configure-nexus ENV=dev REGION=us-east-2
```

This script will:
- ✅ Create NPM proxy, hosted, and group repositories
- ✅ Create Docker proxy, hosted, and group repositories  
- ✅ Create PyPI proxy and group repositories
- ✅ Configure security and access policies
- ✅ Provide access credentials and URLs

### **Step 4: Verify Access**

```bash
# Get Nexus URL and credentials
cd terraform/envs/dev/us-east-2
terragrunt output nexus_url
terragrunt output nexus_admin_password_command

# Execute the password command
$(terragrunt output -raw nexus_admin_password_command)
```

## 📦 Repository Configuration

After deployment, Nexus will have these repositories configured:

### **NPM Repositories**
```bash
# npm-proxy: Caches from registry.npmjs.org
# npm-hosted: Your internal NPM packages
# npm-public: Group repository (hosted + proxy)

# Configure npm to use Nexus
npm config set registry http://<NEXUS_URL>/repository/npm-public/
```

### **Docker Repositories** 
```bash
# docker-proxy: Caches from Docker Hub
# docker-hosted: Your internal Docker images
# docker-public: Group repository

# Login to Nexus Docker registry
docker login <NEXUS_HOST>:8086
```

### **Python (PyPI) Repositories**
```bash
# pypi-proxy: Caches from pypi.org
# pypi-public: Group repository

# Configure pip to use Nexus
pip config --global set global.index-url http://<NEXUS_URL>/repository/pypi-public/simple/
```

## 🔧 Integration with Existing Workflow

### **Update Build Scripts**

Your current `build-and-push.sh` can be enhanced to use Nexus:

```bash
# Add to Code/client/package.json
{
  "config": {
    "registry": "http://<NEXUS_URL>/repository/npm-public/"
  }
}

# Update Dockerfiles to use Nexus registries
FROM <NEXUS_HOST>:8086/node:18-alpine
```

### **Kubernetes Integration**

Nexus integrates seamlessly with your existing setup:
- **Namespace**: `nexus-dev` (isolated from applications)
- **Storage**: Persistent volumes with encryption
- **Monitoring**: Prometheus metrics enabled
- **Security**: Non-root containers, security contexts

## 📊 Monitoring & Observability

Nexus integrates with your observability stack:

### **Metrics Export**
```bash
# Prometheus scrapes metrics from Nexus
http://<NEXUS_URL>/service/metrics/prometheus

# Key metrics:
nexus_blob_store_total_size_bytes
nexus_repository_component_total
nexus_jvm_memory_used_bytes
```

### **Health Checks**
```bash
# Kubernetes health probes
curl http://<NEXUS_URL>/service/rest/v1/status
```

## 🔐 Security Configuration

Nexus follows security best practices:

### **Container Security**
- ✅ Non-root user (UID 200)
- ✅ Read-only root filesystem
- ✅ Security context enforced
- ✅ Resource limits applied

### **Network Security**
- ✅ Namespace isolation
- ✅ LoadBalancer with security groups
- ✅ HTTPS-ready (certificate support)
- ✅ Authentication required

### **Storage Security**
- ✅ Encrypted persistent volumes
- ✅ Backup retention policies
- ✅ Access control via RBAC

## 🚀 Next Steps After Nexus

With Nexus deployed, you're ready for the next phase:

### **Phase 2A: Puppet Enterprise** (Day-2 Operations)
```bash
# Puppet for ongoing configuration management
# - Package, file, and service state
# - Compliance and drift remediation
# - Integration with Ansible Tower
```

### **Phase 2B: Jenkins** (Legacy CI/CD)
```bash
# Jenkins for specialized builds
# - Legacy JVM builds & nightly tasks  
# - Complement to CircleCI
# - Nexus integration for artifact management
```

### **Phase 3: Advanced Observability**
```bash
# Complete the observability stack
# - Prometheus + Grafana
# - Thanos for long-term storage
# - AlertManager for notifications
```

## 🛠️ Troubleshooting

### **Common Issues**

**1. Pod Startup Slow**
```bash
# Nexus requires significant memory for startup
kubectl describe pod -n nexus-dev -l app=nexus
kubectl logs -n nexus-dev -l app=nexus
```

**2. LoadBalancer Pending**
```bash
# Check AWS Load Balancer Controller
kubectl get svc -n nexus-dev
kubectl describe svc -n nexus-dev
```

**3. Storage Issues**
```bash
# Verify PVC is bound
kubectl get pvc -n nexus-dev
kubectl describe pvc nexus-data -n nexus-dev
```

**4. Repository Creation Fails**
```bash
# Check admin password and connectivity
kubectl exec -n nexus-dev -it <nexus-pod> -- cat /nexus-data/admin.password
curl -u admin:<password> http://<NEXUS_URL>/service/rest/v1/status
```

## 💡 Optimization Tips

### **Performance Tuning**
```bash
# Increase memory for large repositories
# Update terraform/modules/k8s/nexus/variables.tf:
memory_request = "6Gi"
memory_limit = "8Gi"
```

### **Storage Optimization**
```bash
# Enable cleanup policies
# Configure blob store compaction
# Set up repository health checks
```

### **Build Optimization**
```bash
# Configure Docker daemon to use Nexus
# Set npm/pip cache directories
# Use multi-stage builds with cached layers
```

## 🎊 Success Criteria

After completing this deployment, you'll have:

✅ **Enterprise Artifact Management**: Nexus handling all dependency caching  
✅ **Improved Build Performance**: Faster builds with local dependency cache  
✅ **Reduced External Dependencies**: Offline build capability  
✅ **Foundation for Advanced CI/CD**: Ready for Jenkins and CircleCI integration  
✅ **Security Compliance**: Encrypted storage, authentication, RBAC  
✅ **Monitoring Integration**: Prometheus metrics and health checks  

Your infrastructure now has the **artifact management backbone** required for enterprise-scale development! 🚀

---

## 📋 Quick Reference

```bash
# Deploy Nexus
make apply ENV=dev REGION=us-east-2

# Configure repositories  
make configure-nexus ENV=dev REGION=us-east-2

# Check status
make nexus-status ENV=dev REGION=us-east-2

# Get access info
terragrunt output nexus_url
$(terragrunt output -raw nexus_admin_password_command)

# Configure local tools
npm config set registry http://<NEXUS_URL>/repository/npm-public/
pip config --global set global.index-url http://<NEXUS_URL>/repository/pypi-public/simple/
docker login <NEXUS_HOST>:8086
``` 