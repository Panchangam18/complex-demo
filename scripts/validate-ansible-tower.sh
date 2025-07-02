#!/bin/bash

# Ansible Tower Installation Validation Script
# This script validates that Ansible Tower 3.8.6-2 is properly installed and running

set -e

RESOURCE_GROUP="dev-ansible-controller-rg"
VM_NAME="dev-ansible-controller-controller-1"

echo "=== Ansible Tower Installation Validation ==="
echo "Timestamp: $(date)"
echo "Resource Group: $RESOURCE_GROUP"
echo "VM Name: $VM_NAME"
echo ""

# Function to run command on Azure VM
run_vm_command() {
    local script="$1"
    echo "Running command on VM..."
    az vm run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --command-id RunShellScript \
        --scripts "$script" \
        --output table
}

# Check VM status
echo "1. Checking VM status..."
VM_STATUS=$(az vm get-instance-view \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "instanceView.statuses[1].displayStatus" \
    --output tsv)
echo "VM Status: $VM_STATUS"

if [ "$VM_STATUS" != "VM running" ]; then
    echo "❌ VM is not running. Current status: $VM_STATUS"
    exit 1
fi
echo "✅ VM is running"
echo ""

# Check Tower services
echo "2. Checking Ansible Tower services..."
run_vm_command '
echo "=== Service Status ==="
systemctl is-active ansible-tower-web || echo "ansible-tower-web: not active"
systemctl is-active ansible-tower-task || echo "ansible-tower-task: not active"  
systemctl is-active postgresql || echo "postgresql: not active"

echo ""
echo "=== Service Details ==="
systemctl status ansible-tower-web --no-pager -l || true
'

echo ""

# Check Tower web interface
echo "3. Checking Tower web interface accessibility..."
PUBLIC_IP=$(az vm list-ip-addresses \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
    --output tsv 2>/dev/null || echo "No public IP")

if [ "$PUBLIC_IP" != "No public IP" ] && [ -n "$PUBLIC_IP" ]; then
    echo "Public IP: $PUBLIC_IP"
    echo "Testing web interface connectivity..."
    
    # Test HTTP connectivity
    if curl -s --connect-timeout 10 "http://$PUBLIC_IP" > /dev/null; then
        echo "✅ Tower web interface is accessible at http://$PUBLIC_IP"
    else
        echo "❌ Tower web interface is not accessible at http://$PUBLIC_IP"
    fi
else
    echo "⚠️  No public IP found, checking load balancer IP..."
    LB_IP=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "dev-ansible-controller-lb-ip" \
        --query "ipAddress" \
        --output tsv 2>/dev/null || echo "No LB IP")
    
    if [ "$LB_IP" != "No LB IP" ] && [ -n "$LB_IP" ]; then
        echo "Load Balancer IP: $LB_IP"
        if curl -s --connect-timeout 10 "http://$LB_IP" > /dev/null; then
            echo "✅ Tower web interface is accessible at http://$LB_IP"
        else
            echo "❌ Tower web interface is not accessible at http://$LB_IP"
        fi
    fi
fi

echo ""

# Check installation logs
echo "4. Checking installation logs..."
run_vm_command '
if [ -f /var/log/ansible-tower-install.log ]; then
    echo "=== Installation Log (last 20 lines) ==="
    tail -20 /var/log/ansible-tower-install.log
    
    echo ""
    echo "=== Installation Status ==="
    if grep -q "The setup process completed successfully" /var/log/ansible-tower-install.log; then
        echo "✅ Installation completed successfully"
    elif grep -q "PLAY RECAP" /var/log/ansible-tower-install.log; then
        echo "✅ Ansible playbook execution completed"
    else
        echo "❌ Installation may not have completed successfully"
    fi
else
    echo "❌ Installation log not found"
fi
'

echo ""

# Check Tower configuration
echo "5. Checking Tower configuration..."
run_vm_command '
echo "=== Tower Configuration ==="
if [ -f /etc/tower/settings.py ]; then
    echo "✅ Tower settings file exists"
    echo "Database configuration:"
    grep -E "^DATABASES|HOST|NAME|USER" /etc/tower/settings.py | head -5 || true
else
    echo "❌ Tower settings file not found"
fi

echo ""
echo "=== Database Status ==="
if systemctl is-active postgresql > /dev/null; then
    sudo -u postgres psql -c "\l" | grep awx || echo "AWX database not found"
else
    echo "PostgreSQL is not running"
fi
'

echo ""
echo "=== Validation Summary ==="
echo "VM Status: $VM_STATUS"
echo "Access URL: http://$PUBLIC_IP (or load balancer IP)"
echo "Admin Username: admin"
echo "Admin Password: AnsibleTower123!"
echo ""
echo "To check detailed status, run:"
echo "az vm run-command invoke --resource-group $RESOURCE_GROUP --name $VM_NAME --command-id RunShellScript --scripts '/opt/ansible/check-tower-status.sh'"
echo ""
echo "Validation completed at: $(date)" 