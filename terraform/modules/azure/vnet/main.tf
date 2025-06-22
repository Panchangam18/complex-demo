# Azure VNet Module
# Creates a Hub VNet with public, private, and internal subnets following Hub-Spoke pattern

locals {
  # Azure uses availability zones (not all regions support them)
  # We'll create subnets that span zones for HA
  zones = var.availability_zones_enabled ? ["1", "2", "3"] : ["none"]
  
  # Calculate subnet ranges
  # Using /20 for each subnet (4096 IPs each)
  public_subnet_cidr   = cidrsubnet(var.vnet_cidr, 4, 0)
  private_subnet_cidr  = cidrsubnet(var.vnet_cidr, 4, 1)
  internal_subnet_cidr = cidrsubnet(var.vnet_cidr, 4, 2)
  gateway_subnet_cidr  = cidrsubnet(var.vnet_cidr, 8, 248)  # /24 for VPN/ExpressRoute
  firewall_subnet_cidr = cidrsubnet(var.vnet_cidr, 8, 249)  # /24 for Azure Firewall
  bastion_subnet_cidr  = cidrsubnet(var.vnet_cidr, 8, 250)  # /24 for Azure Bastion
}

# Resource Group
resource "azurerm_resource_group" "network" {
  name     = "${var.environment}-network-rg"
  location = var.azure_location
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Purpose     = "Network Infrastructure"
    }
  )
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.environment}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
    }
  )
}

# Network Security Groups
# Public NSG
resource "azurerm_network_security_group" "public" {
  name                = "${var.environment}-public-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Subnet      = "public"
    }
  )
}

# Private NSG
resource "azurerm_network_security_group" "private" {
  name                = "${var.environment}-private-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Subnet      = "private"
    }
  )
}

# Internal NSG
resource "azurerm_network_security_group" "internal" {
  name                = "${var.environment}-internal-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Subnet      = "internal"
    }
  )
}

# Subnets
# Public Subnet (for load balancers, public IPs)
resource "azurerm_subnet" "public" {
  name                 = "${var.environment}-public"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.public_subnet_cidr]
  
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.Sql",
    "Microsoft.KeyVault"
  ]
}

# Private Subnet (for application workloads)
resource "azurerm_subnet" "private" {
  name                 = "${var.environment}-private"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.private_subnet_cidr]
  
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.Sql",
    "Microsoft.KeyVault",
    "Microsoft.ServiceBus",
    "Microsoft.EventHub"
  ]
}

# Internal Subnet (for databases, internal services)
resource "azurerm_subnet" "internal" {
  name                 = "${var.environment}-internal"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.internal_subnet_cidr]
  
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.Sql"
  ]
  
  # Delegate to Azure Database for PostgreSQL if needed
  dynamic "delegation" {
    for_each = var.enable_postgresql_delegation ? [1] : []
    content {
      name = "postgresql-delegation"
      
      service_delegation {
        name = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = [
          "Microsoft.Network/virtualNetworks/subnets/join/action"
        ]
      }
    }
  }
}

# Gateway Subnet (required for VPN/ExpressRoute)
resource "azurerm_subnet" "gateway" {
  count = var.enable_gateway_subnet ? 1 : 0
  
  name                 = "GatewaySubnet"  # Must be named exactly this
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.gateway_subnet_cidr]
}

# Azure Firewall Subnet
resource "azurerm_subnet" "firewall" {
  count = var.enable_azure_firewall ? 1 : 0
  
  name                 = "AzureFirewallSubnet"  # Must be named exactly this
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.firewall_subnet_cidr]
}

# Azure Bastion Subnet
resource "azurerm_subnet" "bastion" {
  count = var.enable_bastion ? 1 : 0
  
  name                 = "AzureBastionSubnet"  # Must be named exactly this
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.bastion_subnet_cidr]
}

# Subnet NSG Associations
resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private.id
}

resource "azurerm_subnet_network_security_group_association" "internal" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.internal.id
}

# NSG Rules
# Allow internal VNet communication
resource "azurerm_network_security_rule" "allow_vnet_inbound" {
  for_each = {
    public   = azurerm_network_security_group.public.name
    private  = azurerm_network_security_group.private.name
    internal = azurerm_network_security_group.internal.name
  }
  
  name                        = "AllowVNetInBound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = each.value
}

# Allow Azure Load Balancer
resource "azurerm_network_security_rule" "allow_load_balancer" {
  name                        = "AllowAzureLoadBalancerInBound"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.public.name
}

# NAT Gateway for outbound connectivity
resource "azurerm_public_ip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
  
  name                = "${var.environment}-nat-pip"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.availability_zones_enabled ? ["1", "2", "3"] : []
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Purpose     = "NAT Gateway"
    }
  )
}

resource "azurerm_nat_gateway" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
  
  name                    = "${var.environment}-nat"
  location                = azurerm_resource_group.network.location
  resource_group_name     = azurerm_resource_group.network.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = var.availability_zones_enabled ? ["1", "2", "3"] : []
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
    }
  )
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
  
  nat_gateway_id       = azurerm_nat_gateway.nat[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# Associate NAT Gateway with private subnet
resource "azurerm_subnet_nat_gateway_association" "private" {
  count = var.enable_nat_gateway ? 1 : 0
  
  subnet_id      = azurerm_subnet.private.id
  nat_gateway_id = azurerm_nat_gateway.nat[0].id
}

# Network Watcher
resource "azurerm_network_watcher" "watcher" {
  count = var.enable_network_watcher ? 1 : 0
  
  name                = "${var.environment}-network-watcher"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
    }
  )
}

# Storage Account for Flow Logs
resource "azurerm_storage_account" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  name                     = replace("${var.environment}flowlogs${var.azure_location}", "-", "")
  resource_group_name      = azurerm_resource_group.network.name
  location                 = azurerm_resource_group.network.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Purpose     = "Flow Logs"
    }
  )
}

# NSG Flow Logs
resource "azurerm_network_watcher_flow_log" "public" {
  count = var.enable_flow_logs ? 1 : 0
  
  network_watcher_name = azurerm_network_watcher.watcher[0].name
  resource_group_name  = azurerm_resource_group.network.name
  name                 = "${var.environment}-public-flow-log"
  
  network_security_group_id = azurerm_network_security_group.public.id
  storage_account_id        = azurerm_storage_account.flow_logs[0].id
  enabled                   = true
  
  retention_policy {
    enabled = true
    days    = 30
  }
  
  traffic_analytics {
    enabled               = true
    workspace_id          = var.log_analytics_workspace_id
    workspace_region      = var.azure_location
    workspace_resource_id = var.log_analytics_workspace_resource_id
    interval_in_minutes   = 10
  }
}