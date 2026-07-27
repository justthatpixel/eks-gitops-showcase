# One-time bootstrap: creates the S3 bucket that ../live
# uses as its remote state backend.
#
# This config's OWN state stays local (terraform.tfstate next to this file,
# gitignored). That's deliberate — the bucket that holds remote state can't
# also hold the state that describes itself (chicken-and-egg). Run this once,
# commit nothing but this code, and keep the local .tfstate file somewhere
# safe (or just recreate it with `terraform import` if it's ever lost — the
# bucket itself is the source of truth, not this state file).

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  # Deliberate choice for a demo stack: `terraform destroy` here should take
  # the bucket with it. It's versioned and will hold live/'s state file, and
  # S3 refuses to delete non-empty buckets — force_destroy empties it
  # (all versions included) first. ONLY destroy this AFTER destroying live/,
  # or live/'s record of what exists in AWS is gone with the bucket.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# No DynamoDB lock table — Terraform 1.11+'s native S3 locking
# (use_lockfile = true, configured in live/backend.tf) replaces it.
