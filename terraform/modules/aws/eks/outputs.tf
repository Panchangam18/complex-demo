output "cluster_id" {
  description = "The name/id of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_platform_version" {
  description = "The platform version for the cluster"
  value       = aws_eks_cluster.main.platform_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.eks_cluster.arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if enabled"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.eks[0].arn : null
}

output "oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = try(aws_eks_cluster.main.identity[0].oidc[0].issuer, null)
}

output "node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = aws_eks_node_group.main
}

output "node_iam_role_arn" {
  description = "IAM role ARN for EKS nodes"
  value       = aws_iam_role.eks_nodes.arn
}

output "node_security_group_id" {
  description = "Security group ID for pods"
  value       = aws_security_group.eks_pods.id
}

output "fargate_profiles" {
  description = "Map of attribute maps for all EKS Fargate profiles created"
  value       = aws_eks_fargate_profile.main
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for cluster logs"
  value       = aws_cloudwatch_log_group.eks.name
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for cluster autoscaler"
  value       = var.enable_irsa && var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].arn : null
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = var.enable_irsa && var.enable_aws_load_balancer_controller ? aws_iam_role.aws_load_balancer_controller[0].arn : null
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI Driver"
  value       = var.enable_irsa && var.enable_ebs_csi_driver ? aws_iam_role.ebs_csi_driver[0].arn : null
}

output "efs_csi_driver_role_arn" {
  description = "IAM role ARN for EFS CSI Driver"
  value       = var.enable_irsa && var.enable_efs_csi_driver ? aws_iam_role.efs_csi_driver[0].arn : null
}

output "external_dns_role_arn" {
  description = "IAM role ARN for External DNS"
  value       = var.enable_irsa ? aws_iam_role.external_dns[0].arn : null
}

output "fluent_bit_role_arn" {
  description = "IAM role ARN for Fluent Bit"
  value       = var.enable_irsa ? aws_iam_role.fluent_bit[0].arn : null
}

output "cluster_addons" {
  description = "Map of enabled EKS add-ons"
  value = {
    cluster_autoscaler          = var.enable_cluster_autoscaler
    aws_load_balancer_controller = var.enable_aws_load_balancer_controller
    ebs_csi_driver              = var.enable_ebs_csi_driver
    efs_csi_driver              = var.enable_efs_csi_driver
    metrics_server              = var.enable_metrics_server
  }
}

output "update_kubeconfig_command" {
  description = "Command to update kubeconfig file"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.main.name}"
}