output "nexus_namespace" {
  description = "Namespace where Nexus is deployed"
  value       = kubernetes_namespace.nexus.metadata[0].name
}

output "nexus_service_name" {
  description = "Name of the Nexus service"
  value       = "nexus-terraform-nexus3"
}

output "nexus_url" {
  description = "URL to access Nexus Repository Manager"
  value       = var.service_type == "LoadBalancer" ? "http://$(kubectl get svc nexus-terraform-nexus3 -n ${kubernetes_namespace.nexus.metadata[0].name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081" : "http://nexus-terraform-nexus3.${kubernetes_namespace.nexus.metadata[0].name}.svc.cluster.local:8081"
}

output "nexus_external_url_command" {
  description = "Command to get the external Nexus URL"
  value       = "kubectl get svc nexus-terraform-nexus3 -n ${kubernetes_namespace.nexus.metadata[0].name} -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}:8081'"
}

output "nexus_admin_password_command" {
  description = "Command to retrieve Nexus admin password"
  value       = "kubectl exec -n ${kubernetes_namespace.nexus.metadata[0].name} nexus-terraform-nexus3-0 -- cat /nexus-data/admin.password"
}

output "docker_registry_url" {
  description = "Docker registry URL for Nexus"
  value       = var.service_type == "LoadBalancer" ? "$(kubectl get svc nexus-terraform-nexus3 -n ${kubernetes_namespace.nexus.metadata[0].name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8082" : "nexus-terraform-nexus3.${kubernetes_namespace.nexus.metadata[0].name}.svc.cluster.local:8082"
}

output "npm_registry_url" {
  description = "NPM registry URL for Nexus"
  value       = var.service_type == "LoadBalancer" ? "http://$(kubectl get svc nexus-terraform-nexus3 -n ${kubernetes_namespace.nexus.metadata[0].name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081/repository/npm-public/" : "http://nexus-terraform-nexus3.${kubernetes_namespace.nexus.metadata[0].name}.svc.cluster.local:8081/repository/npm-public/"
} 