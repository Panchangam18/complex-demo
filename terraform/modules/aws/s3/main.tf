locals {
  thanos_bucket_name        = var.thanos_bucket_name != "" ? var.thanos_bucket_name : "thanos-metrics-${var.environment}-${var.region}-${data.aws_caller_identity.current.account_id}"
  elasticsearch_bucket_name = var.elasticsearch_bucket_name != "" ? var.elasticsearch_bucket_name : "elasticsearch-snapshots-${var.environment}-${data.aws_caller_identity.current.account_id}"
  app_assets_bucket_name    = var.app_assets_bucket_name != "" ? var.app_assets_bucket_name : "app-assets-${var.environment}-${var.region}-${data.aws_caller_identity.current.account_id}"
  
  buckets = {
    thanos = {
      name           = local.thanos_bucket_name
      lifecycle_rule = var.lifecycle_rules.thanos
    }
    elasticsearch = {
      name           = local.elasticsearch_bucket_name
      lifecycle_rule = var.lifecycle_rules.elasticsearch
    }
    app_assets = {
      name           = local.app_assets_bucket_name
      lifecycle_rule = var.lifecycle_rules.app_assets
    }
  }
}

data "aws_caller_identity" "current" {}

################################################################################
# S3 Buckets
################################################################################

resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets

  bucket = each.value.name

  tags = merge(
    var.tags,
    {
      Name        = each.value.name
      Environment = var.environment
      Purpose     = each.key
    }
  )
}

resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = local.buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "buckets" {
  for_each = var.enable_versioning ? local.buckets : {}

  bucket = aws_s3_bucket.buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = var.enable_encryption ? local.buckets : {}

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null ? true : false
  }
}

################################################################################
# Lifecycle Rules
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "buckets" {
  for_each = { for k, v in local.buckets : k => v if v.lifecycle_rule.expiration_days > 0 || v.lifecycle_rule.transition_to_ia_days > 0 }

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    id     = "${each.key}-lifecycle-rule"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = each.value.lifecycle_rule.transition_to_ia_days > 0 ? [1] : []
      content {
        days          = each.value.lifecycle_rule.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = each.value.lifecycle_rule.transition_to_glacier_days > 0 ? [1] : []
      content {
        days          = each.value.lifecycle_rule.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    dynamic "expiration" {
      for_each = each.value.lifecycle_rule.expiration_days > 0 ? [1] : []
      content {
        days = each.value.lifecycle_rule.expiration_days
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

################################################################################
# Bucket Policies
################################################################################

# Thanos bucket policy - Allow Thanos components to read/write
data "aws_iam_policy_document" "thanos_bucket_policy" {
  statement {
    sid    = "AllowThanosList"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:ListBucketMultipartUploads"
    ]
    
    resources = [aws_s3_bucket.buckets["thanos"].arn]
  }
  
  statement {
    sid    = "AllowThanosReadWrite"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    
    resources = ["${aws_s3_bucket.buckets["thanos"].arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "thanos" {
  bucket = aws_s3_bucket.buckets["thanos"].id
  policy = data.aws_iam_policy_document.thanos_bucket_policy.json
}

# Elasticsearch bucket policy
data "aws_iam_policy_document" "elasticsearch_bucket_policy" {
  statement {
    sid    = "AllowElasticsearchList"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    
    resources = [aws_s3_bucket.buckets["elasticsearch"].arn]
  }
  
  statement {
    sid    = "AllowElasticsearchReadWrite"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    
    resources = ["${aws_s3_bucket.buckets["elasticsearch"].arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "elasticsearch" {
  bucket = aws_s3_bucket.buckets["elasticsearch"].id
  policy = data.aws_iam_policy_document.elasticsearch_bucket_policy.json
}

################################################################################
# Cross-Region Replication (if enabled)
################################################################################

resource "aws_iam_role" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${var.environment}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${var.environment}-s3-replication-policy"
  role  = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          for bucket in aws_s3_bucket.buckets : bucket.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          for bucket in aws_s3_bucket.buckets : "${bucket.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          for name, config in local.buckets : "arn:aws:s3:::${config.name}-replica-${var.replication_region}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "buckets" {
  for_each = var.enable_replication ? local.buckets : {}

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    id     = "${each.key}-replication"
    status = "Enabled"

    destination {
      bucket        = "arn:aws:s3:::${each.value.name}-replica-${var.replication_region}"
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.buckets]
}