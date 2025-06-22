# Multicloud DevOps Infrastructure

This repository contains the Terraform configuration for a multicloud DevOps platform spanning AWS, GCP, and Azure.

## Directory Structure

```
terraform/
├── modules/           # Reusable Terraform modules
│   ├── aws/          # AWS-specific modules
│   ├── gcp/          # GCP-specific modules
│   └── azure/        # Azure-specific modules
├── envs/             # Environment-specific configurations
│   ├── dev/          # Development environment
│   ├── staging/      # Staging environment
│   └── prod/         # Production environment
├── scripts/          # Helper scripts
├── docs/             # Documentation
└── terragrunt.hcl    # Root Terragrunt configuration
```

## Prerequisites

1. **Install Required Tools:**
   ```bash
   make install-tools
   ```

2. **Configure Cloud Credentials:**
   - AWS: `aws configure` or set `AWS_PROFILE`
   - GCP: `gcloud auth application-default login`
   - Azure: `az login`

3. **Set up Terraform Cloud:**
   - Create an organization in Terraform Cloud
   - Update `terragrunt.hcl` with your organization name
   - Run `terraform login` to authenticate

## Quick Start

1. **Initialize the environment:**
   ```bash
   make init ENV=dev REGION=us-east-2
   ```

2. **Review the plan:**
   ```bash
   make plan ENV=dev REGION=us-east-2
   ```

3. **Apply the configuration:**
   ```bash
   make apply ENV=dev REGION=us-east-2
   ```

## Environment Configuration

Each environment has its own Terragrunt configuration in `envs/<env>/<region>/terragrunt.hcl`. 

### Network CIDR Allocation

Per the multicloud strategy:
- **Global Range:** 10.0.0.0/8
- **Per Cloud:** /16 blocks
  - AWS: 10.0.0.0/16 - 10.15.0.0/16
  - GCP: 10.16.0.0/16 - 10.31.0.0/16
  - Azure: 10.32.0.0/16 - 10.47.0.0/16
- **Per Environment:** Further subdivided
  - Dev: First /18 block
  - Staging: Second /18 block
  - Prod: Third /18 block

## Available Modules

### AWS Modules
- **vpc**: Creates VPC with public, private, and intra subnets
  - Multi-AZ deployment with configurable NAT Gateways
  - VPC Flow Logs for security monitoring
  - Separate route tables for each subnet type

### GCP Modules
- **vpc**: Creates VPC network with regional subnets
  - Public, private, and internal subnet tiers
  - Cloud NAT for outbound connectivity
  - Secondary IP ranges for GKE pods and services
  - VPC Flow Logs enabled by default

### Azure Modules
- **vnet**: Creates Hub VNet following Hub-Spoke pattern
  - Public, private, and internal subnets
  - Optional Gateway, Firewall, and Bastion subnets
  - NAT Gateway for outbound connectivity
  - Network Security Groups with default rules
  - Network Watcher and NSG Flow Logs support

## Makefile Commands

Run `make help` to see all available commands:
- `make init` - Initialize Terraform
- `make plan` - Run Terraform plan
- `make apply` - Apply changes
- `make destroy` - Destroy resources
- `make fmt` - Format code
- `make validate` - Validate configuration
- `make lint` - Run tflint
- `make security-scan` - Run Checkov scan

## Next Steps

1. **Update Cloud Credentials** in `envs/dev/us-east-2/terragrunt.hcl`:
   - Set your GCP project ID
   - Set your Azure subscription ID
   - Set your Terraform Cloud organization

2. **Deploy Base Infrastructure:**
   ```bash
   make apply ENV=dev REGION=us-east-2
   ```

3. **Add More Modules:**
   - Transit Gateway for AWS
   - GCP VPC module
   - Azure VNet module
   - Cross-cloud VPN connections

## Security Considerations

- All state is stored in Terraform Cloud with encryption at rest
- Use OIDC for cloud authentication where possible
- Enable MFA for all cloud accounts
- Follow least-privilege principle for IAM roles

## Contributing

1. Create feature branch from `main`
2. Make changes and test locally
3. Run `make fmt` and `make validate`
4. Submit PR with plan output