# =============================================
# Azure Kubernetes Service (AKS) Module - Simplified
# =============================================

# Data sources
data "azurerm_client_config" "current" {}

# Resource Group for AKS (separate from networking)
resource "azurerm_resource_group" "aks" {
  name     = "${var.environment}-aks-rg"
  location = var.azure_location
  
  tags = var.common_tags
}

# AKS Cluster - Basic Configuration
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "${var.environment}-aks"
  kubernetes_version  = var.kubernetes_version
  
  # Default node pool
  default_node_pool {
    name           = "system"
    node_count     = var.system_node_count
    vm_size        = var.system_vm_size
    vnet_subnet_id = var.private_subnet_id
    
    tags = var.common_tags
  }
  
  # Use system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Network configuration
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
  
  tags = var.common_tags
}

# Container Registry (ACR) for AKS
resource "azurerm_container_registry" "main" {
  count = var.enable_acr ? 1 : 0
  
  name                = replace("${var.environment}acr${random_id.acr_suffix[0].hex}", "-", "")
  resource_group_name = azurerm_resource_group.aks.name
  location           = azurerm_resource_group.aks.location
  sku                = var.acr_sku
  admin_enabled      = false
  
  tags = var.common_tags
}

resource "random_id" "acr_suffix" {
  count = var.enable_acr ? 1 : 0
  byte_length = 4
}

# Role assignment for AKS to pull from ACR
resource "azurerm_role_assignment" "acr_pull" {
  count = var.enable_acr ? 1 : 0
  
  scope                = azurerm_container_registry.main[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
} 