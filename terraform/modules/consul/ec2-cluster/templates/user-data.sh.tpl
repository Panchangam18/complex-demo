#!/bin/bash
set -e

# Log output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Consul installation v6 at $(date)"

# Wait for cloud-init to complete
sleep 60

# Update system with retries
export DEBIAN_FRONTEND=noninteractive
for i in {1..10}; do
  if apt-get update -y; then
    echo "apt-get update succeeded on attempt $i"
    break
  else
    echo "apt-get update failed on attempt $i, retrying in 30 seconds..."
    sleep 30
  fi
done

# Install required packages
apt-get install -y curl unzip jq awscli

# Verify installation
which curl unzip jq aws || { echo "Failed to install dependencies"; exit 1; }

# Install Consul
cd /tmp
echo "Downloading Consul ${consul_version}..."
curl -O https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip
unzip consul_${consul_version}_linux_amd64.zip
mv consul /usr/local/bin/
chmod +x /usr/local/bin/consul

# Verify Consul installation
/usr/local/bin/consul version || { echo "Consul installation failed"; exit 1; }

# Create consul user
useradd --system --home /var/lib/consul --shell /bin/false consul

# Create directories
mkdir -p /opt/consul /var/lib/consul /etc/consul.d /var/log/consul
chown -R consul:consul /opt/consul /var/lib/consul /etc/consul.d /var/log/consul

# Get the private IP address
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Private IP: $PRIVATE_IP"

# Generate Consul configuration
echo "Creating Consul configuration..."
cat > /etc/consul.d/consul.json <<EOF
{
  "datacenter": "${datacenter}",
  "node_name": "${node_name}",
  "server": true,
  "bootstrap_expect": ${total_servers},
  "encrypt": "${gossip_key}",
  "data_dir": "/var/lib/consul",
  "log_level": "INFO",
  "log_file": "/var/log/consul/consul.log",
  "ui_config": {
    "enabled": ${enable_ui}
  },
  "connect": {
    "enabled": ${enable_connect}
  },
  "ports": {
    "grpc": 8502,
    "http": 8500
  },
  "client_addr": "0.0.0.0",
  "bind_addr": "$PRIVATE_IP",
  "retry_join": ["provider=aws tag_key=ConsulAutoJoin tag_value=${retry_join_tag} region=${aws_region}"],
  "performance": {
    "raft_multiplier": 1
  }
}
EOF

# Validate configuration
echo "Validating Consul configuration..."
/usr/local/bin/consul validate /etc/consul.d/consul.json || { echo "Consul configuration validation failed"; exit 1; }

# Create systemd service
echo "Creating Consul systemd service..."
cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description=Consul
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.json

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Consul
echo "Starting Consul service..."
systemctl daemon-reload
systemctl enable consul
systemctl start consul

# Wait for Consul to start and validate
echo "Waiting for Consul to start..."
for i in {1..20}; do
  if systemctl is-active --quiet consul; then
    echo "Consul service is active"
    break
  else
    echo "Consul not ready yet, waiting... ($i/20)"
    sleep 15
  fi
done

# Additional health check - test Consul HTTP API
echo "Testing Consul HTTP API..."
for i in {1..10}; do
  if curl -f http://localhost:8500/v1/status/leader; then
    echo "Consul API is responding"
    break
  else
    echo "Consul API not ready yet, waiting... ($i/10)"
    sleep 10
  fi
done

# Final status check
echo "Final Consul status check..."
systemctl status consul --no-pager
consul members || echo "Consul members not available yet"
echo "Consul startup completed at $(date)"

# Configure log rotation
cat > /etc/logrotate.d/consul <<EOF
/var/log/consul/*.log {
    daily
    missingok
    rotate 30
    compress
    notifempty
    create 0640 consul consul
    postrotate
        /bin/kill -HUP \$(cat /var/run/consul/consul.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF

echo "Consul installation completed successfully at $(date)" 