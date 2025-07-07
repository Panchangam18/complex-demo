global:
  name: consul
  datacenter: ${datacenter_name}
  
  # Gossip encryption
  gossipEncryption:
    secretName: consul-gossip-encryption-key
    secretKey: key

  # Simplified federation configuration 
  federation:
    enabled: true
    k8sAuthMethodHost: https://kubernetes.default.svc.cluster.local:443
    primaryDatacenter: ${primary_datacenter}
    primaryGateways: ${primary_consul_servers}
    k8sSecretName: consul-federation
    k8sSecretKey: serverConfigJSON

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
  
  extraConfig: |
    {
      "datacenter": "${datacenter_name}",
      "primary_datacenter": "${primary_datacenter}",
      "retry_join_wan": ${primary_consul_servers},
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

  # Disable Gateway API CRDs to prevent conflicts with GKE Autopilot
  apiGateway:
    manageExternalCRDs: false

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

# Enable mesh gateway for cross-cloud communication
meshGateway:
  enabled: true
  replicas: 1
  
  # Service configuration for mesh gateway  
  service:
    type: LoadBalancer
    port: 8443
    annotations: |
      cloud.google.com/load-balancer-type: "External"
  
  # Resource allocation
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
  
  # Mesh gateway configuration
  wanAddress:
    source: "Service"
    port: 8443

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