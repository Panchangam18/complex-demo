output "consul_namespace" {
  description = "Kubernetes namespace where Consul is deployed"
  value       = kubernetes_namespace.consul.metadata[0].name
}

output "consul_helm_release" {
  description = "Consul Helm release information"
  value = {
    name      = helm_release.consul.name
    namespace = helm_release.consul.namespace
    version   = helm_release.consul.version
    status    = helm_release.consul.status
  }
}

output "datacenter_name" {
  description = "Consul datacenter name for this K8s cluster"
  value       = var.datacenter_name
}

output "primary_datacenter" {
  description = "Primary Consul datacenter name"
  value       = var.primary_datacenter
}

output "consul_ui_service" {
  description = "Consul UI service information"
  value = var.enable_ui ? {
    name      = "consul-ui"
    namespace = kubernetes_namespace.consul.metadata[0].name
    type      = var.ui_service_type
  } : null
}

output "mesh_gateway_service" {
  description = "Mesh gateway service information"
  value = {
    name      = "consul-mesh-gateway"
    namespace = kubernetes_namespace.consul.metadata[0].name
    port      = 8443
  }
}

output "consul_dns_service" {
  description = "Consul DNS service information"
  value = {
    name      = "consul-dns"
    namespace = kubernetes_namespace.consul.metadata[0].name
    port      = 53
  }
}

output "connect_enabled" {
  description = "Whether Consul Connect is enabled"
  value       = var.enable_connect
}

output "connect_inject_enabled" {
  description = "Whether automatic Connect injection is enabled"
  value       = var.enable_connect_inject
}

output "sync_catalog_enabled" {
  description = "Whether catalog sync is enabled"
  value       = var.enable_sync_catalog
}

output "consul_client_info" {
  description = "Complete Consul client information"
  value = {
    datacenter           = var.datacenter_name
    primary_datacenter   = var.primary_datacenter
    namespace           = kubernetes_namespace.consul.metadata[0].name
    connect_enabled     = var.enable_connect
    ui_enabled          = var.enable_ui
    metrics_enabled     = var.enable_prometheus_metrics
    acls_enabled        = var.enable_acls
    mesh_gateway_port   = 8443
  }
} 