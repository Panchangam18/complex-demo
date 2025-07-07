output "aws_s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "aws_s3_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "aws_dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "aws_dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "aws_backend_config" {
  description = "AWS S3 backend configuration for Terraform"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    region         = var.aws_region
    key            = "terraform.tfstate" # This will be overridden per environment
    dynamodb_table = aws_dynamodb_table.terraform_locks.id
    encrypt        = true
  }
}

output "backend_configuration" {
  description = "Backend configuration to use in terragrunt.hcl"
  value = {
    aws = {
      backend = "s3"
      config = {
        bucket         = aws_s3_bucket.terraform_state.id
        key            = "ENV/REGION/terraform.tfstate"
        region         = var.aws_region
        dynamodb_table = aws_dynamodb_table.terraform_locks.id
        encrypt        = true
      }
    }
  }
}