# Red Hat Ansible Automation Platform on Azure VMs
# This module deploys AAP using RHEL VMs with the containerized installer

# Resource group for Ansible Automation Platform
resource "azurerm_resource_group" "ansible_controller" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# Network Security Group for Ansible Controller
resource "azurerm_network_security_group" "ansible_controller" {
  name                = "${var.cluster_name}-nsg"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name

  # HTTPS access
  security_rule {
    name                       = "HTTPS"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTP access
  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # PostgreSQL access (for database)
  security_rule {
    name                       = "PostgreSQL"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "ansible_controller_lb" {
  name                = "${var.cluster_name}-lb-ip"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Load Balancer for Ansible Controller
resource "azurerm_lb" "ansible_controller" {
  name                = "${var.cluster_name}-lb"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.ansible_controller_lb.id
  }

  tags = var.tags
}

# Load Balancer Backend Pool
resource "azurerm_lb_backend_address_pool" "ansible_controller" {
  loadbalancer_id = azurerm_lb.ansible_controller.id
  name            = "${var.cluster_name}-backend-pool"
}

# Load Balancer Rule for HTTPS
resource "azurerm_lb_rule" "ansible_controller_https" {
  loadbalancer_id                = azurerm_lb.ansible_controller.id
  name                           = "HTTPSRule"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ansible_controller.id]
  probe_id                       = azurerm_lb_probe.ansible_controller_https.id
}

# Load Balancer Rule for HTTP
resource "azurerm_lb_rule" "ansible_controller_http" {
  loadbalancer_id                = azurerm_lb.ansible_controller.id
  name                           = "HTTPRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ansible_controller.id]
  probe_id                       = azurerm_lb_probe.ansible_controller_http.id
}

# Health Probe for HTTPS
resource "azurerm_lb_probe" "ansible_controller_https" {
  loadbalancer_id = azurerm_lb.ansible_controller.id
  name            = "https-probe"
  port            = 443
  protocol        = "Tcp"
}

# Health Probe for HTTP
resource "azurerm_lb_probe" "ansible_controller_http" {
  loadbalancer_id = azurerm_lb.ansible_controller.id
  name            = "http-probe"
  port            = 80
  protocol        = "Tcp"
}

# Public IP for direct VM access (optional)
resource "azurerm_public_ip" "ansible_controller_vm" {
  count               = var.enable_direct_public_ip ? var.controller_count : 0
  name                = "${var.cluster_name}-controller-${count.index + 1}-vm-ip"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Network Interface for Controller VM
resource "azurerm_network_interface" "ansible_controller" {
  count               = var.controller_count
  name                = "${var.cluster_name}-controller-${count.index + 1}-nic"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_direct_public_ip ? azurerm_public_ip.ansible_controller_vm[count.index].id : null
  }

  tags = var.tags
}

# Associate Network Security Group to Network Interface
resource "azurerm_network_interface_security_group_association" "ansible_controller" {
  count                     = var.controller_count
  network_interface_id      = azurerm_network_interface.ansible_controller[count.index].id
  network_security_group_id = azurerm_network_security_group.ansible_controller.id
}

# Associate Network Interface to Load Balancer Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "ansible_controller" {
  count                   = var.controller_count
  network_interface_id    = azurerm_network_interface.ansible_controller[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ansible_controller.id
}

# Virtual Machine for Ansible Controller
resource "azurerm_linux_virtual_machine" "ansible_controller" {
  count               = var.controller_count
  name                = "${var.cluster_name}-controller-${count.index + 1}"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name
  size                = var.vm_size
  admin_username      = var.admin_username

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.ansible_controller[count.index].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "8-lvm-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/user-data.sh"))

  tags = var.tags
}

# Data disk for Ansible Controller (for application data)
resource "azurerm_managed_disk" "ansible_controller_data" {
  count                = var.controller_count
  name                 = "${var.cluster_name}-controller-${count.index + 1}-data"
  location             = azurerm_resource_group.ansible_controller.location
  resource_group_name  = azurerm_resource_group.ansible_controller.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 256

  tags = var.tags
}

# Attach data disk to VM
resource "azurerm_virtual_machine_data_disk_attachment" "ansible_controller_data" {
  count              = var.controller_count
  managed_disk_id    = azurerm_managed_disk.ansible_controller_data[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.ansible_controller[count.index].id
  lun                = "0"
  caching            = "ReadWrite"
}

# Network Interface for Database VM
resource "azurerm_network_interface" "ansible_database" {
  name                = "${var.cluster_name}-database-nic"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

# Associate NSG to Database Network Interface
resource "azurerm_network_interface_security_group_association" "ansible_database" {
  network_interface_id      = azurerm_network_interface.ansible_database.id
  network_security_group_id = azurerm_network_security_group.ansible_controller.id
}

# Virtual Machine for Database
resource "azurerm_linux_virtual_machine" "ansible_database" {
  name                = "${var.cluster_name}-database"
  location            = azurerm_resource_group.ansible_controller.location
  resource_group_name = azurerm_resource_group.ansible_controller.name
  size                = var.database_vm_size
  admin_username      = var.admin_username

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.ansible_database.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "8-lvm-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/user-data.sh"))

  tags = var.tags
}

# Data disk for Database
resource "azurerm_managed_disk" "ansible_database_data" {
  name                 = "${var.cluster_name}-database-data"
  location             = azurerm_resource_group.ansible_controller.location
  resource_group_name  = azurerm_resource_group.ansible_controller.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 512

  tags = var.tags
}

# Attach data disk to Database VM
resource "azurerm_virtual_machine_data_disk_attachment" "ansible_database_data" {
  managed_disk_id    = azurerm_managed_disk.ansible_database_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.ansible_database.id
  lun                = "0"
  caching            = "ReadWrite"
} 