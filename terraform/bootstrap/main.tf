# Bootstrap — provisions the S3 bucket and DynamoDB table that
# terraform/main.tf uses as its remote backend.
#
# Run this ONCE before the main configuration:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#
# State for this bootstrap module stays LOCAL (terraform.tfstate in this
# directory). Keep that file safe — losing it means manually importing
# the two AWS resources if you ever need to manage them with Terraform again.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ── S3 bucket ─────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket = "shopnow-tfstate"

  # Prevent accidental deletion of the bucket that holds live state.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "shopnow-tfstate"
    ManagedBy = "Terraform Bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB lock table ───────────────────────────────────────────────────────
resource "aws_dynamodb_table" "tf_lock" {
  name         = "shopnow-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "shopnow-tf-lock"
    ManagedBy = "Terraform Bootstrap"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "tfstate_bucket" {
  value       = aws_s3_bucket.tfstate.id
  description = "S3 bucket name — used in the backend block of terraform/main.tf"
}

output "lock_table" {
  value       = aws_dynamodb_table.tf_lock.name
  description = "DynamoDB table name — used in the backend block of terraform/main.tf"
}
