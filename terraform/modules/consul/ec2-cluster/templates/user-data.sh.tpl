#!/bin/bash
set -e

# Log output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Consul installation at $(date)"

# Update system
apt-get update
apt-get install -y curl unzip jq awscli

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
  "bind_addr": "{{ GetPrivateInterfaces | include \"network\" \"10.0.0.0/8\" | attr \"address\" }}",
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

# Start Consul
systemctl daemon-reload
systemctl enable consul
systemctl start consul

# Wait for Consul to start
sleep 30

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