#!/bin/bash
set -e

# Log output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Consul installation v5 at $(date)"

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
curl -O https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip
unzip consul_${consul_version}_linux_amd64.zip
mv consul /usr/local/bin/
chmod +x /usr/local/bin/consul

# Create consul user
useradd --system --home /var/lib/consul --shell /bin/false consul

# Create directories
mkdir -p /opt/consul /var/lib/consul /etc/consul.d /var/log/consul
chown -R consul:consul /opt/consul /var/lib/consul /etc/consul.d /var/log/consul

# Get the private IP address
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Generate Consul configuration
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
    "grpc": 8502
  },
  "client_addr": "0.0.0.0",
  "bind_addr": "$PRIVATE_IP",
  "retry_join": ["provider=aws tag_key=ConsulAutoJoin tag_value=${retry_join_tag} region=${aws_region}"],
%{ if primary_datacenter ~}
  "primary_datacenter": "${datacenter}",
%{ endif ~}
%{ if enable_acls ~}
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "enable_token_persistence": true,
    "down_policy": "extend-cache"
  },
%{ endif ~}
# WAN federation configuration removed - not needed for basic setup
  "performance": {
    "raft_multiplier": 1
  }
}
EOF

# Create systemd service
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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Validate configuration
echo "Validating Consul configuration..."
/usr/local/bin/consul validate /etc/consul.d/consul.json

# Start Consul
echo "Starting Consul service..."
systemctl daemon-reload
systemctl enable consul
systemctl start consul

# Wait for Consul to start and validate
echo "Waiting for Consul to start..."
for i in {1..12}; do
  if systemctl is-active --quiet consul; then
    echo "Consul service is active"
    break
  else
    echo "Consul not ready yet, waiting... ($i/12)"
    sleep 10
  fi
done

# Final status check
systemctl status consul --no-pager
echo "Consul startup completed at $(date)"

%{ if enable_acls && server_index == 0 ~}
# Bootstrap ACLs (only on first server)
echo "Bootstrapping ACL system..."
for i in {1..10}; do
  if consul acl bootstrap -format=json > /tmp/acl-bootstrap.json 2>/dev/null; then
    echo "ACL bootstrap successful"
    break
  else
    echo "ACL bootstrap attempt $i failed, retrying in 10 seconds..."
    sleep 10
  fi
done

# Set the master token if ACL bootstrap was successful
if [ -f /tmp/acl-bootstrap.json ]; then
  MASTER_TOKEN=$(jq -r .SecretID /tmp/acl-bootstrap.json)
  export CONSUL_HTTP_TOKEN=$MASTER_TOKEN
  
  # Create agent policy
  consul acl policy create \
    -name "agent-policy" \
    -description "Policy for Consul agents" \
    -rules 'node_prefix "" { policy = "write" } service_prefix "" { policy = "read" }'
  
  # Create agent token
  consul acl token create \
    -description "Agent token" \
    -policy-name "agent-policy" \
    -format=json > /tmp/agent-token.json
  
  AGENT_TOKEN=$(jq -r .SecretID /tmp/agent-token.json)
  consul acl set-agent-token agent "$AGENT_TOKEN"
fi
%{ endif ~}

# Install and configure Envoy (for Connect)
%{ if enable_connect ~}
echo "Installing Envoy for Consul Connect..."
curl -L https://getenvoy.io/cli | bash -s -- -b /usr/local/bin
/usr/local/bin/getenvoy run standard:1.22.2 -- --version || true
%{ endif ~}

# Configure mesh gateway for WAN federation
%{ if wan_federation_secret != "" ~}
echo "Configuring mesh gateway for WAN federation..."

# Create mesh gateway configuration
cat > /etc/consul.d/mesh-gateway.json <<EOF
{
  "service": {
    "name": "mesh-gateway",
    "kind": "mesh-gateway",
    "port": 8443,
    "proxy": {
      "config": {
        "envoy_mesh_gateway_bind_tagged_addresses": true,
        "envoy_mesh_gateway_bind_addresses": {
          "wan": {
            "address": "{{ GetPrivateInterfaces | include \"network\" \"10.0.0.0/8\" | attr \"address\" }}",
            "port": 8443
          }
        }
      }
    }
  }
}
EOF

# Create mesh gateway systemd service
cat > /etc/systemd/system/consul-mesh-gateway.service <<EOF
[Unit]
Description=Consul Mesh Gateway
Documentation=https://www.consul.io/
Requires=consul.service
After=consul.service
ConditionFileNotEmpty=/etc/consul.d/mesh-gateway.json

[Service]
Type=exec
User=consul
Group=consul
ExecStart=/usr/local/bin/consul connect envoy -mesh-gateway -register -service mesh-gateway -address "{{ GetPrivateInterfaces | include \"network\" \"10.0.0.0/8\" | attr \"address\" }}:8443"
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=2
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable and start mesh gateway service
systemctl daemon-reload
systemctl enable consul-mesh-gateway
systemctl start consul-mesh-gateway
%{ endif ~}

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

# Create health check script
cat > /usr/local/bin/consul-health-check.sh <<'EOF'
#!/bin/bash
# Simple health check for Consul
curl -f http://localhost:8500/v1/agent/self > /dev/null 2>&1
exit $?
EOF
chmod +x /usr/local/bin/consul-health-check.sh

# Add consul health check to cron
echo "*/1 * * * * consul /usr/local/bin/consul-health-check.sh || /bin/systemctl restart consul" | crontab -u consul -

echo "Consul installation completed at $(date)"
echo "Consul status:"
systemctl status consul --no-pager 