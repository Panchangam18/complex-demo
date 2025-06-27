global:
  name: consul
  datacenter: ${datacenter_name}
  
  # Gossip encryption
  gossipEncryption:
    secretName: consul-gossip-encryption-key
    secretKey: key

# Simple single-node server for dev
server:
  enabled: true
  replicas: 1
  bootstrapExpect: 1
  
  # NO persistent storage - use emptyDir
  storage: ""
  storageClass: ""
  
  # Dev mode configuration
  extraConfig: |
    {
      "server": true,
      "bootstrap_expect": 1,
      "ui_config": {
        "enabled": true
      },
      "log_level": "INFO",
      "data_dir": "/tmp/consul",
      "disable_host_node_id": true
    }

# Simple client
client:
  enabled: true
  grpc: true

# Simple UI
ui:
  enabled: ${enable_ui}
  service:
    type: ${ui_service_type}

# Disable everything else that causes problems
connectInject:
  enabled: false

syncCatalog:
  enabled: false

meshGateway:
  enabled: false

ingressGateways:
  enabled: false

terminatingGateways:
  enabled: false

prometheus:
  enabled: false

tests:
  enabled: false 