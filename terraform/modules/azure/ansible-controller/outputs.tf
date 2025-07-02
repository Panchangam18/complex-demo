output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.ansible_controller.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.ansible_controller.id
}

output "public_ip_address" {
  description = "Public IP address of the load balancer"
  value       = azurerm_public_ip.ansible_controller_lb.ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the public IP"
  value       = azurerm_public_ip.ansible_controller_lb.fqdn
}

output "controller_direct_public_ips" {
  description = "Direct public IP addresses of controller VMs"
  value       = var.enable_direct_public_ip ? azurerm_public_ip.ansible_controller_vm[*].ip_address : []
}

output "controller_private_ips" {
  description = "Private IP addresses of controller VMs"
  value       = azurerm_network_interface.ansible_controller[*].private_ip_address
}

output "database_private_ip" {
  description = "Private IP address of database VM"
  value       = azurerm_network_interface.ansible_database.private_ip_address
}

output "controller_vm_names" {
  description = "Names of controller VMs"
  value       = azurerm_linux_virtual_machine.ansible_controller[*].name
}

output "database_vm_name" {
  description = "Name of database VM"
  value       = azurerm_linux_virtual_machine.ansible_database.name
}

output "ssh_connection_commands" {
  description = "SSH connection commands"
  value = {
    controllers = [
      for i, vm in azurerm_linux_virtual_machine.ansible_controller :
      "ssh ${var.admin_username}@${azurerm_network_interface.ansible_controller[i].private_ip_address}"
    ]
    database = "ssh ${var.admin_username}@${azurerm_network_interface.ansible_database.private_ip_address}"
  }
}

output "ansible_tower_url" {
  description = "Ansible Tower web interface URL"
  value       = "https://${azurerm_public_ip.ansible_controller_lb.ip_address}"
}

output "ansible_tower_direct_urls" {
  description = "Direct HTTPS URLs to controller VMs"
  value       = var.enable_direct_public_ip ? [for ip in azurerm_public_ip.ansible_controller_vm[*].ip_address : "https://${ip}"] : []
}

output "ansible_tower_credentials" {
  description = "Ansible Tower login credentials"
  value = {
    load_balancer_url = "https://${azurerm_public_ip.ansible_controller_lb.ip_address}"
    direct_urls       = var.enable_direct_public_ip ? [for ip in azurerm_public_ip.ansible_controller_vm[*].ip_address : "https://${ip}"] : []
    admin_username    = "admin"
    admin_password    = "AnsibleTower123!"
    database_password = "PostgresPass123!"
  }
  sensitive = true
}

output "status_check_commands" {
  description = "Commands to check Ansible Tower status"
  value = {
    tower_status = "az vm run-command invoke --resource-group ${azurerm_resource_group.ansible_controller.name} --name ${azurerm_linux_virtual_machine.ansible_controller[0].name} --command-id RunShellScript --scripts '/opt/ansible/check-tower-status.sh'"
    service_status = "az vm run-command invoke --resource-group ${azurerm_resource_group.ansible_controller.name} --name ${azurerm_linux_virtual_machine.ansible_controller[0].name} --command-id RunShellScript --scripts 'systemctl status ansible-tower-web ansible-tower-task postgresql --no-pager'"
    view_logs = "az vm run-command invoke --resource-group ${azurerm_resource_group.ansible_controller.name} --name ${azurerm_linux_virtual_machine.ansible_controller[0].name} --command-id RunShellScript --scripts 'tail -50 /var/log/ansible-tower-install.log'"
  }
}

output "next_steps" {
  description = "Next steps for accessing Ansible Tower"
  value = {
    step_1 = "Wait 10-15 minutes for Ansible Tower installation to complete automatically"
    step_2 = "Check installation status using the status_check_commands outputs"
    step_3_lb = "Access Ansible Tower via load balancer: https://${azurerm_public_ip.ansible_controller_lb.ip_address}"
    step_3_direct = var.enable_direct_public_ip ? "Access Ansible Tower directly: ${join(", ", [for ip in azurerm_public_ip.ansible_controller_vm[*].ip_address : "https://${ip}"])}" : "Direct access disabled"
    step_4 = "Login with username: admin, password: AnsibleTower123!"
    step_5 = "Verify all services are running and configure your automation workflows"
    note = "Use direct URLs if load balancer has connectivity issues"
  }
} 