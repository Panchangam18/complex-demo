output "vnet_id" {
  description = "ID of the VNet"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Name of the VNet"
  value       = azurerm_virtual_network.vnet.name
}

output "vnet_address_space" {
  description = "Address space of the VNet"
  value       = azurerm_virtual_network.vnet.address_space
}

output "resource_group_name" {
  description = "Name of the network resource group"
  value       = azurerm_resource_group.network.name
}

output "resource_group_location" {
  description = "Location of the network resource group"
  value       = azurerm_resource_group.network.location
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = azurerm_subnet.public.id
}

output "public_subnet_name" {
  description = "Name of the public subnet"
  value       = azurerm_subnet.public.name
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = azurerm_subnet.private.id
}

output "private_subnet_name" {
  description = "Name of the private subnet"
  value       = azurerm_subnet.private.name
}

output "internal_subnet_id" {
  description = "ID of the internal subnet"
  value       = azurerm_subnet.internal.id
}

output "internal_subnet_name" {
  description = "Name of the internal subnet"
  value       = azurerm_subnet.internal.name
}

output "gateway_subnet_id" {
  description = "ID of the gateway subnet"
  value       = try(azurerm_subnet.gateway[0].id, null)
}

output "firewall_subnet_id" {
  description = "ID of the firewall subnet"
  value       = try(azurerm_subnet.firewall[0].id, null)
}

output "bastion_subnet_id" {
  description = "ID of the bastion subnet"
  value       = try(azurerm_subnet.bastion[0].id, null)
}

output "public_nsg_id" {
  description = "ID of the public NSG"
  value       = azurerm_network_security_group.public.id
}

output "private_nsg_id" {
  description = "ID of the private NSG"
  value       = azurerm_network_security_group.private.id
}

output "internal_nsg_id" {
  description = "ID of the internal NSG"
  value       = azurerm_network_security_group.internal.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = try(azurerm_nat_gateway.nat[0].id, null)
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value       = try(azurerm_public_ip.nat[0].ip_address, null)
}

output "network_watcher_id" {
  description = "ID of the Network Watcher"
  value       = try(azurerm_network_watcher.watcher[0].id, null)
}

output "flow_logs_storage_account_id" {
  description = "ID of the storage account for flow logs"
  value       = try(azurerm_storage_account.flow_logs[0].id, null)
}