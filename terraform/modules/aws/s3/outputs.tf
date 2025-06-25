output "bucket_ids" {
  description = "Map of bucket names to their IDs"
  value = {
    for k, v in aws_s3_bucket.buckets : k => v.id
  }
}

output "bucket_arns" {
  description = "Map of bucket names to their ARNs"
  value = {
    for k, v in aws_s3_bucket.buckets : k => v.arn
  }
}

output "bucket_domain_names" {
  description = "Map of bucket names to their domain names"
  value = {
    for k, v in aws_s3_bucket.buckets : k => v.bucket_domain_name
  }
}

output "bucket_regional_domain_names" {
  description = "Map of bucket names to their regional domain names"
  value = {
    for k, v in aws_s3_bucket.buckets : k => v.bucket_regional_domain_name
  }
}

output "thanos_bucket_id" {
  description = "The ID of the Thanos metrics bucket"
  value       = aws_s3_bucket.buckets["thanos"].id
}

output "thanos_bucket_arn" {
  description = "The ARN of the Thanos metrics bucket"
  value       = aws_s3_bucket.buckets["thanos"].arn
}

output "elasticsearch_bucket_id" {
  description = "The ID of the Elasticsearch snapshots bucket"
  value       = aws_s3_bucket.buckets["elasticsearch"].id
}

output "elasticsearch_bucket_arn" {
  description = "The ARN of the Elasticsearch snapshots bucket"
  value       = aws_s3_bucket.buckets["elasticsearch"].arn
}

output "app_assets_bucket_id" {
  description = "The ID of the application assets bucket"
  value       = aws_s3_bucket.buckets["app_assets"].id
}

output "app_assets_bucket_arn" {
  description = "The ARN of the application assets bucket"
  value       = aws_s3_bucket.buckets["app_assets"].arn
}

output "replication_role_arn" {
  description = "ARN of the replication role (if replication is enabled)"
  value       = var.enable_replication ? aws_iam_role.replication[0].arn : null
}