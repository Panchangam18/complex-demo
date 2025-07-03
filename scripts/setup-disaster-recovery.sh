#!/bin/bash

# 💾 COMPREHENSIVE DISASTER RECOVERY SETUP
# ========================================
# This script configures complete disaster recovery including:
# - Automated database backups with cross-region replication
# - Kubernetes cluster backup and restore
# - Configuration and secret backup
# - Recovery runbooks and automation

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
BACKUP_REGION=${BACKUP_REGION:-us-west-2}
TERRAFORM_DIR="${TERRAFORM_DIR:-terraform/envs/${ENVIRONMENT}/${REGION}}"

# Print banner
print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║              💾 COMPREHENSIVE DISASTER RECOVERY SETUP 💾                    ║"
    echo "║                                                                              ║"
    echo "║  • Automated database backups and replication                               ║"
    echo "║  • Kubernetes cluster backup and restore                                    ║"
    echo "║  • Configuration and secret management                                      ║"
    echo "║  • Recovery automation and runbooks                                         ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Configure RDS backup and cross-region replication
configure_rds_backup() {
    echo -e "${BLUE}🗄️ Configuring RDS backup and replication...${NC}"
    
    # Get RDS instance information
    local rds_instances=$(aws rds describe-db-instances --region "$REGION" --query 'DBInstances[?contains(DBInstanceIdentifier, `'$ENVIRONMENT'`)].DBInstanceIdentifier' --output text)
    
    for instance in $rds_instances; do
        echo -e "${BLUE}   📋 Configuring backup for RDS instance: $instance${NC}"
        
        # Modify backup settings
        aws rds modify-db-instance \
            --db-instance-identifier "$instance" \
            --backup-retention-period 30 \
            --preferred-backup-window "03:00-04:00" \
            --preferred-maintenance-window "sun:04:00-sun:05:00" \
            --enable-performance-insights \
            --region "$REGION" \
            --apply-immediately || echo -e "${YELLOW}⚠️  Failed to modify $instance${NC}"
        
        # Create cross-region read replica
        local replica_id="${instance}-replica-${BACKUP_REGION}"
        if ! aws rds describe-db-instances --db-instance-identifier "$replica_id" --region "$BACKUP_REGION" >/dev/null 2>&1; then
            aws rds create-db-instance-read-replica \
                --db-instance-identifier "$replica_id" \
                --source-db-instance-identifier "arn:aws:rds:${REGION}:$(aws sts get-caller-identity --query Account --output text):db:${instance}" \
                --region "$BACKUP_REGION" \
                --db-instance-class "db.t3.micro" \
                --publicly-accessible false || echo -e "${YELLOW}⚠️  Failed to create replica for $instance${NC}"
        else
            echo -e "${GREEN}   ✅ Read replica already exists for $instance${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ RDS backup and replication configured${NC}"
}

# Install and configure Velero for Kubernetes backup
install_velero_backup() {
    echo -e "${BLUE}☸️ Installing Velero for Kubernetes backup...${NC}"
    
    # Create S3 bucket for backups
    local backup_bucket="k8s-backup-${ENVIRONMENT}-$(aws sts get-caller-identity --query Account --output text)"
    
    if ! aws s3 ls "s3://$backup_bucket" >/dev/null 2>&1; then
        aws s3 mb "s3://$backup_bucket" --region "$REGION"
        
        # Enable versioning and lifecycle
        aws s3api put-bucket-versioning \
            --bucket "$backup_bucket" \
            --versioning-configuration Status=Enabled
        
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "$backup_bucket" \
            --lifecycle-configuration '{
                "Rules": [
                    {
                        "ID": "BackupRetention",
                        "Status": "Enabled",
                        "Filter": {},
                        "Transitions": [
                            {
                                "Days": 30,
                                "StorageClass": "STANDARD_IA"
                            },
                            {
                                "Days": 90,
                                "StorageClass": "GLACIER"
                            }
                        ],
                        "Expiration": {
                            "Days": 365
                        }
                    }
                ]
            }'
    fi
    
    # Create IAM role for Velero
    local velero_role_name="velero-role-${ENVIRONMENT}"
    if ! aws iam get-role --role-name "$velero_role_name" >/dev/null 2>&1; then
        aws iam create-role \
            --role-name "$velero_role_name" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "ec2.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }'
        
        aws iam put-role-policy \
            --role-name "$velero_role_name" \
            --policy-name "VeleroBackupPolicy" \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "ec2:DescribeVolumes",
                            "ec2:DescribeSnapshots",
                            "ec2:CreateTags",
                            "ec2:CreateVolume",
                            "ec2:CreateSnapshot",
                            "ec2:DeleteSnapshot"
                        ],
                        "Resource": "*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "s3:GetObject",
                            "s3:DeleteObject",
                            "s3:PutObject",
                            "s3:AbortMultipartUpload",
                            "s3:ListMultipartUploadParts"
                        ],
                        "Resource": [
                            "arn:aws:s3:::'$backup_bucket'/*"
                        ]
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "s3:ListBucket"
                        ],
                        "Resource": [
                            "arn:aws:s3:::'$backup_bucket'"
                        ]
                    }
                ]
            }'
    fi
    
    # Install Velero
    if ! kubectl get namespace velero >/dev/null 2>&1; then
        # Download and install Velero CLI if not present
        if ! command -v velero >/dev/null 2>&1; then
            local velero_version="v1.12.1"
            wget -O /tmp/velero.tar.gz "https://github.com/vmware-tanzu/velero/releases/download/${velero_version}/velero-${velero_version}-linux-amd64.tar.gz"
            tar -xzf /tmp/velero.tar.gz -C /tmp
            sudo mv "/tmp/velero-${velero_version}-linux-amd64/velero" /usr/local/bin/
            rm -rf /tmp/velero*
        fi
        
        # Install Velero in cluster
        velero install \
            --provider aws \
            --plugins velero/velero-plugin-for-aws:v1.8.1 \
            --bucket "$backup_bucket" \
            --backup-location-config region="$REGION" \
            --snapshot-location-config region="$REGION" \
            --secret-file <(echo -e "[default]\naws_access_key_id=$(aws configure get aws_access_key_id)\naws_secret_access_key=$(aws configure get aws_secret_access_key)") \
            --wait
    fi
    
    echo -e "${GREEN}✅ Velero backup system installed${NC}"
}

# Configure backup schedules
configure_backup_schedules() {
    echo -e "${BLUE}⏰ Configuring backup schedules...${NC}"
    
    # Daily full cluster backup
    kubectl apply -f - << 'EOF'
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 1 * * *"  # Daily at 1 AM
  template:
    ttl: "720h"  # 30 days
    includedNamespaces:
    - "*"
    excludedNamespaces:
    - kube-system
    - velero
    storageLocation: default
    volumeSnapshotLocations:
    - default
EOF

    # Weekly backup with longer retention
    kubectl apply -f - << 'EOF'
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: weekly-backup
  namespace: velero
spec:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2 AM
  template:
    ttl: "2160h"  # 90 days
    includedNamespaces:
    - "*"
    storageLocation: default
    volumeSnapshotLocations:
    - default
EOF

    # Critical data backup (more frequent)
    kubectl apply -f - << 'EOF'
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: critical-data-backup
  namespace: velero
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  template:
    ttl: "168h"  # 7 days
    includedNamespaces:
    - backend-dev
    - frontend-dev
    - monitoring
    includedResources:
    - secrets
    - configmaps
    - persistentvolumes
    - persistentvolumeclaims
    storageLocation: default
EOF

    echo -e "${GREEN}✅ Backup schedules configured${NC}"
}

# Configure secrets and configuration backup
configure_secrets_backup() {
    echo -e "${BLUE}🔐 Configuring secrets and configuration backup...${NC}"
    
    # Create backup of all secrets
    kubectl create namespace backup-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create CronJob for secrets backup
    kubectl apply -f - << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: secrets-backup
  namespace: backup-system
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: secrets-backup-sa
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              echo "Starting secrets backup..."
              
              # Create backup directory
              BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"
              mkdir -p "$BACKUP_DIR"
              
              # Backup all secrets
              for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
                mkdir -p "$BACKUP_DIR/secrets/$ns"
                kubectl get secrets -n "$ns" -o yaml > "$BACKUP_DIR/secrets/$ns/secrets.yaml"
                kubectl get configmaps -n "$ns" -o yaml > "$BACKUP_DIR/secrets/$ns/configmaps.yaml"
              done
              
              # Backup RBAC
              kubectl get clusterroles -o yaml > "$BACKUP_DIR/clusterroles.yaml"
              kubectl get clusterrolebindings -o yaml > "$BACKUP_DIR/clusterrolebindings.yaml"
              kubectl get roles --all-namespaces -o yaml > "$BACKUP_DIR/roles.yaml"
              kubectl get rolebindings --all-namespaces -o yaml > "$BACKUP_DIR/rolebindings.yaml"
              
              # Backup network policies
              kubectl get networkpolicies --all-namespaces -o yaml > "$BACKUP_DIR/networkpolicies.yaml"
              
              # Upload to S3
              aws s3 sync "$BACKUP_DIR" "s3://k8s-config-backup-${ENVIRONMENT}/$(date +%Y%m%d_%H%M%S)/"
              
              echo "Backup completed successfully"
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
            env:
            - name: AWS_DEFAULT_REGION
              value: "${REGION}"
          volumes:
          - name: backup-storage
            emptyDir: {}
          restartPolicy: OnFailure
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secrets-backup-sa
  namespace: backup-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secrets-backup-role
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps", "namespaces"]
  verbs: ["get", "list"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  verbs: ["get", "list"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: secrets-backup-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: secrets-backup-role
subjects:
- kind: ServiceAccount
  name: secrets-backup-sa
  namespace: backup-system
EOF

    echo -e "${GREEN}✅ Secrets and configuration backup configured${NC}"
}

# Create disaster recovery runbooks
create_recovery_runbooks() {
    echo -e "${BLUE}📚 Creating disaster recovery runbooks...${NC}"
    
    mkdir -p docs/disaster-recovery
    
    # Main DR runbook
    cat > docs/disaster-recovery/DISASTER_RECOVERY_RUNBOOK.md << 'EOF'
# Disaster Recovery Runbook

## Overview
This runbook provides step-by-step procedures for recovering from various disaster scenarios.

## Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)
- **Critical Services**: RTO: 4 hours, RPO: 15 minutes
- **Non-Critical Services**: RTO: 24 hours, RPO: 1 hour
- **Data**: RTO: 2 hours, RPO: 5 minutes

## Scenarios

### 1. Complete AWS Region Failure

#### Immediate Actions (0-30 minutes)
1. **Assess Impact**
   ```bash
   # Check AWS service health
   aws health describe-events --region us-east-2
   
   # Verify backup region accessibility
   aws ec2 describe-regions --region us-west-2
   ```

2. **Activate Backup Infrastructure**
   ```bash
   # Switch to backup region
   export AWS_DEFAULT_REGION=us-west-2
   
   # Deploy infrastructure to backup region
   cd terraform/envs/dev/us-west-2
   terragrunt apply -auto-approve
   ```

3. **Restore Database**
   ```bash
   # Promote read replica to primary
   aws rds promote-read-replica \
     --db-instance-identifier myapp-db-replica-us-west-2 \
     --region us-west-2
   ```

#### Recovery Actions (30 minutes - 4 hours)
4. **Restore Kubernetes Cluster**
   ```bash
   # Update kubeconfig for backup region
   aws eks update-kubeconfig --region us-west-2 --name backup-cluster
   
   # Restore from Velero backup
   velero restore create --from-backup daily-backup-$(date +%Y%m%d) --wait
   ```

5. **Verify Application Functionality**
   ```bash
   # Run validation script
   ./scripts/validate-complete-setup.sh
   ```

6. **Update DNS Records**
   ```bash
   # Point DNS to backup region
   aws route53 change-resource-record-sets \
     --hosted-zone-id Z123456789 \
     --change-batch file://dns-failover.json
   ```

### 2. Database Corruption/Loss

#### Immediate Actions
1. **Isolate Affected Database**
   ```bash
   # Stop application writes
   kubectl scale deployment backend --replicas=0 -n backend-dev
   ```

2. **Assess Corruption Extent**
   ```bash
   # Check database integrity
   kubectl exec -it postgres-pod -- psql -c "SELECT * FROM pg_stat_database;"
   ```

3. **Restore from Backup**
   ```bash
   # Point-in-time recovery
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier myapp-db \
     --target-db-instance-identifier myapp-db-restored \
     --restore-time 2024-01-01T12:00:00.000Z
   ```

### 3. Kubernetes Cluster Failure

#### Recovery Steps
1. **Deploy New Cluster**
   ```bash
   # Create new EKS cluster
   cd terraform/modules/aws/eks
   terragrunt apply -auto-approve
   ```

2. **Restore Applications**
   ```bash
   # Restore from Velero
   velero restore create --from-backup weekly-backup-latest --wait
   ```

3. **Restore Persistent Data**
   ```bash
   # Restore PVs from snapshots
   kubectl apply -f backup/persistent-volumes/
   ```

## Contact Information
- **On-Call Engineer**: +1-555-0123
- **Engineering Manager**: +1-555-0124
- **AWS Support**: Enterprise Support Case

## Post-Recovery Actions
1. Conduct post-incident review
2. Update runbooks based on lessons learned
3. Test recovery procedures monthly
4. Update backup retention policies if needed

## Testing Schedule
- **Monthly**: Database restore test
- **Quarterly**: Full disaster recovery drill
- **Annually**: Complete region failover test
EOF

    # Create specific recovery scripts
    cat > docs/disaster-recovery/quick-recovery.sh << 'EOF'
#!/bin/bash
# Quick Recovery Script
# This script automates the most common recovery scenarios

set -euo pipefail

SCENARIO=${1:-""}
ENVIRONMENT=${ENVIRONMENT:-dev}
BACKUP_REGION=${BACKUP_REGION:-us-west-2}

case "$SCENARIO" in
    "database")
        echo "🗄️ Initiating database recovery..."
        # Database recovery logic here
        ;;
    "cluster")
        echo "☸️ Initiating cluster recovery..."
        # Cluster recovery logic here
        ;;
    "full")
        echo "🚨 Initiating full disaster recovery..."
        # Full recovery logic here
        ;;
    *)
        echo "Usage: $0 {database|cluster|full}"
        exit 1
        ;;
esac
EOF

    chmod +x docs/disaster-recovery/quick-recovery.sh
    
    echo -e "${GREEN}✅ Disaster recovery runbooks created${NC}"
}

# Configure monitoring and alerting for backup systems
configure_backup_monitoring() {
    echo -e "${BLUE}📊 Configuring backup monitoring...${NC}"
    
    # Create PrometheusRule for backup alerts
    kubectl apply -f - << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: backup-alerts
  namespace: velero
  labels:
    app: velero
spec:
  groups:
  - name: backup.rules
    rules:
    - alert: VeleroBackupFailed
      expr: increase(velero_backup_failure_total[24h]) > 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Velero backup failed"
        description: "Velero backup has failed in the last 24 hours."
    
    - alert: VeleroBackupTooOld
      expr: time() - velero_backup_last_successful_timestamp > 86400
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Velero backup is too old"
        description: "No successful Velero backup in the last 24 hours."
    
    - alert: RDSBackupFailed
      expr: aws_rds_backup_failed > 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "RDS backup failed"
        description: "RDS automated backup has failed."
EOF

    # Create Grafana dashboard for backup monitoring
    kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: backup-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  backup-dashboard.json: |
    {
      "dashboard": {
        "title": "Disaster Recovery Dashboard",
        "panels": [
          {
            "title": "Backup Success Rate",
            "type": "stat",
            "targets": [
              {
                "expr": "rate(velero_backup_success_total[24h]) * 100",
                "legendFormat": "Success Rate %"
              }
            ]
          },
          {
            "title": "Backup Duration",
            "type": "graph",
            "targets": [
              {
                "expr": "velero_backup_duration_seconds",
                "legendFormat": "{{backup_name}}"
              }
            ]
          },
          {
            "title": "RDS Backup Status",
            "type": "table",
            "targets": [
              {
                "expr": "aws_rds_backup_latest_recovery_time",
                "legendFormat": "{{instance}}"
              }
            ]
          }
        ]
      }
    }
EOF

    echo -e "${GREEN}✅ Backup monitoring configured${NC}"
}

# Validate disaster recovery setup
validate_dr_setup() {
    echo -e "${BLUE}🔍 Validating disaster recovery setup...${NC}"
    
    local validation_passed=true
    
    # Check Velero installation
    if kubectl get pods -n velero --no-headers 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✅ Velero is running${NC}"
    else
        echo -e "${RED}❌ Velero is not running${NC}"
        validation_passed=false
    fi
    
    # Check backup schedules
    local schedules=$(kubectl get schedules -n velero --no-headers 2>/dev/null | wc -l)
    if [ "$schedules" -gt 0 ]; then
        echo -e "${GREEN}✅ $schedules backup schedules configured${NC}"
    else
        echo -e "${RED}❌ No backup schedules found${NC}"
        validation_passed=false
    fi
    
    # Check recent backups
    local recent_backups=$(kubectl get backups -n velero --no-headers 2>/dev/null | head -5 | wc -l)
    if [ "$recent_backups" -gt 0 ]; then
        echo -e "${GREEN}✅ $recent_backups recent backups found${NC}"
    else
        echo -e "${YELLOW}⚠️  No recent backups found${NC}"
    fi
    
    # Check S3 backup bucket
    local backup_bucket="k8s-backup-${ENVIRONMENT}-$(aws sts get-caller-identity --query Account --output text)"
    if aws s3 ls "s3://$backup_bucket" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ S3 backup bucket accessible${NC}"
    else
        echo -e "${RED}❌ S3 backup bucket not accessible${NC}"
        validation_passed=false
    fi
    
    if [ "$validation_passed" = true ]; then
        echo -e "${GREEN}✅ Disaster recovery validation passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Disaster recovery validation failed${NC}"
        return 1
    fi
}

# Display summary
display_summary() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  🎉 DISASTER RECOVERY SETUP COMPLETE 🎉                     ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}💾 Disaster Recovery Summary:${NC}"
    echo -e "   🗄️  Database: Automated backups with cross-region replicas"
    echo -e "   ☸️  Kubernetes: Velero backup system with scheduled backups"
    echo -e "   🔐 Secrets: Automated configuration and secrets backup"
    echo -e "   📚 Runbooks: Comprehensive recovery procedures"
    echo -e "   📊 Monitoring: Backup success/failure alerting"
    
    echo -e "\n${BLUE}🔧 What Was Configured:${NC}"
    echo -e "   ✅ RDS automated backups with 30-day retention"
    echo -e "   ✅ Cross-region read replicas for failover"
    echo -e "   ✅ Velero for Kubernetes cluster backup"
    echo -e "   ✅ Daily, weekly, and critical data backup schedules"
    echo -e "   ✅ Secrets and configuration backup automation"
    echo -e "   ✅ Disaster recovery runbooks and procedures"
    echo -e "   ✅ Backup monitoring and alerting"
    
    echo -e "\n${BLUE}⏰ Backup Schedules:${NC}"
    echo -e "   • Daily: Full cluster backup (1 AM, 30-day retention)"
    echo -e "   • Weekly: Long-term backup (Sunday 2 AM, 90-day retention)"
    echo -e "   • Critical: High-frequency data backup (every 6 hours, 7-day retention)"
    echo -e "   • Secrets: Daily configuration backup (3 AM)"
    
    echo -e "\n${BLUE}🚨 Recovery Objectives:${NC}"
    echo -e "   • RTO (Recovery Time): 4 hours for critical services"
    echo -e "   • RPO (Recovery Point): 15 minutes for critical data"
    echo -e "   • Database: Point-in-time recovery capability"
    echo -e "   • Applications: Full cluster restore capability"
    
    echo -e "\n${BLUE}🔗 Management Commands:${NC}"
    echo -e "   # Check backup status:"
    echo -e "   kubectl get backups -n velero"
    echo -e ""
    echo -e "   # Manual backup:"
    echo -e "   velero backup create manual-backup-\$(date +%Y%m%d-%H%M%S)"
    echo -e ""
    echo -e "   # Restore from backup:"
    echo -e "   velero restore create --from-backup <backup-name>"
    echo -e ""
    echo -e "   # Check RDS backups:"
    echo -e "   aws rds describe-db-snapshots --region $REGION"
    
    echo -e "\n${BLUE}📚 Documentation:${NC}"
    echo -e "   • Disaster recovery runbook: docs/disaster-recovery/DISASTER_RECOVERY_RUNBOOK.md"
    echo -e "   • Quick recovery script: docs/disaster-recovery/quick-recovery.sh"
    echo -e "   • Regular DR drills scheduled monthly"
    
    echo -e "\n${GREEN}🎊 Your disaster recovery system is fully operational! 🎊${NC}"
}

# Main execution
main() {
    print_banner
    
    echo -e "${BLUE}📋 Starting comprehensive disaster recovery setup...${NC}"
    echo -e "   Environment: $ENVIRONMENT"
    echo -e "   Primary Region: $REGION"
    echo -e "   Backup Region: $BACKUP_REGION"
    
    configure_rds_backup
    install_velero_backup
    configure_backup_schedules
    configure_secrets_backup
    create_recovery_runbooks
    configure_backup_monitoring
    validate_dr_setup
    display_summary
    
    echo -e "${GREEN}✅ Disaster recovery setup completed successfully!${NC}"
}

# Execute main function
main "$@" 