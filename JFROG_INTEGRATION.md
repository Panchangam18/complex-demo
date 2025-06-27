# 🚀 JFrog Artifactory Integration Guide

This guide walks you through the complete JFrog Artifactory integration for your multi-cloud DevOps platform, including building, pushing, and deploying your Vue.js frontend and Node.js backend applications.

## 🎯 Overview

Your architecture now uses **JFrog Artifactory** as the primary container registry instead of ECR, aligning with your comprehensive plan's artifact management strategy:

- **Signed image verification** with Connaisseur admission controller
- **Multi-site replication** (EU, US, APAC)
- **Unified artifact management** across clouds
- **Security scanning** and gatekeeping

## 📋 Prerequisites

1. **JFrog Cloud Account** ✅ (Already configured)
2. **Docker** installed locally
3. **kubectl** configured for your EKS cluster
4. **Repository Setup** in JFrog (see below)

## 🏗️ JFrog Repository Setup

Before building images, ensure you have the following repositories in your JFrog instance (`https://forgea37.jfrog.io`):

### **Required Repositories:**
```bash
# Log into JFrog → Administration → Repositories → Repositories

1. docker-local     # For storing your built images
2. docker-remote    # Proxy to Docker Hub (optional)
3. docker           # Virtual repo (combines local + remote)
```

**If you don't have these**, create them:
- **Repository Key**: `docker-local`
- **Package Type**: Docker
- **Repository Layout**: `maven 2 default`

## ⚙️ Environment Setup

### **1. Create `.env` file in project root:**

```bash
# .env (already configured for you!)
ARTIFACTORY_URL=https://forgea37.jfrog.io
ARTIFACTORY_USERNAME=sritan@a37.ai
ARTIFACTORY_TOKEN=cmVmdGtuOjAxOjE3ODEwNTgyMDA6aHFxUDczMnZBa1N0U2w3SVpOWmpVMk1wSkxz

# Docker Repository Names 
ARTIFACTORY_DOCKER_REPO=docker-local
ARTIFACTORY_DOCKER_VIRTUAL=docker

# Environment
ENVIRONMENT=dev
AWS_REGION=us-east-2
GCP_PROJECT_ID=forge-demo-463617

# Application Configuration
FRONTEND_IMAGE_NAME=dev-frontend
BACKEND_IMAGE_NAME=dev-backend
IMAGE_TAG=latest
```

## 🚀 Complete Workflow

### **Step 1: Build and Push Images**

```bash
# Build both frontend and backend, push to JFrog
./scripts/build-and-push.sh
```

**This script will:**
- ✅ Login to JFrog Artifactory
- ✅ Build optimized Docker images for Vue.js frontend and Node.js backend
- ✅ Push images to JFrog with proper tagging
- ✅ Provide image URLs for next steps

**Expected Output:**
```bash
🎉 Build and push completed successfully!
📋 Images pushed:
  Frontend: https://forgea37.jfrog.io/docker-local/dev-frontend:latest
  Backend:  https://forgea37.jfrog.io/docker-local/dev-backend:latest
```

### **Step 2: Update Kubernetes Deployments**

```bash
# Update K8s deployment files to use JFrog images
./scripts/update-k8s-images.sh
```

**This script will:**
- ✅ Replace ECR image URLs with JFrog URLs in deployment files
- ✅ Update both frontend and backend deployments
- ✅ Preserve all other configuration

### **Step 3: Create Image Pull Secrets**

```bash
# First, connect to your EKS cluster
aws eks update-kubeconfig --region us-east-2 --name dev-eks-us-east-2

# Create JFrog pull secrets in all namespaces
./scripts/create-image-pull-secrets.sh
```

**This script will:**
- ✅ Create `jfrog-pull-secret` in all necessary namespaces
- ✅ Patch default service accounts to use the secret automatically
- ✅ Verify secret creation

### **Step 4: Deploy via GitOps**

```bash
# Your ArgoCD will automatically detect and sync the changes
# Or manually sync via ArgoCD UI

# Commit and push the updated deployment files
git add k8s/envs/dev/*/deployment.yaml
git commit -m "feat: migrate to JFrog Artifactory for container images"
git push origin main
```

## 📁 Files Created/Modified

### **New Files:**
- `Code/client/nginx.conf` - Optimized nginx config for Vue.js SPA
- `scripts/build-and-push.sh` - Build and push automation
- `scripts/update-k8s-images.sh` - Update deployment files
- `scripts/create-image-pull-secrets.sh` - K8s secret management
- `k8s/secrets/jfrog-pull-secret.yaml` - Secret template

### **Modified Files:**
- `Code/client/Dockerfile` - Multi-stage, optimized build
- `Code/server/Dockerfile` - Multi-stage, security-hardened build
- `k8s/envs/dev/frontend/deployment.yaml` - JFrog image URLs
- `k8s/envs/dev/backend/deployment.yaml` - JFrog image URLs

## 🐳 Docker Image Optimization

### **Frontend (Vue.js):**
- **Multi-stage build**: Node.js build → Nginx serving
- **Alpine Linux**: Smaller image size
- **Security headers**: CORS, XSS protection, content type sniffing
- **Gzip compression**: Better performance
- **Health checks**: `/health` endpoint

### **Backend (Node.js):**
- **Multi-stage build**: Separate build and runtime stages
- **Non-root user**: Security best practice
- **Production dependencies only**: Smaller attack surface
- **Health checks**: Uses existing `/status` endpoint

## 🔐 Security Enhancements

### **Image Pull Secrets:**
- Automatic authentication to JFrog Artifactory
- Scoped to specific namespaces
- Integrated with default service accounts

### **Docker Security:**
- Non-root containers
- Minimal base images (Alpine Linux)
- Multi-stage builds to reduce attack surface
- Health checks for container reliability

## 🎯 Image URLs

After successful build and push:

```bash
# Frontend
https://forgea37.jfrog.io/docker-local/dev-frontend:latest

# Backend  
https://forgea37.jfrog.io/docker-local/dev-backend:latest
```

## 🔄 CI/CD Integration (Next Phase)

Your comprehensive plan calls for CircleCI integration. The foundation is now ready:

```yaml
# .circleci/config.yml (future)
workflows:
  application-pipeline:
    - build-and-test
    - security-scan:
        requires: [build-and-test]
    - build-and-push-to-jfrog:
        requires: [security-scan]
        filters: { branches: { only: main } }
    - update-gitops-manifests:
        requires: [build-and-push-to-jfrog]
```

## 🚨 Troubleshooting

### **Common Issues:**

**1. Login Failed:**
```bash
# Check credentials in .env file
# Verify JFrog URL and token
```

**2. Repository Not Found:**
```bash
# Create docker-local repository in JFrog UI
# Verify ARTIFACTORY_DOCKER_REPO variable
```

**3. K8s Pull Fails:**
```bash
# Verify image pull secret exists
kubectl get secrets jfrog-pull-secret -n frontend-dev

# Check service account patch
kubectl get serviceaccount default -n frontend-dev -o yaml
```

**4. Build Fails:**
```bash
# Check Docker daemon is running
# Verify Dockerfile syntax
# Check network connectivity to JFrog
```

## 🎉 Success Verification

### **1. Images in JFrog:**
- Log into JFrog UI → Artifactory → docker-local
- Verify `dev-frontend` and `dev-backend` repositories exist

### **2. Kubernetes Deployment:**
```bash
# Check pod status
kubectl get pods -n frontend-dev
kubectl get pods -n backend-dev

# Check image pull events
kubectl describe pod <pod-name> -n <namespace>
```

### **3. Application Access:**
```bash
# Your applications should be accessible via:
# Frontend: https://dev-frontend.your-domain.com
# Backend: https://dev-api.your-domain.com
```

## 🚀 Next Steps (Aligned with Your Architecture)

1. **✅ JFrog Artifactory Integration** - Complete!
2. **🔄 CircleCI Pipeline** - Build metadata to Prometheus
3. **⚙️ Ansible Tower** - Configuration management
4. **🔐 HashiCorp Vault** - Secrets management
5. **🛡️ OPA/Gatekeeper** - Policy enforcement
6. **📊 Advanced Observability** - Thanos, New Relic integration

---

**🎊 Congratulations!** Your application images are now managed through JFrog Artifactory, providing enterprise-grade artifact management with security scanning, multi-site replication, and seamless integration with your multi-cloud DevOps platform. 