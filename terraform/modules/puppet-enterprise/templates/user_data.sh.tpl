#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "🚀 Puppet Enterprise Bootstrap Started: $(date)"

# Variables passed from Terraform
ENVIRONMENT="${environment}"
PE_VERSION="${pe_version}"
PE_CONSOLE_ADMIN_PASSWORD="${pe_console_admin_password}"
PE_DOWNLOAD_URL="${pe_download_url}"
AWS_REGION="${aws_region}"
CONSUL_SERVER_IPS="${consul_server_ips}"
CONSUL_DATACENTER="${consul_datacenter}"
PUPPET_FQDN="${puppet_fqdn}"

# Create environment file for the full installer script
cat > /tmp/pe_install_env << EOF
export ENVIRONMENT="$ENVIRONMENT"
export PE_VERSION="$PE_VERSION"
export PE_CONSOLE_ADMIN_PASSWORD="$PE_CONSOLE_ADMIN_PASSWORD"
export PE_DOWNLOAD_URL="$PE_DOWNLOAD_URL"
export AWS_REGION="$AWS_REGION"
export CONSUL_SERVER_IPS="$CONSUL_SERVER_IPS"
export CONSUL_DATACENTER="$CONSUL_DATACENTER"
export PUPPET_FQDN="$PUPPET_FQDN"
EOF

# Update system and install essential packages
echo "Installing essential packages..."
yum update -y
yum install -y wget curl

# Download and run the full installation script
echo "Downloading Puppet Enterprise installation script..."
wget -O /tmp/install_puppet_enterprise.sh https://raw.githubusercontent.com/puppetlabs/puppet-enterprise-guide/master/install_script.sh || {
    echo "Failed to download from GitHub, creating installation script locally..."
    cat > /tmp/install_puppet_enterprise.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

# Source environment variables
source /tmp/pe_install_env

echo "🚀 Puppet Enterprise Full Installation Started: $(date)"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to log errors  
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >&2
}

# Install required packages
log_message "Installing required packages..."
yum install -y git vim tree curl nc jq firewalld

# Set hostname
log_message "Setting hostname..."
hostnamectl set-hostname "$PUPPET_FQDN"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Update /etc/hosts
cat >> /etc/hosts << EOF
$PRIVATE_IP $PUPPET_FQDN puppet-enterprise
$PUBLIC_IP $PUPPET_FQDN puppet-enterprise
EOF

# Wait for EBS data volume to attach
log_message "Waiting for EBS data volume to attach..."
DEVICE=""
WAIT_COUNT=0

while [ -z "$DEVICE" ]; do
  if [ -e /dev/sdf ]; then
    DEVICE=/dev/sdf
  elif [ -e /dev/nvme1n1 ]; then
    DEVICE=/dev/nvme1n1
  else
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $WAIT_COUNT -gt 60 ]; then
      log_error "EBS data volume not attached after 5 minutes"
      exit 1
    fi
  fi
done

log_message "Found EBS data volume at $DEVICE"

# Format and mount EBS volume if not already formatted
if ! blkid $DEVICE; then
  log_message "Formatting EBS data volume..."
  mkfs -t xfs $DEVICE
fi

# Create mount point and mount
mkdir -p /opt/puppetlabs
mount $DEVICE /opt/puppetlabs
echo "$DEVICE /opt/puppetlabs xfs defaults,nofail 0 2" >> /etc/fstab

# Configure firewall
log_message "Configuring firewall..."
systemctl start firewalld
systemctl enable firewalld

# Open required ports for Puppet Enterprise
firewall-cmd --permanent --add-port=443/tcp    # PE Console
firewall-cmd --permanent --add-port=8140/tcp   # Puppet Server
firewall-cmd --permanent --add-port=8081/tcp   # PuppetDB
firewall-cmd --permanent --add-port=8142/tcp   # Orchestrator
firewall-cmd --permanent --add-port=8143/tcp   # PCP Broker
firewall-cmd --permanent --add-port=8170/tcp   # Code Manager
firewall-cmd --permanent --add-port=4433/tcp   # PE RBAC
firewall-cmd --reload

# Download Puppet Enterprise
log_message "Downloading Puppet Enterprise..."
cd /tmp
wget --content-disposition "$PE_DOWNLOAD_URL"

# Find and extract PE
PE_TARBALL=$(ls -1 puppet-enterprise-*.tar.gz 2>/dev/null | head -1)
tar -xzf "$PE_TARBALL"
PE_DIR=$(find . -maxdepth 1 -type d -name "puppet-enterprise-*" | head -1)
cd "$PE_DIR"

# Create pe.conf
log_message "Creating pe.conf configuration..."
cat > pe.conf << EOF
{
  "console_admin_password": "$PE_CONSOLE_ADMIN_PASSWORD",
  "puppet_enterprise::puppet_master_host": "$PUPPET_FQDN",
  "pe_install::puppet_master_dnsaltnames": [
    "puppet-enterprise",
    "$PUPPET_FQDN",
    "$PUBLIC_IP",
    "$PRIVATE_IP"
  ],
  "puppet_enterprise::profile::master::code_manager_auto_configure": true,
  "puppet_enterprise::profile::master::r10k_remote": "https://github.com/puppetlabs/control-repo.git",
  "puppet_enterprise::profile::database::puppetdb_java_args": {
    "Xmx": "1g",
    "Xms": "512m"
  },
  "puppet_enterprise::profile::master::java_args": {
    "Xmx": "1g", 
    "Xms": "512m"
  }
}
EOF

# Install Puppet Enterprise
log_message "Installing Puppet Enterprise (15-20 minutes)..."
./puppet-enterprise-installer -c pe.conf

# Enable services
systemctl enable pe-puppetserver pe-puppetdb pe-console-services pe-orchestration-services pe-nginx

# Create basic Puppet code structure
mkdir -p /etc/puppetlabs/code/environments/production/manifests
cat > /etc/puppetlabs/code/environments/production/manifests/site.pp << 'EOF'
node default {
  notify { 'puppet_ready':
    message => "Puppet Enterprise is ready! Environment: $environment",
  }
}
EOF

chown -R pe-puppet:pe-puppet /etc/puppetlabs/code

# Create helper scripts
mkdir -p /usr/local/bin
cat > /usr/local/bin/pe-status << 'EOF'
#!/bin/bash
echo "Puppet Enterprise Status:"
/opt/puppetlabs/bin/puppet infrastructure status
EOF
chmod +x /usr/local/bin/pe-status

# Register with Consul if configured
if [ -n "$CONSUL_SERVER_IPS" ] && [ "$CONSUL_SERVER_IPS" != "" ]; then
    log_message "Installing Consul agent for service registration..."
    cd /tmp
    wget https://releases.hashicorp.com/consul/1.16.1/consul_1.16.1_linux_amd64.zip
    unzip consul_1.16.1_linux_amd64.zip
    mv consul /usr/local/bin/
    
    useradd --system --home /etc/consul.d --shell /bin/false consul
    mkdir -p /opt/consul /etc/consul.d
    chown consul:consul /opt/consul /etc/consul.d
    
    cat > /etc/consul.d/consul.json << EOF
{
  "datacenter": "$CONSUL_DATACENTER",
  "data_dir": "/opt/consul",
  "retry_join": [$(echo "$CONSUL_SERVER_IPS" | sed 's/,/", "/g' | sed 's/^/"/; s/$/"/')],
  "bind_addr": "$PRIVATE_IP",
  "client_addr": "127.0.0.1",
  "services": [
    {
      "name": "puppet-enterprise",
      "port": 443,
      "tags": ["puppet", "configuration-management", "$ENVIRONMENT"]
    }
  ]
}
EOF
    
    chown consul:consul /etc/consul.d/consul.json
    
    cat > /etc/systemd/system/consul.service << 'EOF'
[Unit]
Description=Consul
After=network-online.target

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable consul
    systemctl start consul
fi

log_message "🎉 Puppet Enterprise installation completed: $(date)"
touch /var/lib/cloud/instance/boot-finished
SCRIPT_EOF
}

chmod +x /tmp/install_puppet_enterprise.sh

# Run the full installation script in background
echo "Starting Puppet Enterprise installation..."
nohup /tmp/install_puppet_enterprise.sh > /var/log/pe-install.log 2>&1 &

echo "✅ Bootstrap completed: $(date)"
echo "Full installation running in background. Check /var/log/pe-install.log for progress." 