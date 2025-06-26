output "argocd_url" {
  description = "ArgoCD server public URL"
  value       = "http://${data.external.argocd_info.result.argocd_url}"
}

output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = data.external.argocd_info.result.argocd_password
  sensitive   = true
}

output "grafana_url" {
  description = "Grafana public URL"
  value       = "http://${data.external.argocd_info.result.grafana_url}"
}

output "grafana_admin_username" {
  description = "Grafana admin username"
  value       = "admin"
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = "admin123"
  sensitive   = true
}

output "prometheus_url" {
  description = "Prometheus public URL"
  value       = "http://${data.external.argocd_info.result.prometheus_url}"
}

output "observability_summary" {
  description = "Summary of all observability endpoints and credentials"
  value = <<-EOT
╔════════════════════════════════════════════════════════════════════════════╗
║                            🚀 OBSERVABILITY STACK                          ║
╠════════════════════════════════════════════════════════════════════════════╣
║                                                                            ║
║  🔄 ArgoCD (GitOps Platform)                                              ║
║     URL:      http://${data.external.argocd_info.result.argocd_url}
║     Username: admin                                                        ║
║     Password: ${data.external.argocd_info.result.argocd_password}
║                                                                            ║
║  📊 Grafana (Monitoring Dashboards)                                       ║
║     URL:      http://${data.external.argocd_info.result.grafana_url}
║     Username: admin                                                        ║
║     Password: admin123                                                     ║
║                                                                            ║
║  📈 Prometheus (Metrics Database)                                         ║
║     URL:      http://${data.external.argocd_info.result.prometheus_url}
║     Access:   Public                                                      ║
║                                                                            ║
║  🔔 AlertManager (Alert Management)                                       ║
║     URL:      prometheus-alertmanager.observability.svc.cluster.local:9093║
║     Access:   Internal cluster access only                                ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
  EOT
} 