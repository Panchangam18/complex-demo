# CircleCI Integration Setup Guide

## 📋 Required Contexts

### 1. `jfrog-context`
```bash
ARTIFACTORY_URL=https://forgea37.jfrog.io
ARTIFACTORY_USERNAME=sritan@a37.ai
ARTIFACTORY_TOKEN=cmVmdGtuOjAxOjE3ODEwNTgyMDA6aHFxUDczMnZBa1N0U2w3SVpOWmpVMk1wSkxz
ARTIFACTORY_DOCKER_REPO=docker-local
FRONTEND_IMAGE_NAME=dev-frontend
BACKEND_IMAGE_NAME=dev-backend
```

### 2. `aws-context`
```bash
AWS_REGION=us-east-2
AWS_ROLE_ARN=arn:aws:iam::YOUR_ACCOUNT:role/CircleCIRole
```

### 3. `gcp-context`
```bash
GCP_PROJECT_ID=forge-demo-463617
GCP_REGION=us-east1
GOOGLE_CLOUD_KEYFILE_JSON=<service-account-json>
```

### 4. `prometheus-context`
```bash
PROMETHEUS_PUSHGATEWAY_URL=http://your-prometheus-pushgateway:9091
```

### 5. `github-context`
```bash
GITHUB_TOKEN=<your-github-token>
```

## 🔒 Setting up OIDC Authentication

### AWS OIDC Provider Setup

1. **Create IAM Role for CircleCI:**
```bash
aws iam create-role \
  --role-name CircleCIRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::YOUR_ACCOUNT:oidc-provider/oidc.circleci.com/org/YOUR_ORG_ID"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "oidc.circleci.com/org/YOUR_ORG_ID:aud": "YOUR_ORG_ID"
          }
        }
      }
    ]
  }'
```

2. **Attach necessary policies:**
```bash
aws iam attach-role-policy \
  --role-name CircleCIRole \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

aws iam attach-role-policy \
  --role-name CircleCIRole \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
```

### GCP Service Account Setup

1. **Create service account:**
```bash
gcloud iam service-accounts create circleci-deployment \
  --display-name="CircleCI Deployment Account"
```

2. **Grant necessary roles:**
```bash
gcloud projects add-iam-policy-binding forge-demo-463617 \
  --member="serviceAccount:circleci-deployment@forge-demo-463617.iam.gserviceaccount.com" \
  --role="roles/editor"

gcloud projects add-iam-policy-binding forge-demo-463617 \
  --member="serviceAccount:circleci-deployment@forge-demo-463617.iam.gserviceaccount.com" \
  --role="roles/container.admin"
```

3. **Create and download key:**
```bash
gcloud iam service-accounts keys create circleci-key.json \
  --iam-account=circleci-deployment@forge-demo-463617.iam.gserviceaccount.com
```

## 🎯 Testing the Pipeline

### First Test Run
1. **Commit the config file:**
```bash
git add .circleci/config.yml docs/circleci-setup.md
git commit -m "feat: add CircleCI integration"
git push origin main
```

2. **Monitor in CircleCI Dashboard:**
   - Go to **Pipelines** 
   - Watch the `ci-cd-pipeline` workflow execute
   - Check logs for any errors

### Expected Pipeline Flow
```
1. security-scan (parallel)     ← SAST/Container scans
2. terraform-validate (parallel) ← Infrastructure validation  
3. build-frontend (parallel)    ← Vue.js build & test
4. build-backend (parallel)     ← Node.js build & test
5. terraform-plan              ← Infrastructure planning
6. build-and-push-images       ← Docker build + JFrog push
7. [Manual Approval]           ← Production safety gate
8. terraform-apply             ← Infrastructure deployment
9. update-gitops-manifests     ← ArgoCD trigger
```

## 🔍 Troubleshooting

### Common Issues:

**1. Context Variables Not Found:**
- Ensure contexts are created with exact names
- Verify environment variables are set in contexts
- Check workflow uses correct context names

**2. OIDC Authentication Fails:**
- Verify OIDC provider is created in AWS/GCP
- Check role trust relationships
- Ensure org ID matches in role policy

**3. JFrog Login Fails:**
- Verify token is current and has push permissions
- Check repository exists in JFrog
- Test login manually: `docker login forgea37.jfrog.io`

**4. Terraform Commands Fail:**
- Ensure backend configuration matches
- Check AWS credentials and permissions
- Verify Terraform Cloud token if using remote backend

## 📊 Monitoring Build Metrics

Your pipeline publishes metrics to Prometheus pushgateway:
- Build success/failure rates
- Build duration
- Image vulnerability counts
- Infrastructure drift detection

Access via Grafana dashboards in your observability stack. 