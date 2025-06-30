output "jenkins_url" {
  description = "URL to access Jenkins web interface"
  value       = "http://${aws_eip.jenkins_eip.public_ip}:8080"
}

output "jenkins_admin_username" {
  description = "Jenkins admin username"
  value       = "admin"
}

output "jenkins_admin_password" {
  description = "Jenkins admin password"
  value       = random_password.jenkins_admin_password.result
  sensitive   = true
}

output "jenkins_admin_password_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing Jenkins admin password"
  value       = aws_secretsmanager_secret.jenkins_admin_password.arn
}

output "jenkins_public_ip" {
  description = "Public IP address of Jenkins server"
  value       = aws_eip.jenkins_eip.public_ip
}

output "jenkins_private_ip" {
  description = "Private IP address of Jenkins server"
  value       = aws_instance.jenkins_server.private_ip
}

output "jenkins_instance_id" {
  description = "EC2 instance ID of Jenkins server"
  value       = aws_instance.jenkins_server.id
}

output "jenkins_security_group_id" {
  description = "Security group ID for Jenkins server"
  value       = aws_security_group.jenkins_sg.id
}

output "jenkins_key_pair_name" {
  description = "Name of the SSH key pair for Jenkins server"
  value       = aws_key_pair.jenkins_key.key_name
}

output "jenkins_ssh_private_key_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing SSH private key (if auto-generated)"
  value       = var.ssh_public_key == "" ? aws_secretsmanager_secret.jenkins_ssh_key[0].arn : ""
}

output "ssh_command" {
  description = "SSH command to connect to Jenkins server"
  value       = "ssh -i /path/to/your/private/key ec2-user@${aws_eip.jenkins_eip.public_ip}"
}

# Simple outputs - no complex integrations for now 