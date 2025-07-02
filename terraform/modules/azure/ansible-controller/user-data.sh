#!/bin/bash

# Red Hat Ansible Tower VM Initialization Script  
# This script prepares RHEL 8 VMs for Ansible Tower 3.8.6 installation
# Fully automated installation for IaC deployment

set -e

# Log all output
exec > >(tee /var/log/ansible-tower-init.log) 2>&1

echo "Starting Red Hat Ansible Tower VM initialization..."
echo "Timestamp: $(date)"

# Update system
echo "Updating system packages..."
dnf update -y

# Install required packages
echo "Installing required packages..."
dnf install -y \
    curl \
    wget \
    git \
    unzip \
    tar \
    python3 \
    python3-pip \
    firewalld \
    chrony \
    rsync

# Start and enable services
echo "Starting and enabling services..."
systemctl enable --now firewalld
systemctl enable --now chronyd

# Configure firewall for Ansible Tower
echo "Configuring firewall..."
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=22/tcp
firewall-cmd --permanent --add-port=5432/tcp  # PostgreSQL
firewall-cmd --reload

# Create ansible user
echo "Creating ansible user..."
useradd -m -s /bin/bash ansible
usermod -aG wheel ansible

# Set up SSH directory for ansible user
mkdir -p /home/ansible/.ssh
chmod 700 /home/ansible/.ssh
chown ansible:ansible /home/ansible/.ssh

# Format and mount data disk if it exists
echo "Setting up data disk..."
if [ -b /dev/sdc ]; then
    echo "Data disk found at /dev/sdc, formatting and mounting..."
    mkfs.xfs /dev/sdc
    mkdir -p /opt/ansible
    mount /dev/sdc /opt/ansible
    echo "/dev/sdc /opt/ansible xfs defaults 0 0" >> /etc/fstab
    chown -R ansible:ansible /opt/ansible
else
    echo "No data disk found, creating directory on root filesystem..."
    mkdir -p /opt/ansible
    chown -R ansible:ansible /opt/ansible
fi

# Download and install Ansible Tower 3.8.6-2
echo "Downloading Ansible Tower 3.8.6-2..."
mkdir -p /opt/ansible/installer
cd /opt/ansible/installer

# Download the installer
wget -O ansible-tower-setup-bundle-latest.el8.tar.gz \
    https://releases.ansible.com/ansible-tower/setup-bundle/ansible-tower-setup-bundle-latest.el8.tar.gz

# Extract the installer
echo "Extracting Ansible Tower installer..."
tar -xzf ansible-tower-setup-bundle-latest.el8.tar.gz

# Change to installer directory
cd ansible-tower-setup-bundle-3.8.6-2

# Create automated inventory configuration
echo "Creating Ansible Tower inventory configuration..."
cat > inventory << 'EOF'
[tower]
localhost ansible_connection=local

[automationhub]

[database]

[all:vars]
admin_password='AnsibleTower123!'

pg_host=''
pg_port=''

pg_database='awx'
pg_username='awx'
pg_password='PostgresPass123!'
pg_sslmode='prefer'

# Automation Hub Configuration - disabled for single-node setup
automationhub_admin_password=''
automationhub_pg_host=''
automationhub_pg_port=''
automationhub_pg_database='automationhub'
automationhub_pg_username='automationhub'
automationhub_pg_password=''
automationhub_pg_sslmode='prefer'
EOF

# Create installation script
echo "Creating installation script..."
cat > /opt/ansible/install-tower.sh << 'EOF'
#!/bin/bash
set -e

echo "Starting Ansible Tower 3.8.6-2 installation..."
echo "Timestamp: $(date)"

cd /opt/ansible/installer/ansible-tower-setup-bundle-3.8.6-2

# Run the installation
echo "Running Ansible Tower installer..."
./setup.sh 2>&1 | tee /var/log/ansible-tower-install.log

# Check installation status
echo "Installation completed. Checking services..."
systemctl status ansible-tower-web --no-pager || true
systemctl status ansible-tower-task --no-pager || true
systemctl status postgresql --no-pager || true

# Enable services to start on boot
systemctl enable ansible-tower-web
systemctl enable ansible-tower-task

echo "Ansible Tower installation completed successfully!"
echo "Access URL: http://$(hostname -I | awk '{print $1}')"
echo "Admin username: admin"
echo "Admin password: AnsibleTower123!"
echo "Installation completed at: $(date)"
EOF

chmod +x /opt/ansible/install-tower.sh

# Create SSL certificate fix script
echo "Creating SSL certificate fix script..."
cat > /opt/ansible/fix-ssl-certificate.sh << 'EOF'
#!/bin/bash
set -e

echo "Fixing SSL certificate for external access..."

# Get the VM's public IP address
PUBLIC_IP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01" || echo "")
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Stop Tower services
systemctl stop ansible-tower

# Backup current certificate
cp /etc/tower/tower.cert /etc/tower/tower.cert.backup || true
cp /etc/tower/tower.key /etc/tower/tower.key.backup || true

# Generate new certificate with correct IP addresses
if [ -n "$PUBLIC_IP" ]; then
    echo "Generating SSL certificate for public IP: $PUBLIC_IP"
    openssl req -new -x509 -days 365 -nodes -out /etc/tower/tower.cert -keyout /etc/tower/tower.key \
        -subj "/CN=$PUBLIC_IP" \
        -addext "subjectAltName=IP:$PUBLIC_IP,IP:$PRIVATE_IP,DNS:localhost,DNS:$(hostname)"
else
    echo "Generating SSL certificate for private IP: $PRIVATE_IP"
    openssl req -new -x509 -days 365 -nodes -out /etc/tower/tower.cert -keyout /etc/tower/tower.key \
        -subj "/CN=$PRIVATE_IP" \
        -addext "subjectAltName=IP:$PRIVATE_IP,DNS:localhost,DNS:$(hostname)"
fi

# Set correct permissions
chown awx:awx /etc/tower/tower.cert /etc/tower/tower.key
chmod 640 /etc/tower/tower.cert /etc/tower/tower.key

# Start Tower services
systemctl start ansible-tower

echo "SSL certificate updated successfully"
EOF

chmod +x /opt/ansible/fix-ssl-certificate.sh

# Run the installation
echo "Running Ansible Tower installation..."
/opt/ansible/install-tower.sh

# Fix SSL certificate after installation
echo "Fixing SSL certificate for external access..."
/opt/ansible/fix-ssl-certificate.sh

# Create status script for verification
cat > /opt/ansible/check-tower-status.sh << 'EOF'
#!/bin/bash
echo "=== Ansible Tower Status Check ==="
echo "Timestamp: $(date)"

echo "=== Service Status ==="
systemctl is-active ansible-tower-web || echo "ansible-tower-web: inactive"
systemctl is-active ansible-tower-task || echo "ansible-tower-task: inactive"
systemctl is-active postgresql || echo "postgresql: inactive"

echo "=== Tower Web Interface ==="
if systemctl is-active ansible-tower-web > /dev/null; then
    echo "Tower Web: http://$(hostname -I | awk '{print $1}')"
    echo "Admin username: admin"
    echo "Admin password: AnsibleTower123!"
else
    echo "Tower Web: Not running"
fi

echo "=== Recent Log Entries ==="
tail -10 /var/log/ansible-tower-install.log 2>/dev/null || echo "No installation log found"
EOF

chmod +x /opt/ansible/check-tower-status.sh

# Set proper ownership
chown -R ansible:ansible /opt/ansible

# Create VM info file
cat > /opt/ansible/vm-info.txt << EOF
VM Type: $(dmidecode -s system-product-name 2>/dev/null || echo "Unknown")
VM Size: $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01" || echo "Unknown")
Private IP: $(hostname -I | awk '{print $1}')
Hostname: $(hostname)
OS: $(cat /etc/redhat-release)
Ansible Tower Version: 3.8.6-2
Admin Username: admin
Admin Password: AnsibleTower123!
Database Password: PostgresPass123!
Initialization Date: $(date)
EOF

chown ansible:ansible /opt/ansible/vm-info.txt

# Final status check
echo "=== Final Status Check ==="
/opt/ansible/check-tower-status.sh

echo "Red Hat Ansible Tower VM initialization completed successfully!"
echo "Access Tower at: http://$(hostname -I | awk '{print $1}')"
echo "Username: admin"
echo "Password: AnsibleTower123!"
echo ""
echo "Initialization completed at: $(date)" 