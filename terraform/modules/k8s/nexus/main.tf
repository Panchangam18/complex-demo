locals {
  nexus_namespace = "nexus-${var.environment}"
}

# Create namespace for Nexus
resource "kubernetes_namespace" "nexus" {
  metadata {
    name = local.nexus_namespace
    labels = {
      name = local.nexus_namespace
      environment = var.environment
      managed-by = "terraform"
    }
  }
}

# Create storage class for Nexus persistent storage (only if using EBS CSI driver)
resource "kubernetes_storage_class" "nexus" {
  count = var.storage_provisioner == "ebs.csi.aws.com" ? 1 : 0
  
  metadata {
    name = "nexus-ssd"
  }
  storage_provisioner = var.storage_provisioner
  reclaim_policy     = "Retain"
  parameters = {
    type = "gp3"
    iops = "3000"
    encrypted = "true"
  }
}

# Note: PVC is now created by Helm chart to avoid WaitForFirstConsumer circular dependency

# Deploy Nexus using Helm
resource "helm_release" "nexus" {
  name       = "nexus-repo"
  repository = "https://stevehipwell.github.io/helm-charts/"
  chart      = "nexus3"
  version    = var.nexus_chart_version
  namespace  = kubernetes_namespace.nexus.metadata[0].name

  values = [
    templatefile("${path.module}/templates/nexus-values.yaml.tpl", {
      environment = var.environment
      service_type = var.service_type
      ingress_enabled = var.ingress_enabled
      ingress_host = var.ingress_host
      cpu_request = var.cpu_request
      memory_request = var.memory_request
      cpu_limit = var.cpu_limit
      memory_limit = var.memory_limit
    })
  ]

  depends_on = [
    kubernetes_namespace.nexus
  ]
}

# Create service monitor for Prometheus scraping
resource "kubernetes_manifest" "nexus_service_monitor" {
  count = var.enable_monitoring ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "nexus"
      namespace = kubernetes_namespace.nexus.metadata[0].name
      labels = {
        app = "nexus"
        environment = var.environment
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "nexus"
        }
      }
      endpoints = [
        {
          port = "http"
          path = "/service/metrics/prometheus"
          interval = "30s"
        }
      ]
    }
  }
}

# Create ingress for Nexus UI
resource "kubernetes_ingress_v1" "nexus" {
  count = var.ingress_enabled ? 1 : 0

  metadata {
    name      = "nexus"
    namespace = kubernetes_namespace.nexus.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "alb"
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect" = "443"
      "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
    }
  }

  spec {
    rule {
      host = var.ingress_host
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "nexus-nexus-repository-manager"
              port {
                number = 8081
              }
            }
          }
        }
      }
    }
  }
} 