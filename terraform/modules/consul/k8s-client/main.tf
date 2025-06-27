# Configure required providers  
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# Create namespace for Consul
resource "kubernetes_namespace" "consul" {
  metadata {
    name = "consul"
    labels = {
      name = "consul"
      "app.kubernetes.io/name" = "consul"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Create secret for gossip encryption
resource "kubernetes_secret" "gossip_key" {
  metadata {
    name      = "consul-gossip-encryption-key"
    namespace = kubernetes_namespace.consul.metadata[0].name
  }

  data = {
    key = var.gossip_key
  }

  type = "Opaque"
}

# Create secret for WAN federation
resource "kubernetes_secret" "wan_federation" {
  metadata {
    name      = "consul-federation"
    namespace = kubernetes_namespace.consul.metadata[0].name
  }

  data = {
    gossipEncryptionKey = var.gossip_key 
    caCert             = ""  # Will be populated by Consul
    caKey              = ""  # Will be populated by Consul
  }

  type = "Opaque"
}

# Create secret for ACL token if ACLs are enabled
resource "kubernetes_secret" "consul_acl_token" {
  count = var.enable_acls && var.consul_master_token != "" ? 1 : 0
  
  metadata {
    name      = "consul-acl-token"
    namespace = kubernetes_namespace.consul.metadata[0].name
  }

  data = {
    token = var.consul_master_token
  }

  type = "Opaque"
}

# Install Consul using Helm
resource "helm_release" "consul" {
  name       = "consul"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "consul"
  version    = var.consul_helm_version
  namespace  = kubernetes_namespace.consul.metadata[0].name
  
  # Custom values for multi-datacenter client setup
  values = [templatefile("${path.module}/templates/consul-values.yaml.tpl", {
    datacenter_name          = var.datacenter_name
    primary_datacenter       = var.primary_datacenter
    consul_image_tag         = var.consul_image_tag
    consul_k8s_image_tag     = var.consul_k8s_image_tag
    enable_connect           = var.enable_connect
    enable_connect_inject    = var.enable_connect_inject
    enable_ui                = var.enable_ui
    ui_service_type          = var.ui_service_type
    enable_prometheus_metrics = var.enable_prometheus_metrics
    enable_sync_catalog      = var.enable_sync_catalog
    enable_acls              = var.enable_acls
    mesh_gateway_replicas    = var.mesh_gateway_replicas
    client_replicas          = var.client_replicas
    primary_consul_servers   = jsonencode(var.primary_consul_servers)
    wan_federation_secret    = var.wan_federation_secret
  })]

  depends_on = [
    kubernetes_namespace.consul,
    kubernetes_secret.gossip_key,
    kubernetes_secret.wan_federation
  ]

  # Wait for deployment to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 120  # 2 minutes timeout - fail fast
} 