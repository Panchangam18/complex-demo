# =============================================
# Azure AKS Module Outputs - Simplified
# =============================================

# Cluster information
output "cluster_id" {
  description = "The ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for the AKS control plane"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "kube_config" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

# Resource Group information
output "resource_group_name" {
  description = "Name of the AKS resource group"
  value       = azurerm_resource_group.aks.name
}

output "node_resource_group" {
  description = "Name of the AKS node resource group"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

# Container Registry information
output "acr_id" {
  description = "ID of the Azure Container Registry"
  value       = var.enable_acr ? azurerm_container_registry.main[0].id : null
}

output "acr_login_server" {
  description = "Login server for the Azure Container Registry"
  value       = var.enable_acr ? azurerm_container_registry.main[0].login_server : null
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = var.enable_acr ? azurerm_container_registry.main[0].name : null
}

# Kubectl command
output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

# Connection summary
output "aks_connection_info" {
  description = "Complete AKS connection information"
  value = {
    cluster_name           = azurerm_kubernetes_cluster.main.name
    resource_group         = azurerm_resource_group.aks.name
    location              = azurerm_resource_group.aks.location
    kubernetes_version    = azurerm_kubernetes_cluster.main.kubernetes_version
    node_resource_group   = azurerm_kubernetes_cluster.main.node_resource_group
    kubectl_command       = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.main.name}"
    acr_enabled          = var.enable_acr
  }
} 