# Developer Notes

the main files to consider for deployment and destruction are deploy.sh and destroy.sh respectively

to run load tests, you should be in root and have kubeconfig configured with the deployed cluster, then run the following command:

make run-load-tests          # all tests
make run-backend-load-test   # backend tests  
make run-frontend-load-test  # frontend tests

peep Code/client/src/tests/stresstests for more info on what the tests actually do

---

# Multicloud DevOps Stack – Comprehensive Architecture & Integration Guide

## 1. Executive Summary

This document prescribes a single‑source, **multicloud DevOps platform** that spans AWS, GCP, and Azure. All infrastructure is defined and version‑controlled in one Terraform mono‑repository, while operations, observability, security, and deployment workflows are federated across clouds but presented through unified control planes. 

The stack emphasises:
- **Git‑centric automation**
- **Service discoverability**
- **Holistic observability**
- **Rapid delivery with strong governance**

## 2. Infrastructure‑as‑Code (IaC)

| Element | Detail |
|---------|--------|
| **Repository Layout** | `/modules/<provider>/<service>` reusable modules; `/envs/<env>` environments |
| **Backends** | Remote state in Terraform Cloud per environment, with state‑sharing locks across clouds |
| **Validation** | `tflint`, `checkov`, and `terraform validate` run in CircleCI |
| **Apply Workflow** | Protected main branch merges trigger CircleCI ➔ `terraform plan`; approval ➔ `terraform apply` via OIDC‑based short‑lived cloud creds |

### Cross‑Cloud Account / Project Strategy

- **AWS** – Dedicated Landing Zone with separate accounts per workload tier (prod, non‑prod)
- **GCP** – Projects mirror AWS accounts; Cloud Identity federates users
- **Azure** – Management Group hierarchy mirrors the other providers, enforced with Azure Policy

## 3. Networking & Connectivity

### Address Space
**Flat Address Space** – A `/8` RFC‑1918 range is subdivided into `/16` per cloud, `/20` per region.

### In‑Cloud Fabric
- **AWS**: VPC per region with public, private, and intra‑service subnets; connectivity via AWS Transit Gateway
- **Azure**: Hub‑and‑Spoke VNets with Azure Firewall
- **GCP**: Shared‑VPC topology with Dedicated Interconnect optional

### Inter‑Cloud Peering / VPN
IPSec tunnels terminate on cloud‑native VPN gateways and are managed by Terraform. BGP propagates routes to form a single RFC‑1918 mesh.

### Consul WAN Federation
Every VPC/VNet hosts a Consul server cluster (odd count, 1–3 per region) joined via WAN federation over the VPN mesh.

## 4. Identity, Secrets & Policy

| Concern | Implementation |
|---------|----------------|
| **Human SSO** | Azure AD is IdP; AWS IAM Identity Center & GCP Workload Identity Federation consume via SAML/OIDC |
| **Workload Identities** | Terraform configures identity providers so Kubernetes ServiceAccounts receive cloud‑native credentials via IAM Roles for Service Accounts (IRSA), Workload Identity Federation, or Managed Identity |
| **Secrets** | Argo CD's `argocd-vault-plugin` sources secrets from HashiCorp Vault mounts in each cloud; Vault replicates via Performance Replication |
| **Policy as Code** | Open Policy Agent (OPA)/Gatekeeper enforces Kubernetes guardrails; Sentinel & Azure Policy govern IaC plans |

## 5. Continuous Integration (CI)

### 5.1 Build Pipelines

| Stage | CircleCI | Jenkins | AWS CodeBuild |
|-------|----------|---------|---------------|
| **Compile & Test** | Primary orchestrator; containerised executors spin up per commit | Legacy JVM builds & nightly tasks | Provider‑specific builds for AWS serverless artefacts |
| **Security Scans** | Anchore/Trivy in CircleCI; SonarQube in Jenkins | – | – |
| **Image Push** | Docker images pushed to Artifactory (prod) & ECR (AWS); language artefacts to Nexus as proxy cache | – | – |

> **Note**: All pipelines publish build metadata to Prometheus via `prometheus-pushgateway` for traceability.

## 6. GitOps & Continuous Delivery (CD)

**Argo CD** (HA, three replicas) runs in a dedicated management Kubernetes cluster in AWS `us‑east‑1`. It:

- Watches Git `envs/<env>` directories
- Performs sync to target clusters (EKS, GKE, AKS, on‑prem) using Argo CD Image Updater to roll new tags
- Blue/Green & Canary handled by Argo Rollouts where available, or AWS CodeDeploy for ECS

### Cross‑Cloud RBAC
Each target cluster exposes an OIDC provider; Argo CD uses `kube‑service‑account` tokens with least privilege.

## 7. Configuration Management & Day‑2 Ops

| Tool | Moment of Use | Scope | Integration |
|------|---------------|-------|-------------|
| **Ansible Tower / AWX** | Day‑0/1 provisioning of OS, middleware, and Consul agents. Invoked by CircleCI post‑Terraform | All VMs, bare‑metal, and initial container images | Inventory sourced from Terraform state via `terraform‑inv` |
| **Puppet Enterprise** | Day‑2 drift remediation & compliance. Runs as agent on VMs and as sidecar for long‑lived containers | Package, file, and service state | Tower playbook triggers Puppet runs via REST API at the end of provisioning; Puppet reports export to Elasticsearch |

> **Key Interaction**: Tower writes a classification Hiera file consumed by Puppet for ongoing policy, avoiding duplication.

## 8. Service Discovery & Networking Mesh

- **Consul Agents** – Deployed via Ansible; register services on VMs & Kubernetes pods using Consul‑K8s sync
- **Consul Connect** – Provides mTLS sidecar proxies (Envoy) enabling zero‑trust east‑west across clouds
- **DNS** – `*.service.consul` domain forwarded from VPC DHCP options / kube‑dns

## 9. Observability

### 9.1 Metrics
- **Prometheus** on every cluster scrapes node, K8s, and application exporters
- **Thanos** sidecars ship metrics to Object Storage (S3, GCS, or Azure Blob) enabling long‑term, global queries
- **Datadog** agent (‑infra focus) and **New Relic** language agents complement Prometheus with deep APM

### 9.2 Logging
- **Fluent Bit** DaemonSets 📤 container logs ➔ **Elasticsearch** (dedicated three‑node hot tier per cloud), replicated with Cross‑Cluster Replication (CCR) to a global cold tier in AWS
- **Kibana** front‑end served via Grafana's Elastic datasource for a single dashboard UI

### 9.3 Visualisation & Alerting
- **Grafana** consumes Thanos, Elasticsearch, Datadog, and New Relic datasources; dashboards versioned via JSONNet in Git
- **Alerts** flow to PagerDuty & Slack via Grafana Alerting and New Relic

## 10. Artifact & Package Management

| Repository | Purpose | Replication |
|------------|---------|-------------|
| **Artifactory** | Internal, signed Docker images; Golden AMIs; proprietary libs | Multisite replication (EU, US, APAC) |
| **Nexus Repo** | Upstream cache for Maven, NPM, PyPI, Go modules, etc. | Read‑only remote repos; no replication needed |

> **Gatekeeping**: only signed images from Artifactory pass Connaisseur admission controller in clusters.

## 11. Security & Compliance

- **AWS GuardDuty**, **Azure Defender**, **GCP Security Command Center** findings forwarded to Elasticsearch SIEM index
- **OPA Gates** block privileged pods; **CIS Benchmarks** enforced by Puppet
- **SAST/DAST** scans tied into CircleCI (OWASP ZAP, Semgrep) with results exported to Prometheus

## 12. Disaster Recovery & High Availability

| Component | HA Strategy | RTO / RPO |
|-----------|-------------|-----------|
| **Terraform State** | Terraform Cloud (SaaS) multi‑region | <15 min / 0 min |
| **Consul** | 3× servers per cloud, quorum tolerant of 1 cloud outage | 5 min / 0 min |
| **Elasticsearch** | CCR + Snapshot to S3 Glacier | 30 min / 5 min |
| **Artifactory** | Active/Active replicas, blob‑store sync | 30 min / 15 min |
| **Vault** | Performance replication + Raft storage | 5 min / 0 min |
| **Thanos** | Object storage geo‑replication | 15 min / 5 min |

## 13. End‑to‑End Workflow Walkthrough

1. **Developer pushes code** ➔ GitHub main
2. **CircleCI**:
   - `terraform plan` (for infra changes) – awaiting approval
   - Build & unit tests
   - Static scans
   - Docker image pushed to Artifactory
3. **Jenkins** nightly job builds legacy artefacts ➔ Nexus
4. **Merge** ➔ Argo CD detects change; syncs Helm chart to EKS prod & GKE prod
5. **Argo Rollouts** performs canary; success promotes full traffic
6. **Consul** registers services; mTLS established
7. **Thanos & Elasticsearch** capture metrics & logs; Grafana alerts on SLO breaches
8. **Puppet** agent enforces drift daily; Ansible only on redeploys

## 14. Reference Implementation Extension (AWS Sample Repo)

- `modules/aws/ecs‑service` from sample augmented with variables for cloud‑agnostic container image URI
- `modules/gcp/gke‑cluster` and `modules/azure/aks‑cluster` replicate network & IAM patterns
- `root/envs/prod/` directory shows three parallel region deployments referencing shared modules
- `ci/` directory includes CircleCI orbs invoking both Terraform and Ansible

## 15. Operations Handbook (Runbooks)

### Scaling
```bash
terraform apply -target=module.aws.eks_nodes ...
```
to adjust desired node groups; Cluster‑Autoscaler manages GKE/AKS/EKS.

### Failover
```bash
thanos query --stores=<backup‑store>
```
to switch dashboards; enable Consul emergency serf join.

### Secret Rotation
Vault's database secrets engine rotates RDS & CloudSQL credentials hourly; Argo CD redeploys pods automatically via annotations.

## 16. Tool Interaction Matrix (High‑Level)

- **Terraform** ➔ **Clouds** – Provision core infra & service IAM roles
- **CircleCI / Jenkins** ➔ **Artifactory / Nexus** – Publish artefacts
- **Argo CD** ➔ **Kubernetes / ECS** – Deploy workloads
- **Ansible (Tower)** ➔ **Consul / OS** – Install & register services
- **Puppet** ➔ **All Hosts** – Ongoing configuration drift remediation
- **Prometheus & Thanos** ⇄ **Grafana** – Visualisation
- **Datadog & New Relic** ⇄ **APM APIs** – Deep tracing
- **Fluent Bit** ➔ **Elasticsearch** – Log aggregation

---

## Getting Started

To deploy this stack:

1. **Prerequisites**: Ensure you have access to AWS, GCP, and Azure accounts
2. **Clone Repository**: `git clone <repo-url>`
3. **Initialize Terraform**: Run `terraform init` in the appropriate environment directory
4. **Configure Variables**: Update `variables.tf` with your specific settings
5. **Deploy**: Follow the deployment guide in `/docs/DEPLOYMENT_GUIDE.md`

For detailed setup instructions, see the documentation in the `/docs` directory.
