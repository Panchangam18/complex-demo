global:
  name: consul
  datacenter: ${datacenter_name}
  
  # External servers configuration - points to primary consul servers
  externalServers:
    enabled: true
%{ if length(mesh_gateway_endpoints) > 0 && cloud_provider == "gcp" ~}
    # For cross-cloud GKE, use public mesh gateway endpoints
    hosts: ${mesh_gateway_endpoints}
%{ else ~}
    # For same-cloud or AWS, use private server IPs
    hosts: ${primary_consul_servers}
%{ endif ~}
    httpPort: 8500
    grpcPort: 8502
    k8sAuthMethodHost: https://kubernetes.default.svc.cluster.local:443
    useSystemRoots: false
  
  # Gossip encryption
  gossipEncryption:
    secretName: consul-gossip-encryption-key
    secretKey: key

  # Simplified federation configuration 
  federation:
    enabled: false
    k8sAuthMethodHost: https://kubernetes.default.svc.cluster.local:443
    k8sSecretName: consul-federation
    k8sSecretKey: serverConfigJSON
    primaryDatacenter: ${primary_datacenter}

# FIXED: Disable connect-injector to avoid external servers compatibility issues
connectInject:
  enabled: false
  # Connect injection is disabled for external servers deployment
  # This avoids the DNS resolution bug where connect-injector tries to resolve consul-server.consul.svc

# Explicitly disable clients since we're using external servers
client:
  enabled: false

# Configure server to be disabled (external servers mode)
server:
  enabled: false

# Disable mesh gateway since it requires connectInject (which we disabled)
meshGateway:
  enabled: false

# Disable catalog sync as it's not needed for infrastructure deployment
syncCatalog:
  enabled: false

# Disable ingress gateways for infrastructure deployment
ingressGateways:
  enabled: false

# Disable terminating gateways for infrastructure deployment  
terminatingGateways:
  enabled: false

# UI is handled by the external servers
ui:
  enabled: false

# Minimal DNS configuration
dns:
  enabled: true
  enableRedirection: false 