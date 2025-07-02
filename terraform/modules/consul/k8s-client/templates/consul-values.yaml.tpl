global:
  name: consul
  datacenter: ${datacenter_name}
  
  # Gossip encryption
  gossipEncryption:
    secretName: consul-gossip-encryption-key
    secretKey: key

  # Federation configuration for WAN joining
  federation:
    enabled: ${wan_federation_secret != ""}
    k8sAuthMethodHost: https://kubernetes.default.svc.cluster.local:443
    
  # ACLs configuration
  acls:
    manageSystemACLs: ${enable_acls}
    %{ if enable_acls ~}
    bootstrapToken:
      secretName: consul-acl-token
      secretKey: token
    %{ endif ~}

# Client-only mode - NO server in K8s!
server:
  enabled: false

# Minimal Consul clients
client:
  enabled: true
  grpc: true
  
  # Minimal resource requests
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"
  
  # Join the primary datacenter
  join: ${primary_consul_servers}
  
  extraConfig: |
    {
      "datacenter": "${datacenter_name}",
      "primary_datacenter": "${primary_datacenter}",
      "retry_join": ${primary_consul_servers},
      "log_level": "INFO",
      "ports": {
        "grpc": 8502
      },
      "connect": {
        "enabled": ${enable_connect}
      }
    }

# UI disabled - use primary cluster UI
ui:
  enabled: false

# Minimal service mesh configuration
connectInject:
  enabled: ${enable_connect_inject}
  
  # Minimal resource requests
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"
  
  # Only inject when explicitly requested
  default: false

# Simplified service catalog sync
syncCatalog:
  enabled: ${enable_sync_catalog}
  toConsul: true
  toK8S: false
  
  # Minimal resources
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"
  
  consulNodeName: "k8s-${datacenter_name}"

# Disable heavy components for now
meshGateway:
  enabled: false

ingressGateways:
  enabled: false

terminatingGateways:
  enabled: false

# Disable metrics temporarily
prometheus:
  enabled: false

# Cleanup tests
tests:
  enabled: false 

# Minimal DNS configuration
dns:
  enabled: true
  enableRedirection: false 