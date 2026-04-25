# S3 Bucket
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "secure_share_bucket" {
  bucket        = "${var.project_name}-files-${var.environment}-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-files"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "secure_share_bucket_pab" {
  bucket                  = aws_s3_bucket.secure_share_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "secure_share_bucket_cors" {
  bucket = aws_s3_bucket.secure_share_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure_share_bucket_sse" {
  bucket = aws_s3_bucket.secure_share_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "secure_share_metadata" {
  name         = "${var.project_name}-metadata-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "file_id"

  attribute {
    name = "file_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# Outputs
output "s3_bucket_name" {
  value       = aws_s3_bucket.secure_share_bucket.id
  description = "S3 bucket name"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.secure_share_metadata.name
  description = "DynamoDB table name"
}
