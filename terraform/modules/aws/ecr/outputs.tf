output "repository_urls" {
  description = "Map of repository names to URLs"
  value       = { for k, v in aws_ecr_repository.main : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository names to ARNs"
  value       = { for k, v in aws_ecr_repository.main : k => v.arn }
}

output "registry_id" {
  description = "The registry ID where the repositories were created"
  value       = length(aws_ecr_repository.main) > 0 ? values(aws_ecr_repository.main)[0].registry_id : null
}

output "ecr_pull_role_arn" {
  description = "ARN of the IAM role for ECR pull operations"
  value       = aws_iam_role.ecr_pull.arn
}

output "pull_through_cache_rules" {
  description = "List of pull through cache rules created"
  value = {
    docker_hub = var.environment == "prod" ? aws_ecr_pull_through_cache_rule.docker_hub[0].ecr_repository_prefix : null
    ecr_public = var.environment == "prod" ? aws_ecr_pull_through_cache_rule.ecr_public[0].ecr_repository_prefix : null
    kubernetes = var.environment == "prod" ? aws_ecr_pull_through_cache_rule.kubernetes[0].ecr_repository_prefix : null
    quay       = var.environment == "prod" ? aws_ecr_pull_through_cache_rule.quay[0].ecr_repository_prefix : null
  }
}