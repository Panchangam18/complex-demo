# Zero-Trust Architecture Implementation Plan  
_multicloud edition (AWS · GCP · Azure)_

---

## 0. Guiding Principles

| Pillar | Principle |
|--------|-----------|
| Verify Explicitly | Authenticate & authorize every request based on *identity, context, and risk*. |
| Least-Privilege | Default deny; grant time-bound, scoped access only when needed. |
| Assume Breach | Design controls so compromise of one component does not compromise the rest. |
| Continuous Validation | Telemetry feeds automated policy decisions; revoke trust immediately upon anomaly. |

---

## 1. Network Segmentation Strategy

### 1.1 Macro-Segmentation (per cloud / region)

| Cloud | Recommended Primitive | Implementation Steps |
|-------|----------------------|----------------------|
| AWS   | AWS Transit Gateway + Resource Access Manager | 1. Create isolated VPCs per *trust zone* (prod, non-prod, mgmt).<br>2. Attach to Transit Gateway; restrict route-tables so only approved CIDRs are reachable. |
| GCP   | Shared VPC + VPC-SC | 1. Enable VPC-SC; define *service perimeters* for each trust zone.<br>2. Separate host & service projects; keep centralised firewall in host. |
| Azure | Hub-and-Spoke w/ Azure Firewall & Route Tables | 1. Build dedicated *Hub* vNet with Azure Firewall Premium.<br>2. Spoke vNets per zone; disable transitive peering; route all egress through Firewall. |

### 1.2 Micro-Segmentation (workload / pod level)

* Kubernetes: enforce network policies via **Cilium** (preferred) or Calico (`NetworkPolicy` + eBPF).
* VM / container mesh: **Consul Connect** & **Istio** sidecars enforcing mTLS and L7 intentions.
* Deny-all default, open only necessary ports between namespaces.

---

## 2. Identity & Access Management Improvements

### 2.1 Human Access

* Central IdP = **Azure AD**.  
  * **AWS IAM Identity Center** & **GCP Workforce Identity Federation** trust Azure AD via SAML/OIDC.
* Enforce **MFA** (WebAuthn hardware keys) + Conditional Access (location, device posture).
* Just-In-Time (JIT) privileged access via **Azure PIM**, auto-expire after 1 h.

### 2.2 Workload Identity

| Cloud | Mechanism | IaC Snippet |
|-------|-----------|-------------|
| AWS   | IAM Roles for Service Accounts (IRSA) | `eks_irsa_assume_role_policy` referencing OIDC sub *@k8s.* |
| GCP   | Workload Identity Federation | `workload_identity_pool` + binding to `serviceAccount:${PROJECT}.svc.id.goog[ns/sa]` |
| Azure | Managed Identity | `azurerm_kubernetes_cluster` ➜ `oidc_issuer_enabled = true` |

*Prohibit long-lived access keys. Scan and revoke any in Git history using **git-secrets** hook.*

---

## 3. Device Trust Verification

| Control | Implementation |
|---------|----------------|
| EDR     | Deploy **CrowdStrike Falcon** (or Microsoft Defender) to all endpoints; enforce healthy status in Conditional Access. |
| MDM     | Intune / Kandji to ensure disk encryption, OS patch level, secure boot. |
| Secure Tunnel | **Tailscale** / **Zscaler ZPA** for dev laptops ➜ prohibit direct SSH/RDP; route through identity-aware proxy. |

Enforce access only from *compliant* devices via IdP device compliance claims.

---

## 4. Application Security Controls

1. **Service Mesh mTLS** – mandatory encryption in-transit.
2. **OPA/Gatekeeper** – Kubernetes admission policies (no privileged pods, approved base images SHA).
3. **SCA & SAST in CI** – Trivy, Semgrep; fail build on High/Critical.
4. **Secrets Hygiene** – Use **SealedSecrets** or **External-Secrets Operator** pulling from **Vault**/*AWS Secrets Manager*/GCP Secret Manager/Azure Key Vault*.
5. **Runtime Protection** – **Falco** ruleset for suspicious syscalls; send to SIEM.

---

## 5. Data Protection Measures

| Layer | Control | Tooling |
|-------|---------|---------|
| At Rest | AES-256 encryption keys managed by **KMS** (per cloud).  Enable Customer-Managed Keys (CMK) for S3, GCS, Blob, RDS, CloudSQL & Azure SQL. |
| In-Use | Tokenization or Format-Preserving Encryption for sensitive PII via **Vault Transform**. |
| In-Transit | Enforced by service mesh mTLS; public endpoints use **ACM / Azure Key Vault** issued certs with **TLS 1.3**. |
| DLP | Cloud-native DLP APIs (GCP DLP, Azure Purview, Macie) scanning buckets weekly; quarantine findings. |

---

## 6. Monitoring, Telemetry & Continuous Verification

* **Central SIEM** – Elasticsearch + CCR; ingest GuardDuty, Security Command Center, Azure Defender, Falco, CrowdStrike, OPA audit logs.
* **Behavior Analytics** – Enable `Amazon Detective`, `Azure Sentinel UEBA`, `Chronicle` for anomaly detection.
* **Policy as Code Feedback** –  
  * OPA decision logs ➜ Kafka ➜ Loki/Grafana for real-time dashboards.  
  * Alert on policy *shadow deny* to tune rules.
* **Attack Surface Mgmt** – **Shodan Monitor** & **AWS ECR/CVE scanning** daily.

---

## 7. Implementation Roadmap

| Phase | Timeline | Key Deliverables | Owners |
|-------|----------|------------------|--------|
| **0 – Preparation** | Week 1-2 | • Create Zero-Trust Tiger Team<br>• Baseline asset & trust zone inventory | Security Arch, Cloud Ops |
| **1 – Identity Hardening** | Week 3-5 | • Azure AD MFA + Conditional Access<br>• IRSA / Workload Identity in all clusters | IAM Team |
| **2 – Network Segmentation** | Week 6-9 | • Transit Gateway / Hub-and-Spoke & firewall rules<br>• Cilium network policies default-deny | NetEng |
| **3 – Secrets & Mesh** | Week 10-13 | • Vault deployment & External-Secrets<br>• Consul Connect + Istio mTLS enforced | Platform Eng |
| **4 – Device & Developer Access** | Week 14-16 | • EDR roll-out<br>• Tailscale/ZPA enforced for admin operations | IT Sec |
| **5 – Monitoring & Response** | Week 17-20 | • Unified SIEM pipeline<br>• OPA/Gatekeeper with audit mode ➜ enforce | SecOps |
| **6 – Data Protections** | Week 21-24 | • KMS CMKs applied<br>• DLP pipelines operational | Data Gov |
| **7 – Verification & Red Team** | Week 25-26 | • Breach/Attack Simulation (Atomic Red Team)<br>• Adjust controls, finalize KPIs | Offensive Sec |
| **8 – Continuous Improvement** | Ongoing | • Quarterly policy drift reviews<br>• Monthly CVE patch SLAs | All teams |

**Success Metrics**

* 100 % workloads using short-lived OIDC identities  
* < 5 min automatic revocation upon anomaly detection  
* 0 permissive (`0.0.0.0/0`) SG rules in production  
* ≥ 90 % laptop fleet EDR coverage  
* Mean Time to Mitigate exposed secret < 30 min

---

### Reference Terraform / Helm Modules

* `modules/aws/network/segmentation.tf`
* `modules/opa/policies/*.rego`
* `helm/cilium/values-zero-trust.yaml`
* `helm/consul/connect-strict-mtls.yaml`
* `terraform/modules/vault/transform.tf`

> **Next Step:** Kick-off Phase 0 by approving this plan in the `security-enhancements` pull request and scheduling a Tiger-Team workshop.
