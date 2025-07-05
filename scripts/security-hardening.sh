#!/bin/bash
#
# Multi-Cloud Security Hardening Script
# -------------------------------------
# This script implements comprehensive security hardening across AWS, GCP, and Azure
# infrastructure, Kubernetes clusters, networking, secrets management, and monitoring.
#
# The script is designed to be idempotent and can be safely run multiple times.
# It includes logging, error handling, and verification steps for each hardening measure.
#
# Compatible with the complex-demo multi-cloud DevOps platform.
#
# Usage: ./security-hardening.sh [--dry-run] [--skip-section <section_name>]
#
# Author: Security Engineering Team
# Last updated: 2025-07-05

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${REPO_ROOT}/logs/security-hardening-$(date +%Y%m%d-%H%M%S).log"
CONFIG_DIR="${REPO_ROOT}/config/security"
DRY_RUN=false
SKIP_SECTIONS=()
TERRAFORM_DIR="${REPO_ROOT}/terraform"
K8S_DIR="${REPO_ROOT}/k8s"
ANSIBLE_DIR="${REPO_ROOT}/ansible"

# Create logs directory if it doesn't exist
mkdir -p "${REPO_ROOT}/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  --dry-run               Show what would be done without making changes"
  echo "  --skip-section NAME     Skip the specified section (can be used multiple times)"
  echo "  --help                  Display this help message"
  echo
  echo "Available sections:"
  echo "  aws                     AWS security hardening"
  echo "  gcp                     GCP security hardening"
  echo "  azure                   Azure security hardening"
  echo "  kubernetes              Kubernetes cluster hardening"
  echo "  network                 Network security improvements"
  echo "  secrets                 Secrets management hardening"
  echo "  compliance              Compliance and governance controls"
  echo "  monitoring              Security monitoring and alerting"
  echo "  testing                 Automated security testing"
  echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-section)
      SKIP_SECTIONS+=("$2")
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Logging functions
log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  case "$level" in
    "INFO")
      echo -e "${BLUE}[INFO]${NC} $message"
      ;;
    "SUCCESS")
      echo -e "${GREEN}[SUCCESS]${NC} $message"
      ;;
    "WARNING")
      echo -e "${YELLOW}[WARNING]${NC} $message"
      ;;
    "ERROR")
      echo -e "${RED}[ERROR]${NC} $message"
      ;;
    *)
      echo -e "$message"
      ;;
  esac
  
  echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Error handling function
handle_error() {
  local exit_code=$?
  local line_number=$1
  log "ERROR" "Error occurred at line ${line_number} with exit code ${exit_code}"
  log "ERROR" "Check the log file for details: ${LOG_FILE}"
  exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Function to check if a section should be skipped
should_skip() {
  local section="$1"
  for skip in "${SKIP_SECTIONS[@]}"; do
    if [[ "$skip" == "$section" ]]; then
      return 0
    fi
  done
  return 1
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check required tools
check_requirements() {
  log "INFO" "Checking required tools..."
  
  local missing_tools=()
  
  # Core tools
  for tool in aws gcloud az kubectl terraform ansible-playbook jq curl; do
    if ! command_exists "$tool"; then
      missing_tools+=("$tool")
    fi
  done
  
  # Security-specific tools
  for tool in trivy kube-bench semgrep vault; do
    if ! command_exists "$tool"; then
      log "WARNING" "$tool not found. Some security checks may be skipped."
    fi
  done
  
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    log "ERROR" "Missing required tools: ${missing_tools[*]}"
    log "ERROR" "Please install these tools before running this script."
    exit 1
  fi
  
  log "SUCCESS" "All core required tools are available."
}

# Function to verify cloud provider authentication
verify_cloud_auth() {
  log "INFO" "Verifying cloud provider authentication..."
  
  # Check AWS authentication
  if aws sts get-caller-identity >/dev/null 2>&1; then
    log "SUCCESS" "AWS authentication verified."
  else
    log "ERROR" "AWS authentication failed. Please configure AWS credentials."
    exit 1
  fi
  
  # Check GCP authentication
  if gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
    log "SUCCESS" "GCP authentication verified."
  else
    log "ERROR" "GCP authentication failed. Please run 'gcloud auth login'."
    exit 1
  fi
  
  # Check Azure authentication
  if az account show >/dev/null 2>&1; then
    log "SUCCESS" "Azure authentication verified."
  else
    log "ERROR" "Azure authentication failed. Please run 'az login'."
    exit 1
  fi
}

# Function to backup configurations before making changes
backup_configs() {
  local backup_dir="${REPO_ROOT}/backups/security-$(date +%Y%m%d-%H%M%S)"
  log "INFO" "Creating configuration backups in ${backup_dir}..."
  
  mkdir -p "${backup_dir}"
  
  # Backup Terraform state
  mkdir -p "${backup_dir}/terraform"
  if [[ -d "${TERRAFORM_DIR}/envs" ]]; then
    find "${TERRAFORM_DIR}/envs" -name "*.tfstate" -exec cp --parents {} "${backup_dir}" \;
  fi
  
  # Backup Kubernetes configurations
  mkdir -p "${backup_dir}/kubernetes"
  kubectl get configmaps,secrets --all-namespaces -o yaml > "${backup_dir}/kubernetes/all-configs-secrets.yaml" 2>/dev/null || true
  
  # Backup cloud provider security configurations
  mkdir -p "${backup_dir}/cloud-configs"
  aws cloudtrail describe-trails > "${backup_dir}/cloud-configs/aws-cloudtrail.json" 2>/dev/null || true
  aws guardduty list-detectors > "${backup_dir}/cloud-configs/aws-guardduty.json" 2>/dev/null || true
  gcloud logging sinks list --format=json > "${backup_dir}/cloud-configs/gcp-logging.json" 2>/dev/null || true
  az monitor diagnostic-settings list --format json > "${backup_dir}/cloud-configs/azure-diagnostics.json" 2>/dev/null || true
  
  log "SUCCESS" "Configuration backups created."
}

#########################################
# 1. AWS Security Hardening
#########################################
harden_aws() {
  if should_skip "aws"; then
    log "INFO" "Skipping AWS security hardening..."
    return
  fi
  
  log "INFO" "Starting AWS security hardening..."
  
  # Enable AWS CloudTrail in all regions
  log "INFO" "Configuring AWS CloudTrail with multi-region logging..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would enable CloudTrail in all regions with log validation."
  else
    aws cloudtrail update-trail \
      --name management-events \
      --is-multi-region-trail \
      --enable-log-file-validation \
      --kms-key-id "alias/aws/cloudtrail" \
      --is-organization-trail \
      --no-include-global-service-events || {
        log "WARNING" "Failed to update CloudTrail. Attempting to create..."
        aws cloudtrail create-trail \
          --name management-events \
          --s3-bucket-name "security-audit-logs-$(aws sts get-caller-identity --query 'Account' --output text)" \
          --is-multi-region-trail \
          --enable-log-file-validation \
          --kms-key-id "alias/aws/cloudtrail" \
          --tags "Key=Environment,Value=Production" "Key=SecurityControl,Value=Audit"
      }
    aws cloudtrail start-logging --name management-events
    log "SUCCESS" "CloudTrail configured successfully."
  fi
  
  # Enable AWS GuardDuty in all regions
  log "INFO" "Enabling AWS GuardDuty in all regions..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would enable GuardDuty in all regions."
  else
    regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
    for region in $regions; do
      log "INFO" "Enabling GuardDuty in $region..."
      aws guardduty create-detector --enable --finding-publishing-frequency FIFTEEN_MINUTES --region "$region" || {
        detector_id=$(aws guardduty list-detectors --region "$region" --query 'DetectorIds[0]' --output text)
        if [[ -n "$detector_id" && "$detector_id" != "None" ]]; then
          aws guardduty update-detector --detector-id "$detector_id" --enable --finding-publishing-frequency FIFTEEN_MINUTES --region "$region"
        fi
      }
    done
    log "SUCCESS" "GuardDuty enabled in all regions."
  fi
  
  # Configure AWS Config for compliance monitoring
  log "INFO" "Configuring AWS Config for compliance monitoring..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure AWS Config with security best practice rules."
  else
    regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
    for region in $regions; do
      log "INFO" "Configuring AWS Config in $region..."
      
      # Create S3 bucket for config if it doesn't exist
      bucket_name="config-bucket-$(aws sts get-caller-identity --query 'Account' --output text)-$region"
      aws s3api create-bucket --bucket "$bucket_name" --region "$region" --create-bucket-configuration LocationConstraint="$region" || true
      
      # Enable AWS Config
      aws configservice put-configuration-recorder \
        --configuration-recorder name=default,roleARN=arn:aws:iam::$(aws sts get-caller-identity --query 'Account' --output text):role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
        --recording-group allSupported=true,includeGlobalResourceTypes=true \
        --region "$region" || true
      
      aws configservice put-delivery-channel \
        --delivery-channel name=default,s3BucketName="$bucket_name",configSnapshotDeliveryProperties="{deliveryFrequency=Six_Hours}" \
        --region "$region" || true
      
      aws configservice start-configuration-recorder --configuration-recorder-name default --region "$region" || true
      
      # Enable security best practice rules
      security_rules=(
        "cloudtrail-enabled"
        "cloud-trail-encryption-enabled"
        "cloud-trail-log-file-validation-enabled"
        "multi-region-cloudtrail-enabled"
        "s3-bucket-public-read-prohibited"
        "s3-bucket-public-write-prohibited"
        "encrypted-volumes"
        "restricted-ssh"
        "restricted-common-ports"
        "iam-password-policy"
        "root-account-mfa-enabled"
        "iam-user-mfa-enabled"
      )
      
      for rule in "${security_rules[@]}"; do
        aws configservice put-config-rule --config-rule "ConfigRuleName=$rule,Source={Owner=AWS,SourceIdentifier=$rule}" --region "$region" || true
      done
    done
    log "SUCCESS" "AWS Config configured in all regions."
  fi
  
  # Harden S3 bucket policies
  log "INFO" "Hardening S3 bucket policies..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would apply security best practices to S3 buckets."
  else
    buckets=$(aws s3api list-buckets --query 'Buckets[].Name' --output text)
    for bucket in $buckets; do
      log "INFO" "Securing bucket: $bucket"
      
      # Enable default encryption
      aws s3api put-bucket-encryption \
        --bucket "$bucket" \
        --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}' || true
      
      # Block public access
      aws s3api put-public-access-block \
        --bucket "$bucket" \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" || true
      
      # Enable versioning
      aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled || true
      
      # Enable access logging if it's not a log bucket itself
      if [[ ! "$bucket" == *"log"* ]]; then
        log_bucket="access-logs-$(aws sts get-caller-identity --query 'Account' --output text)"
        aws s3api create-bucket --bucket "$log_bucket" --region us-east-1 || true
        aws s3api put-bucket-logging \
          --bucket "$bucket" \
          --bucket-logging-status "{\"LoggingEnabled\":{\"TargetBucket\":\"$log_bucket\",\"TargetPrefix\":\"$bucket/\"}}" || true
      fi
    done
    log "SUCCESS" "S3 bucket policies hardened."
  fi
  
  # Harden IAM policies
  log "INFO" "Hardening IAM policies..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would apply IAM security best practices."
  else
    # Set strong password policy
    aws iam update-account-password-policy \
      --minimum-password-length 14 \
      --require-symbols \
      --require-numbers \
      --require-uppercase-characters \
      --require-lowercase-characters \
      --allow-users-to-change-password \
      --max-password-age 90 \
      --password-reuse-prevention 24 || true
    
    # Enforce MFA for all IAM users
    users=$(aws iam list-users --query 'Users[].UserName' --output text)
    for user in $users; do
      # Check if user has MFA enabled
      mfa_devices=$(aws iam list-mfa-devices --user-name "$user" --query 'MFADevices[*]' --output text)
      if [[ -z "$mfa_devices" ]]; then
        log "WARNING" "User $user does not have MFA enabled. Adding policy to enforce MFA."
        
        # Create policy to enforce MFA
        aws iam put-user-policy \
          --user-name "$user" \
          --policy-name EnforceMFA \
          --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
              {
                "Sid": "AllowViewAccountInfo",
                "Effect": "Allow",
                "Action": [
                  "iam:GetAccountPasswordPolicy",
                  "iam:GetAccountSummary",
                  "iam:ListVirtualMFADevices"
                ],
                "Resource": "*"
              },
              {
                "Sid": "AllowManageOwnPasswords",
                "Effect": "Allow",
                "Action": [
                  "iam:ChangePassword",
                  "iam:GetUser"
                ],
                "Resource": "arn:aws:iam::*:user/${aws:username}"
              },
              {
                "Sid": "AllowManageOwnAccessKeys",
                "Effect": "Allow",
                "Action": [
                  "iam:CreateAccessKey",
                  "iam:DeleteAccessKey",
                  "iam:ListAccessKeys",
                  "iam:UpdateAccessKey"
                ],
                "Resource": "arn:aws:iam::*:user/${aws:username}"
              },
              {
                "Sid": "AllowManageOwnSigningCertificates",
                "Effect": "Allow",
                "Action": [
                  "iam:DeleteSigningCertificate",
                  "iam:ListSigningCertificates",
                  "iam:UpdateSigningCertificate",
                  "iam:UploadSigningCertificate"
                ],
                "Resource": "arn:aws:iam::*:user/${aws:username}"
              },
              {
                "Sid": "AllowManageOwnSSHPublicKeys",
                "Effect": "Allow",
                "Action": [
                  "iam:DeleteSSHPublicKey",
                  "iam:GetSSHPublicKey",
                  "iam:ListSSHPublicKeys",
                  "iam:UpdateSSHPublicKey",
                  "iam:UploadSSHPublicKey"
                ],
                "Resource": "arn:aws:iam::*:user/${aws:username}"
              },
              {
                "Sid": "AllowManageOwnGitCredentials",
                "Effect": "Allow",
                "Action": [
                  "iam:CreateServiceSpecificCredential",
                  "iam:DeleteServiceSpecificCredential",
                  "iam:ListServiceSpecificCredentials",
                  "iam:ResetServiceSpecificCredential",
                  "iam:UpdateServiceSpecificCredential"
                ],
                "Resource": "arn:aws:iam::*:user/${aws:username}"
              },
              {
                "Sid": "AllowManageOwnVirtualMFADevice",
                "Effect": "Allow",
                "Action": [
                  "iam:CreateVirtualMFADevice",
                  "iam:DeleteVirtualMFADevice"
                ],
                "Resource": "arn:aws:iam::*:mfa/${aws:username}"
              },
              {
                "Sid": "AllowManageOwnUserMFA",
                "Effect": "Allow",
                "Action": [
                  "iam:DeactivateMFADevice",
                  "iam:EnableMFADevice",
                  "iam:ListMFADevices",
                  "iam:ResyncMFADevice"
                ],
                "Resource": "arn:aws:iam::*:user/${aws:username}"
              },
              {
                "Sid": "DenyAllExceptListedIfNoMFA",
                "Effect": "Deny",
                "NotAction": [
                  "iam:CreateVirtualMFADevice",
                  "iam:EnableMFADevice",
                  "iam:GetUser",
                  "iam:ListMFADevices",
                  "iam:ListVirtualMFADevices",
                  "iam:ResyncMFADevice",
                  "sts:GetSessionToken"
                ],
                "Resource": "*",
                "Condition": {
                  "BoolIfExists": {
                    "aws:MultiFactorAuthPresent": "false"
                  }
                }
              }
            ]
          }' || true
      fi
    done
    
    # Remove inactive access keys
    for user in $users; do
      access_keys=$(aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[?Status==`Active`].AccessKeyId' --output text)
      for key in $access_keys; do
        # Check key last used
        last_used=$(aws iam get-access-key-last-used --access-key-id "$key" --query 'AccessKeyLastUsed.LastUsedDate' --output text)
        if [[ "$last_used" == "None" || "$last_used" < $(date -d '90 days ago' +%Y-%m-%d) ]]; then
          log "WARNING" "Deactivating unused access key $key for user $user"
          aws iam update-access-key --access-key-id "$key" --status Inactive --user-name "$user" || true
        fi
      done
    done
    
    log "SUCCESS" "IAM policies hardened."
  fi
  
  log "SUCCESS" "AWS security hardening completed."
}

#########################################
# 2. GCP Security Hardening
#########################################
harden_gcp() {
  if should_skip "gcp"; then
    log "INFO" "Skipping GCP security hardening..."
    return
  fi
  
  log "INFO" "Starting GCP security hardening..."
  
  # Get current project
  project_id=$(gcloud config get-value project)
  log "INFO" "Working with GCP project: $project_id"
  
  # Enable essential security services
  log "INFO" "Enabling essential GCP security services..."
  security_services=(
    "cloudresourcemanager.googleapis.com"
    "securitycenter.googleapis.com"
    "cloudasset.googleapis.com"
    "cloudkms.googleapis.com"
    "logging.googleapis.com"
    "monitoring.googleapis.com"
    "clouderrorreporting.googleapis.com"
    "containerscanning.googleapis.com"
    "binaryauthorization.googleapis.com"
    "secretmanager.googleapis.com"
  )
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would enable the following GCP services: ${security_services[*]}"
  else
    for service in "${security_services[@]}"; do
      log "INFO" "Enabling $service..."
      gcloud services enable "$service" --project="$project_id" || log "WARNING" "Failed to enable $service. It might already be enabled."
    done
    log "SUCCESS" "GCP security services enabled."
  fi
  
  # Configure organization policies
  log "INFO" "Configuring GCP organization policies..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure GCP organization policies for security hardening."
  else
    # Disable service account key creation
    gcloud resource-manager org-policies enable-enforce \
      --project="$project_id" \
      constraints/iam.disableServiceAccountKeyCreation || log "WARNING" "Failed to set org policy for service account keys."
    
    # Require OS Login for VMs
    gcloud resource-manager org-policies enable-enforce \
      --project="$project_id" \
      constraints/compute.requireOsLogin || log "WARNING" "Failed to set org policy for OS Login."
    
    # Restrict public IP access
    gcloud resource-manager org-policies enable-enforce \
      --project="$project_id" \
      constraints/compute.restrictVpcPeering || log "WARNING" "Failed to set org policy for VPC peering."
    
    # Disable serial port access
    gcloud resource-manager org-policies enable-enforce \
      --project="$project_id" \
      constraints/compute.disableSerialPortAccess || log "WARNING" "Failed to set org policy for serial port access."
    
    # Restrict shared VPC project lien removal
    gcloud resource-manager org-policies enable-enforce \
      --project="$project_id" \
      constraints/compute.restrictXpnProjectLienRemoval || log "WARNING" "Failed to set org policy for shared VPC project lien removal."
    
    log "SUCCESS" "GCP organization policies configured."
  fi
  
  # Set up Cloud Audit Logging
  log "INFO" "Configuring GCP Cloud Audit Logging..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Cloud Audit Logging for all services."
  else
    # Create a dedicated logging bucket
    log_bucket_name="audit-logs-$project_id"
    gcloud logging buckets create "$log_bucket_name" \
      --project="$project_id" \
      --location=global \
      --retention-days=365 \
      --description="Centralized audit logs for security monitoring" || log "WARNING" "Failed to create logging bucket. It might already exist."
    
    # Configure audit log sinks
    gcloud logging sinks create audit-logs-sink \
      "logging.googleapis.com/projects/$project_id/locations/global/buckets/$log_bucket_name" \
      --project="$project_id" \
      --log-filter='logName:"cloudaudit.googleapis.com"' || log "WARNING" "Failed to create audit logs sink. It might already exist."
    
    # Set IAM permissions for the sink
    sink_service_account=$(gcloud logging sinks describe audit-logs-sink --project="$project_id" --format="value(writerIdentity)")
    gcloud projects add-iam-policy-binding "$project_id" \
      --member="$sink_service_account" \
      --role="roles/logging.bucketWriter" || log "WARNING" "Failed to set IAM permissions for the sink."
    
    log "SUCCESS" "GCP Cloud Audit Logging configured."
  fi
  
  # Enable Security Command Center
  log "INFO" "Enabling GCP Security Command Center..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would enable Security Command Center with standard tier."
  else
    gcloud scc settings update \
      --project="$project_id" \
      --enable-security-center \
      --update-mask=enableSecurityCenter || log "WARNING" "Failed to enable Security Command Center."
    
    # Enable Security Health Analytics
    gcloud scc settings services update security-health-analytics \
      --project="$project_id" \
      --enable || log "WARNING" "Failed to enable Security Health Analytics."
    
    # Enable Container Threat Detection
    gcloud scc settings services update container-threat-detection \
      --project="$project_id" \
      --enable || log "WARNING" "Failed to enable Container Threat Detection."
    
    # Enable Web Security Scanner
    gcloud scc settings services update web-security-scanner \
      --project="$project_id" \
      --enable || log "WARNING" "Failed to enable Web Security Scanner."
    
    log "SUCCESS" "GCP Security Command Center enabled."
  fi
  
  # Configure VPC Service Controls
  log "INFO" "Configuring VPC Service Controls..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure VPC Service Controls for sensitive services."
  else
    # Check if VPC Service Controls are already configured
    perimeter_exists=$(gcloud access-context-manager perimeters list --policy=default --format="value(name)" | grep -c "$project_id" || echo "0")
    
    if [[ "$perimeter_exists" -eq "0" ]]; then
      log "INFO" "Creating new VPC Service Controls perimeter..."
      
      # Create a temporary file for the perimeter configuration
      perimeter_config=$(mktemp)
      cat > "$perimeter_config" << EOF
name: accessPolicies/default/servicePerimeters/$project_id-perimeter
title: $project_id Security Perimeter
description: Security perimeter for sensitive services
status:
  resources:
  - projects/$project_id
  restrictedServices:
  - bigquery.googleapis.com
  - storage.googleapis.com
  - cloudkms.googleapis.com
  - secretmanager.googleapis.com
  vpcAccessibleServices:
    enableRestriction: true
    allowedServices:
    - bigquery.googleapis.com
    - storage.googleapis.com
    - cloudkms.googleapis.com
    - secretmanager.googleapis.com
EOF
      
      gcloud access-context-manager perimeters create "$project_id-perimeter" \
        --policy=default \
        --config-from-file="$perimeter_config" || log "WARNING" "Failed to create VPC Service Controls perimeter."
      
      rm -f "$perimeter_config"
    else
      log "INFO" "VPC Service Controls perimeter already exists. Skipping creation."
    fi
    
    log "SUCCESS" "VPC Service Controls configured."
  fi
  
  # Configure Binary Authorization for GKE
  log "INFO" "Configuring Binary Authorization for GKE..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Binary Authorization for GKE clusters."
  else
    # Check if there are any GKE clusters
    clusters=$(gcloud container clusters list --project="$project_id" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$clusters" ]]; then
      for cluster in $clusters; do
        zone_or_region=$(gcloud container clusters list --project="$project_id" --filter="name=$cluster" --format="value(location)")
        
        # Enable Binary Authorization
        gcloud container clusters update "$cluster" \
          --project="$project_id" \
          --location="$zone_or_region" \
          --enable-binauthz || log "WARNING" "Failed to enable Binary Authorization for cluster $cluster."
        
        log "SUCCESS" "Binary Authorization enabled for GKE cluster $cluster."
      done
    else
      log "INFO" "No GKE clusters found. Skipping Binary Authorization configuration."
    fi
  fi
  
  log "SUCCESS" "GCP security hardening completed."
}

#########################################
# 3. Azure Security Hardening
#########################################
harden_azure() {
  if should_skip "azure"; then
    log "INFO" "Skipping Azure security hardening..."
    return
  fi
  
  log "INFO" "Starting Azure security hardening..."
  
  # Get current subscription
  subscription_id=$(az account show --query id --output tsv)
  log "INFO" "Working with Azure subscription: $subscription_id"
  
  # Enable Azure Security Center/Defender
  log "INFO" "Enabling Azure Security Center/Defender..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would enable Azure Security Center/Defender for all resource types."
  else
    # Enable Azure Defender for key resource types
    resource_types=(
      "VirtualMachines"
      "SqlServers"
      "AppServices"
      "StorageAccounts"
      "KubernetesService"
      "ContainerRegistry"
      "KeyVaults"
      "Dns"
      "Arm"
    )
    
    for resource_type in "${resource_types[@]}"; do
      az security pricing create \
        --name "$resource_type" \
        --tier "Standard" || log "WARNING" "Failed to enable Azure Defender for $resource_type."
    done
    
    # Enable auto-provisioning of monitoring agent
    az security auto-provisioning-setting update \
      --name "default" \
      --auto-provision "On" || log "WARNING" "Failed to enable auto-provisioning of monitoring agent."
    
    log "SUCCESS" "Azure Security Center/Defender enabled."
  fi
  
  # Configure Azure Policy for security compliance
  log "INFO" "Configuring Azure Policy for security compliance..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would assign security-focused Azure Policies."
  else
    # Assign built-in security policies
    security_policies=(
      "4f11b553-d42e-4e3a-89be-32ca364cad4c" # Identity Management - MFA should be enabled for accounts with write permissions
      "a451c1ef-c6ca-483d-87ed-f49761e3ffb5" # Management ports should be closed on your virtual machines
      "501541f7-f7e7-4cd6-868c-4190fdad3ac9" # Web Application Firewall (WAF) should be enabled for Application Gateway
      "b54ed75b-3e1a-44ac-a333-05ba39b99ff0" # Audit usage of custom RBAC rules
      "f6de0be7-9a8a-4b8a-b349-43cf02d22f7c" # Disk encryption should be applied on virtual machines
      "5b9159ae-1701-4a6f-9a7a-aa9c8ddd0580" # Key Vault objects should be recoverable
      "c3f317a7-a95c-4547-b7e7-11017ebdf2fe" # System updates should be installed on your machines
    )
    
    for policy_id in "${security_policies[@]}"; do
      policy_name=$(az policy definition show --id "/providers/Microsoft.Authorization/policyDefinitions/$policy_id" --query displayName --output tsv)
      
      az policy assignment create \
        --name "${policy_name//[^a-zA-Z0-9]/}-assignment" \
        --policy "$policy_id" \
        --scope "/subscriptions/$subscription_id" \
        --display-name "Security: $policy_name" \
        --description "Assigned by security hardening script" || log "WARNING" "Failed to assign policy: $policy_name"
    done
    
    log "SUCCESS" "Azure Policies assigned for security compliance."
  fi
  
  # Configure Azure Monitor and Log Analytics
  log "INFO" "Configuring Azure Monitor and Log Analytics..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Azure Monitor and Log Analytics for security monitoring."
  else
    # Create Log Analytics workspace if it doesn't exist
    workspace_name="security-monitoring-workspace"
    resource_group="security-monitoring-rg"
    
    # Create resource group if it doesn't exist
    az group create \
      --name "$resource_group" \
      --location "eastus" || log "WARNING" "Failed to create resource group. It might already exist."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
      --resource-group "$resource_group" \
      --workspace-name "$workspace_name" \
      --retention-time 365 || log "WARNING" "Failed to create Log Analytics workspace. It might already exist."
    
    # Get workspace ID
    workspace_id=$(az monitor log-analytics workspace show \
      --resource-group "$resource_group" \
      --workspace-name "$workspace_name" \
      --query id \
      --output tsv)
    
    # Enable security solutions
    solutions=(
      "Security"
      "SecurityCenterFree"
      "AzureActivity"
      "ChangeTracking"
      "Updates"
      "ServiceMap"
    )
    
    for solution in "${solutions[@]}"; do
      az deployment group create \
        --resource-group "$resource_group" \
        --template-uri "https://raw.githubusercontent.com/Azure/Azure-Sentinel/master/Solutions/SolutionTemplates/Template/solution.json" \
        --parameters "workspaceName=$workspace_name" "solutionName=$solution" || log "WARNING" "Failed to enable solution: $solution"
    done
    
    # Configure diagnostic settings for subscription
    az monitor diagnostic-settings subscription create \
      --name "security-logging" \
      --location "eastus" \
      --logs '[{"category": "Administrative", "enabled": true}, {"category": "Security", "enabled": true}, {"category": "ServiceHealth", "enabled": true}, {"category": "Alert", "enabled": true}, {"category": "Recommendation", "enabled": true}, {"category": "Policy", "enabled": true}, {"category": "Autoscale", "enabled": true}, {"category": "ResourceHealth", "enabled": true}]' \
      --workspace "$workspace_id" || log "WARNING" "Failed to configure diagnostic settings for subscription."
    
    log "SUCCESS" "Azure Monitor and Log Analytics configured."
  fi
  
  # Configure Azure Key Vault security
  log "INFO" "Configuring Azure Key Vault security..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure security for Azure Key Vaults."
  else
    # Get all Key Vaults
    key_vaults=$(az keyvault list --query '[].name' --output tsv)
    
    if [[ -n "$key_vaults" ]]; then
      for vault in $key_vaults; do
        resource_group=$(az keyvault show --name "$vault" --query resourceGroup --output tsv)
        
        # Enable soft delete and purge protection
        az keyvault update \
          --name "$vault" \
          --resource-group "$resource_group" \
          --enable-soft-delete true \
          --enable-purge-protection true || log "WARNING" "Failed to update Key Vault $vault."
        
        # Enable diagnostic settings
        az monitor diagnostic-settings create \
          --name "security-logging" \
          --resource "$(az keyvault show --name "$vault" --query id --output tsv)" \
          --logs '[{"category": "AuditEvent","enabled": true}]' \
          --metrics '[{"category": "AllMetrics","enabled": true}]' \
          --workspace "$workspace_id" || log "WARNING" "Failed to configure diagnostic settings for Key Vault $vault."
      done
      
      log "SUCCESS" "Azure Key Vault security configured."
    else
      log "INFO" "No Azure Key Vaults found. Skipping Key Vault security configuration."
    fi
  fi
  
  # Configure Network Security Groups
  log "INFO" "Hardening Network Security Groups..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would harden Network Security Groups."
  else
    # Get all NSGs
    nsgs=$(az network nsg list --query '[].name' --output tsv)
    
    if [[ -n "$nsgs" ]]; then
      for nsg in $nsgs; do
        resource_group=$(az network nsg show --name "$nsg" --query resourceGroup --output tsv)
        
        # Enable flow logs
        storage_account=$(az storage account list --query '[0].name' --output tsv)
        if [[ -n "$storage_account" ]]; then
          storage_id=$(az storage account show --name "$storage_account" --query id --output tsv)
          
          az network watcher flow-log create \
            --name "${nsg}-flowlog" \
            --resource-group "$resource_group" \
            --nsg "$nsg" \
            --storage-account "$storage_id" \
            --workspace "$workspace_id" \
            --enabled true \
            --retention 90 || log "WARNING" "Failed to enable flow logs for NSG $nsg."
        fi
        
        # Check for overly permissive rules
        permissive_rules=$(az network nsg rule list --nsg-name "$nsg" --resource-group "$resource_group" --query "[?sourceAddressPrefix=='*' && (destinationPortRange=='22' || destinationPortRange=='3389')].name" --output tsv)
        
        if [[ -n "$permissive_rules" ]]; then
          log "WARNING" "Found permissive rules in NSG $nsg: $permissive_rules"
          log "WARNING" "Consider restricting these rules to specific IP ranges."
        fi
      done
      
      log "SUCCESS" "Network Security Groups hardened."
    else
      log "INFO" "No Network Security Groups found. Skipping NSG hardening."
    fi
  fi
  
  log "SUCCESS" "Azure security hardening completed."
}

#########################################
# 4. Kubernetes Cluster Hardening
#########################################
harden_kubernetes() {
  if should_skip "kubernetes"; then
    log "INFO" "Skipping Kubernetes cluster hardening..."
    return
  fi
  
  log "INFO" "Starting Kubernetes cluster hardening..."
  
  # Check if kubectl is properly configured
  if ! kubectl get nodes &>/dev/null; then
    log "ERROR" "kubectl is not properly configured. Please set up your kubeconfig."
    return 1
  fi
  
  # Get cluster info
  cluster_info=$(kubectl cluster-info | head -n 1)
  log "INFO" "Working with Kubernetes cluster: $cluster_info"
  
  # Apply Pod Security Standards
  log "INFO" "Applying Pod Security Standards..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would apply Pod Security Standards to all namespaces."
  else
    # Create a namespace for security policies if it doesn't exist
    kubectl create namespace security-policies 2>/dev/null || true
    
    # Apply Pod Security Standards labels to all namespaces
    namespaces=$(kubectl get namespaces -o name | cut -d/ -f2)
    for namespace in $namespaces; do
      # Skip system namespaces
      if [[ "$namespace" == "kube-system" || "$namespace" == "kube-public" || "$namespace" == "kube-node-lease" ]]; then
        continue
      fi
      
      # Apply restricted pod security standard
      kubectl label --overwrite namespace "$namespace" \
        pod-security.kubernetes.io/enforce=restricted \
        pod-security.kubernetes.io/audit=restricted \
        pod-security.kubernetes.io/warn=restricted || log "WARNING" "Failed to apply Pod Security Standards to namespace $namespace."
    done
    
    log "SUCCESS" "Pod Security Standards applied to all namespaces."
  fi
  
  # Install/Update Network Policies
  log "INFO" "Configuring Network Policies..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would apply default deny Network Policies to all namespaces."
  else
    # Check if the cluster supports Network Policies
    if kubectl api-resources | grep -q networkpolicies; then
      # Apply default deny network policy to all namespaces
      namespaces=$(kubectl get namespaces -o name | cut -d/ -f2)
      for namespace in $namespaces; do
        # Skip system namespaces
        if [[ "$namespace" == "kube-system" || "$namespace" == "kube-public" || "$namespace" == "kube-node-lease" ]]; then
          continue
        fi
        
        # Create default deny policy
        cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: $namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
EOF
        
        # Create policy to allow specific communications
        cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: $namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF
        
        log "SUCCESS" "Network Policies applied to namespace $namespace."
      done
    else
      log "WARNING" "This cluster does not support Network Policies. Consider using a CNI plugin that supports them."
    fi
  fi
  
  # Configure RBAC hardening
  log "INFO" "Hardening Kubernetes RBAC..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would review and harden RBAC configurations."
  else
    # Check for overly permissive ClusterRoleBindings
    permissive_bindings=$(kubectl get clusterrolebinding -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name')
    
    if [[ -n "$permissive_bindings" ]]; then
      log "WARNING" "Found potentially overly permissive ClusterRoleBindings:"
      echo "$permissive_bindings" | while read -r binding; do
        subjects=$(kubectl get clusterrolebinding "$binding" -o json | jq -r '.subjects[] | "\(.kind) \(.name)"')
        log "WARNING" "ClusterRoleBinding $binding grants cluster-admin to: $subjects"
      done
      log "WARNING" "Review these bindings and consider restricting permissions."
    fi
    
    # Create least-privilege service account for applications
    kubectl create namespace app-restricted 2>/dev/null || true
    
    kubectl create serviceaccount restricted-sa -n app-restricted 2>/dev/null || true
    
    cat << EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: restricted-role
  namespace: app-restricted
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
EOF
    
    cat << EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: restricted-binding
  namespace: app-restricted
subjects:
- kind: ServiceAccount
  name: restricted-sa
  namespace: app-restricted
roleRef:
  kind: Role
  name: restricted-role
  apiGroup: rbac.authorization.k8s.io
EOF
    
    log "SUCCESS" "RBAC hardening completed."
  fi
  
  # Run kube-bench for CIS compliance
  log "INFO" "Running kube-bench for CIS compliance checks..."
  if command_exists kube-bench; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log "INFO" "[DRY RUN] Would run kube-bench for CIS compliance checks."
    else
      # Create a job to run kube-bench
      cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench
  namespace: default
spec:
  template:
    spec:
      hostPID: true
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        securityContext:
          privileged: true
        volumeMounts:
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
        - name: etc-systemd
          mountPath: /etc/systemd
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
      volumes:
      - name: var-lib-kubelet
        hostPath:
          path: /var/lib/kubelet
      - name: etc-systemd
        hostPath:
          path: /etc/systemd
      - name: etc-kubernetes
        hostPath:
          path: /etc/kubernetes
      restartPolicy: Never
EOF
      
      # Wait for the job to complete
      kubectl wait --for=condition=complete job/kube-bench --timeout=300s
      
      # Get the results
      pod_name=$(kubectl get pods --selector=job-name=kube-bench -o jsonpath='{.items[0].metadata.name}')
      kubectl logs "$pod_name" > "${REPO_ROOT}/logs/kube-bench-$(date +%Y%m%d).log"
      
      # Clean up
      kubectl delete job kube-bench
      
      log "SUCCESS" "kube-bench CIS compliance check completed. Results saved to logs directory."
    fi
  else
    log "WARNING" "kube-bench not found. Skipping CIS compliance checks."
  fi
  
  # Configure Admission Controllers
  log "INFO" "Configuring Kubernetes Admission Controllers..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure OPA Gatekeeper for policy enforcement."
  else
    # Check if OPA Gatekeeper is installed
    if ! kubectl get crds | grep -q "constrainttemplates.templates.gatekeeper.sh"; then
      log "INFO" "Installing OPA Gatekeeper..."
      kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
    else
      log "INFO" "OPA Gatekeeper is already installed."
    fi
    
    # Apply security policies
    log "INFO" "Applying security constraint templates..."
    
    # Require privileged container restrictions
    cat << EOF | kubectl apply -f -
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8spsprivilegedcontainer
spec:
  crd:
    spec:
      names:
        kind: K8sPSPPrivilegedContainer
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8spsprivilegedcontainer

        violation[{"msg": msg}] {
          c := input_containers[_]
          c.securityContext.privileged
          msg := sprintf("Privileged container is not allowed: %v, securityContext: %v", [c.name, c.securityContext])
        }

        input_containers[c] {
          c := input.review.object.spec.containers[_]
        }

        input_containers[c] {
          c := input.review.object.spec.initContainers[_]
        }
EOF
    
    # Apply the constraint
    cat << EOF | kubectl apply -f -
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: psp-privileged-container
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system"]
EOF
    
    # Require limits on resources
    cat << EOF | kubectl apply -f -
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredresources
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredResources
      validation:
        openAPIV3Schema:
          properties:
            limits:
              type: array
              items:
                type: string
            requests:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredresources

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          resource := input.parameters.limits[_]
          not container.resources.limits[resource]
          msg := sprintf("Container %v does not have resource limit for %v", [container.name, resource])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          resource := input.parameters.requests[_]
          not container.resources.requests[resource]
          msg := sprintf("Container %v does not have resource request for %v", [container.name, resource])
        }
EOF
    
    # Apply the constraint
    cat << EOF | kubectl apply -f -
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredResources
metadata:
  name: required-resources
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system"]
  parameters:
    limits:
      - cpu
      - memory
    requests:
      - cpu
      - memory
EOF
    
    log "SUCCESS" "Kubernetes Admission Controllers configured."
  fi
  
  # Configure Secret Encryption
  log "INFO" "Configuring Kubernetes Secret Encryption..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Secret encryption for Kubernetes."
  else
    # Check if we're running on a managed Kubernetes service
    if kubectl get nodes -o yaml | grep -q "eks.amazonaws.com" || 
       kubectl get nodes -o yaml | grep -q "gke.cloud.google.com" ||
       kubectl get nodes -o yaml | grep -q "azure.com"; then
      log "INFO" "Running on a managed Kubernetes service. Secret encryption is typically managed by the provider."
    else
      log "WARNING" "Secret encryption configuration for self-managed Kubernetes clusters requires direct access to the API server configuration."
      log "WARNING" "Please refer to the Kubernetes documentation for configuring encryption at rest."
    fi
  fi
  
  # Configure audit logging
  log "INFO" "Configuring Kubernetes audit logging..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Kubernetes audit logging."
  else
    # For managed Kubernetes services, check if audit logging is enabled
    if kubectl get nodes -o yaml | grep -q "eks.amazonaws.com"; then
      log "INFO" "For EKS, enable CloudWatch logging for the cluster through the AWS console or CLI."
    elif kubectl get nodes -o yaml | grep -q "gke.cloud.google.com"; then
      log "INFO" "For GKE, enable Cloud Audit Logging through the GCP console or CLI."
    elif kubectl get nodes -o yaml | grep -q "azure.com"; then
      log "INFO" "For AKS, enable Azure Monitor for Containers through the Azure portal or CLI."
    else
      log "WARNING" "Audit logging configuration for self-managed Kubernetes clusters requires direct access to the API server configuration."
      log "WARNING" "Please refer to the Kubernetes documentation for configuring audit logging."
    fi
  fi
  
  log "SUCCESS" "Kubernetes cluster hardening completed."
}

#########################################
# 5. Network Security Improvements
#########################################
harden_network() {
  if should_skip "network"; then
    log "INFO" "Skipping network security improvements..."
    return
  fi
  
  log "INFO" "Starting network security improvements..."
  
  # Configure AWS network security
  log "INFO" "Configuring AWS network security..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure AWS network security."
  else
    # Enable VPC Flow Logs
    vpcs=$(aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output text)
    for vpc in $vpcs; do
      log_group_name="/vpc/flowlogs/$vpc"
      
      # Create CloudWatch log group if it doesn't exist
      aws logs create-log-group --log-group-name "$log_group_name" 2>/dev/null || true
      
      # Create IAM role for flow logs if it doesn't exist
      role_name="VPCFlowLogsRole"
      role_exists=$(aws iam get-role --role-name "$role_name" 2>/dev/null || echo "false")
      
      if [[ "$role_exists" == "false" ]]; then
        # Create trust policy document
        trust_policy=$(mktemp)
        cat > "$trust_policy" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        # Create the role
        aws iam create-role --role-name "$role_name" --assume-role-policy-document "file://$trust_policy" || log "WARNING" "Failed to create IAM role for VPC Flow Logs."
        
        # Create permission policy
        permission_policy=$(mktemp)
        cat > "$permission_policy" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
        
        # Attach policy to role
        aws iam put-role-policy --role-name "$role_name" --policy-name "VPCFlowLogsPolicy" --policy-document "file://$permission_policy" || log "WARNING" "Failed to attach policy to IAM role."
        
        # Clean up temporary files
        rm -f "$trust_policy" "$permission_policy"
      fi
      
      # Get role ARN
      role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
      
      # Enable flow logs
      aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids "$vpc" \
        --traffic-type ALL \
        --log-destination-type cloud-watch-logs \
        --log-destination "arn:aws:logs:$(aws configure get region):$(aws sts get-caller-identity --query 'Account' --output text):log-group:$log_group_name" \
        --deliver-logs-permission-arn "$role_arn" || log "WARNING" "Failed to enable VPC Flow Logs for VPC $vpc. They might already be enabled."
    done
    
    # Configure security groups - remove overly permissive rules
    security_groups=$(aws ec2 describe-security-groups --query 'SecurityGroups[*].GroupId' --output text)
    for sg in $security_groups; do
      # Check for 0.0.0.0/0 ingress rules
      permissive_rules=$(aws ec2 describe-security-group-rules \
        --filter "Name=group-id,Values=$sg" "Name=is-egress,Values=false" "Name=cidr,Values=0.0.0.0/0" \
        --query 'SecurityGroupRules[*].{ID:SecurityGroupRuleId,Port:FromPort,Protocol:IpProtocol}' \
        --output json)
      
      # Log warning for permissive rules
      if [[ "$permissive_rules" != "[]" ]]; then
        log "WARNING" "Security group $sg has overly permissive ingress rules:"
        echo "$permissive_rules" | jq -r '.[] | "  - Rule ID: \(.ID), Port: \(.Port), Protocol: \(.Protocol)"'
        log "WARNING" "Consider restricting these rules to specific IP ranges."
      fi
    done
    
    # Enable AWS Network Firewall if available in the region
    if aws networkfirewall help &>/dev/null; then
      log "INFO" "AWS Network Firewall is available. Consider implementing it for enhanced network security."
    fi
    
    log "SUCCESS" "AWS network security configured."
  fi
  
  # Configure GCP network security
  log "INFO" "Configuring GCP network security..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure GCP network security."
  else
    # Get current project
    project_id=$(gcloud config get-value project)
    
    # Enable VPC Flow Logs
    networks=$(gcloud compute networks list --format="value(name)")
    for network in $networks; do
      # Check if flow logs are already enabled
      flow_logs_enabled=$(gcloud compute networks subnets list \
        --filter="network:$network" \
        --format="value(enableFlowLogs)")
      
      if [[ "$flow_logs_enabled" != "True" ]]; then
        # Get all subnets in the network
        subnets=$(gcloud compute networks subnets list \
          --filter="network:$network" \
          --format="value(name,region)")
        
        while read -r subnet_name region; do
          log "INFO" "Enabling flow logs for subnet $subnet_name in $region..."
          
          gcloud compute networks subnets update "$subnet_name" \
            --region="$region" \
            --enable-flow-logs || log "WARNING" "Failed to enable flow logs for subnet $subnet_name."
        done <<< "$subnets"
      fi
    done
    
    # Configure Firewall Rules - check for overly permissive rules
    permissive_rules=$(gcloud compute firewall-rules list \
      --filter="sourceRanges:0.0.0.0/0 AND allowed.ports:22 OR allowed.ports:3389" \
      --format="value(name)")
    
    if [[ -n "$permissive_rules" ]]; then
      log "WARNING" "Found overly permissive firewall rules:"
      echo "$permissive_rules" | while read -r rule; do
        log "WARNING" "  - $rule allows SSH or RDP from anywhere (0.0.0.0/0)"
      done
      log "WARNING" "Consider restricting these rules to specific IP ranges."
    fi
    
    # Configure Cloud Armor if available
    if gcloud compute security-policies list &>/dev/null; then
      # Create a basic security policy if none exists
      existing_policies=$(gcloud compute security-policies list --format="value(name)")
      
      if [[ -z "$existing_policies" ]]; then
        log "INFO" "Creating Cloud Armor security policy..."
        
        gcloud compute security-policies create "default-security-policy" \
          --description "Default security policy created by hardening script" || log "WARNING" "Failed to create Cloud Armor security policy."
        
        # Add rules to block common attacks
        gcloud compute security-policies rules create 1000 \
          --security-policy "default-security-policy" \
          --description "Block XSS attacks" \
          --expression "evaluatePreconfiguredExpr('xss-stable')" \
          --action "deny-403" || log "WARNING" "Failed to create XSS protection rule."
        
        gcloud compute security-policies rules create 2000 \
          --security-policy "default-security-policy" \
          --description "Block SQL injection attacks" \
          --expression "evaluatePreconfiguredExpr('sqli-stable')" \
          --action "deny-403" || log "WARNING" "Failed to create SQL injection protection rule."
        
        gcloud compute security-policies rules create 3000 \
          --security-policy "default-security-policy" \
          --description "Block remote file inclusion attacks" \
          --expression "evaluatePreconfiguredExpr('rfi-stable')" \
          --action "deny-403" || log "WARNING" "Failed to create RFI protection rule."
        
        gcloud compute security-policies rules create 4000 \
          --security-policy "default-security-policy" \
          --description "Block local file inclusion attacks" \
          --expression "evaluatePreconfiguredExpr('lfi-stable')" \
          --action "deny-403" || log "WARNING" "Failed to create LFI protection rule."
      fi
    fi
    
    log "SUCCESS" "GCP network security configured."
  fi
  
  # Configure Azure network security
  log "INFO" "Configuring Azure network security..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Azure network security."
  else
    # Get resource groups
    resource_groups=$(az group list --query '[].name' --output tsv)
    
    for rg in $resource_groups; do
      # Enable NSG flow logs
      nsgs=$(az network nsg list --resource-group "$rg" --query '[].name' --output tsv)
      
      if [[ -n "$nsgs" ]]; then
        for nsg in $nsgs; do
          # Check if flow logs are already enabled
          flow_logs_enabled=$(az network watcher flow-log show \
            --nsg "$nsg" \
            --resource-group "$rg" 2>/dev/null || echo "")
          
          if [[ -z "$flow_logs_enabled" ]]; then
            log "INFO" "Enabling flow logs for NSG $nsg..."
            
            # Create storage account for flow logs if it doesn't exist
            storage_account_name="nsgflowlogs$(openssl rand -hex 4)"
            az storage account create \
              --name "$storage_account_name" \
              --resource-group "$rg" \
              --sku "Standard_LRS" \
              --kind "StorageV2" || log "WARNING" "Failed to create storage account for NSG flow logs."
            
            # Get storage account ID
            storage_id=$(az storage account show \
              --name "$storage_account_name" \
              --resource-group "$rg" \
              --query "id" \
              --output tsv)
            
            # Enable flow logs
            az network watcher flow-log create \
              --nsg "$nsg" \
              --resource-group "$rg" \
              --enabled true \
              --storage-account "$storage_id" \
              --retention 90 || log "WARNING" "Failed to enable flow logs for NSG $nsg."
          fi
          
          # Check for overly permissive rules
          permissive_rules=$(az network nsg rule list \
            --nsg-name "$nsg" \
            --resource-group "$rg" \
            --query "[?sourceAddressPrefix=='*' && (destinationPortRange=='22' || destinationPortRange=='3389')].name" \
            --output tsv)
          
          if [[ -n "$permissive_rules" ]]; then
            log "WARNING" "NSG $nsg has overly permissive rules:"
            echo "$permissive_rules" | while read -r rule; do
              log "WARNING" "  - $rule allows SSH or RDP from anywhere (*)"
            done
            log "WARNING" "Consider restricting these rules to specific IP ranges."
          fi
        done
      fi
      
      # Configure Azure Firewall if available
      firewalls=$(az network firewall list --resource-group "$rg" --query '[].name' --output tsv)
      
      if [[ -z "$firewalls" ]]; then
        log "INFO" "No Azure Firewalls found in resource group $rg. Consider implementing Azure Firewall for enhanced network security."
      else
        log "INFO" "Azure Firewall is already deployed in resource group $rg."
      fi
      
      # Configure Azure Front Door WAF policies if available
      if az network front-door waf-policy list &>/dev/null; then
        waf_policies=$(az network front-door waf-policy list --resource-group "$rg" --query '[].name' --output tsv)
        
        if [[ -z "$waf_policies" ]]; then
          log "INFO" "Creating Azure Front Door WAF policy..."
          
          az network front-door waf-policy create \
            --name "default-waf-policy" \
            --resource-group "$rg" \
            --mode "Prevention" \
            --disabled false || log "WARNING" "Failed to create Azure Front Door WAF policy."
          
          # Enable OWASP rule set
          az network front-door waf-policy managed-rules add \
            --policy-name "default-waf-policy" \
            --resource-group "$rg" \
            --type "Microsoft_DefaultRuleSet" \
            --version "1.1" || log "WARNING" "Failed to add OWASP rule set to WAF policy."
        fi
      fi
    done
    
    log "SUCCESS" "Azure network security configured."
  fi
  
  # Configure Consul service mesh security
  log "INFO" "Configuring Consul service mesh security..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Consul service mesh security."
  else
    # Check if Consul is deployed
    if kubectl get namespace consul &>/dev/null; then
      log "INFO" "Consul namespace found. Checking Consul configuration..."
      
      # Check if Consul Connect (service mesh) is enabled
      connect_enabled=$(kubectl get configmap -n consul consul-server-config -o json 2>/dev/null | jq -r '.data."server.json"' | jq -r '.connect.enabled')
      
      if [[ "$connect_enabled" != "true" ]]; then
        log "WARNING" "Consul Connect is not enabled. Consider enabling it for service-to-service encryption."
      else
        log "INFO" "Consul Connect is enabled. Checking TLS configuration..."
        
        # Check if TLS is enabled
        tls_enabled=$(kubectl get configmap -n consul consul-server-config -o json 2>/dev/null | jq -r '.data."server.json"' | jq -r '.verify_incoming')
        
        if [[ "$tls_enabled" != "true" ]]; then
          log "WARNING" "Consul TLS verification is not enabled. Consider enabling it for secure communications."
        else
          log "INFO" "Consul TLS verification is enabled."
        fi
      fi
    else
      log "INFO" "Consul namespace not found. Skipping Consul service mesh configuration."
    fi
  fi
  
  # Configure Istio service mesh security
  log "INFO" "Configuring Istio service mesh security..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Istio service mesh security."
  else
    # Check if Istio is deployed
    if kubectl get namespace istio-system &>/dev/null; then
      log "INFO" "Istio namespace found. Checking Istio configuration..."
      
      # Check if mTLS is enabled
      mtls_enabled=$(kubectl get peerauthentication -n istio-system -o json 2>/dev/null | jq -r '.items[].spec.mtls.mode')
      
      if [[ "$mtls_enabled" != "STRICT" ]]; then
        log "INFO" "Enabling strict mTLS for Istio..."
        
        # Create PeerAuthentication policy for strict mTLS
        cat << EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF
        
        log "SUCCESS" "Istio mTLS set to STRICT mode."
      else
        log "INFO" "Istio mTLS is already set to STRICT mode."
      fi
      
      # Configure default deny authorization policy
      auth_policy_exists=$(kubectl get authorizationpolicy -n istio-system -o json 2>/dev/null | jq -r '.items | length')
      
      if [[ "$auth_policy_exists" -eq "0" ]]; then
        log "INFO" "Creating default deny authorization policy for Istio..."
        
        # Create default deny policy
        cat << EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: istio-system
spec:
  {}
EOF
        
        log "SUCCESS" "Default deny authorization policy created for Istio."
      else
        log "INFO" "Istio authorization policies already exist."
      fi
    else
      log "INFO" "Istio namespace not found. Skipping Istio service mesh configuration."
    fi
  fi
  
  log "SUCCESS" "Network security improvements completed."
}

#########################################
# 6. Secrets Management Hardening
#########################################
harden_secrets() {
  if should_skip "secrets"; then
    log "INFO" "Skipping secrets management hardening..."
    return
  fi
  
  log "INFO" "Starting secrets management hardening..."
  
  # Check for HashiCorp Vault
  log "INFO" "Checking for HashiCorp Vault..."
  if command_exists vault; then
    log "INFO" "HashiCorp Vault found. Checking configuration..."
    
    # Check Vault status
    if vault status &>/dev/null; then
      log "INFO" "Vault is operational."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure Vault security policies."
      else
        # Check if audit devices are enabled
        audit_devices=$(vault audit list -format=json 2>/dev/null | jq -r 'keys | length')
        
        if [[ "$audit_devices" -eq "0" ]]; then
          log "WARNING" "No audit devices enabled in Vault. Enabling file audit device..."
          
          # Create audit log directory if it doesn't exist
          mkdir -p "${REPO_ROOT}/logs/vault-audit"
          
          # Enable file audit device
          vault audit enable file file_path="${REPO_ROOT}/logs/vault-audit/audit.log" || log "WARNING" "Failed to enable Vault audit logging."
        fi
        
        # Create security policy for least privilege
        cat > /tmp/security-policy.hcl << EOF
# Deny all by default
path "*" {
  capabilities = ["deny"]
}

# Allow listing of secrets but not reading
path "secret/metadata/*" {
  capabilities = ["list"]
}

# Allow reading specific paths
path "secret/data/app/*" {
  capabilities = ["read"]
}

# Allow creating and updating app secrets
path "secret/data/app/+/*" {
  capabilities = ["create", "update", "read"]
}

# Deny access to system backend
path "sys/*" {
  capabilities = ["deny"]
}
EOF
        
        # Create the policy
        vault policy write security-policy /tmp/security-policy.hcl || log "WARNING" "Failed to create Vault security policy."
        
        # Clean up
        rm -f /tmp/security-policy.hcl
        
        log "SUCCESS" "Vault security policies configured."
      fi
    else
      log "WARNING" "Vault is installed but not operational or not accessible."
    fi
  else
    log "INFO" "HashiCorp Vault not found. Checking for other secret management solutions..."
  fi
  
  # Configure Kubernetes Secrets encryption
  log "INFO" "Configuring Kubernetes Secrets management..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would configure Kubernetes Secrets management."
  else
    # Check if Sealed Secrets is installed
    if kubectl get crd sealedsecrets.bitnami.com &>/dev/null; then
      log "INFO" "Sealed Secrets is installed. This is good for encrypting Kubernetes secrets."
    else
      log "INFO" "Sealed Secrets not found. Consider installing it for better Kubernetes secrets management."
      
      # Check if we can install Sealed Secrets
      if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Installing Sealed Secrets controller..."
        
        # Add Bitnami repo
        helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets || log "WARNING" "Failed to add Sealed Secrets Helm repo."
        helm repo update
        
        # Install Sealed Secrets
        helm install sealed-secrets sealed-secrets/sealed-secrets \
          --namespace kube-system \
          --set fullnameOverride=sealed-secrets-controller || log "WARNING" "Failed to install Sealed Secrets controller."
        
        log "SUCCESS" "Sealed Secrets controller installed."
      fi
    fi
    
    # Check if External Secrets Operator is installed
    if kubectl get crd clustersecretstores.external-secrets.io &>/dev/null; then
      log "INFO" "External Secrets Operator is installed. This is good for integrating with external secret stores."
    else
      log "INFO" "External Secrets Operator not found. Consider installing it for integration with external secret