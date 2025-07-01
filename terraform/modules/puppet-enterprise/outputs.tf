output "puppet_enterprise_url" {
  description = "URL to access Puppet Enterprise Console"
  value       = "https://${aws_instance.puppet_enterprise_server.public_ip}"
}

output "puppet_server_url" {
  description = "URL to access Puppet Server"
  value       = "https://${aws_instance.puppet_enterprise_server.public_ip}:8140"
}

output "puppetdb_url" {
  description = "URL to access PuppetDB"
  value       = "https://${aws_instance.puppet_enterprise_server.public_ip}:8081"
}

output "puppet_enterprise_public_ip" {
  description = "Public IP address of Puppet Enterprise server"
  value       = aws_instance.puppet_enterprise_server.public_ip
}

output "puppet_enterprise_private_ip" {
  description = "Private IP address of Puppet Enterprise server"
  value       = aws_instance.puppet_enterprise_server.private_ip
}

output "puppet_enterprise_instance_id" {
  description = "Instance ID of Puppet Enterprise server"
  value       = aws_instance.puppet_enterprise_server.id
}

output "puppet_enterprise_admin_username" {
  description = "Puppet Enterprise Console admin username"
  value       = "admin"
}

output "puppet_enterprise_admin_password_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing PE admin password"
  value       = aws_secretsmanager_secret.pe_console_admin_password.arn
}

output "puppet_enterprise_ssh_key_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing SSH private key"
  value       = var.generate_ssh_key ? aws_secretsmanager_secret.puppet_ssh_key[0].arn : ""
}

output "puppet_enterprise_ssh_command" {
  description = "SSH command to connect to Puppet Enterprise server"
  value       = "ssh -i /path/to/private/key ec2-user@${aws_instance.puppet_enterprise_server.public_ip}"
}

output "puppet_enterprise_fqdn" {
  description = "Fully qualified domain name of Puppet Enterprise server"
  value       = "puppet-enterprise.${var.environment}.local"
}

output "puppet_enterprise_summary" {
  description = "Summary of Puppet Enterprise deployment"
  value = {
    console_url     = "https://${aws_instance.puppet_enterprise_server.public_ip}"
    puppet_server   = "https://${aws_instance.puppet_enterprise_server.public_ip}:8140"
    puppetdb        = "https://${aws_instance.puppet_enterprise_server.public_ip}:8081"
    orchestrator    = "https://${aws_instance.puppet_enterprise_server.public_ip}:8142"
    code_manager    = "https://${aws_instance.puppet_enterprise_server.public_ip}:8170"
    public_ip       = aws_instance.puppet_enterprise_server.public_ip
    private_ip      = aws_instance.puppet_enterprise_server.private_ip
    instance_id     = aws_instance.puppet_enterprise_server.id
    fqdn           = "puppet-enterprise.${var.environment}.local"
    admin_username  = "admin"
    admin_password_secret = aws_secretsmanager_secret.pe_console_admin_password.arn
  }
} 