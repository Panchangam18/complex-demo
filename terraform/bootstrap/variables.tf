variable "aws_region" {
  description = "AWS region for backend resources"
  type        = string
  default     = "us-east-2"
}

variable "bucket_suffix" {
  description = "Suffix for bucket names. If not provided, a random suffix will be generated."
  type        = string
  default     = ""
}