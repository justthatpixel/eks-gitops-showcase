# Published-pages bucket — where the backend uploads server-rendered HTML
# on publish (see application/apps/backend/src/storage/storage.service.ts). This is the
# S3 the app already knows how to talk to via the AWS SDK; in prod it swaps
# in for the local MinIO bucket with no code changes (same S3 API).

resource "aws_s3_bucket" "published_pages" {
  bucket = var.published_pages_bucket_name
  tags   = var.tags

  # Demo stack: `terraform destroy` should succeed even after the app has
  # published pages into this bucket. S3 refuses to delete non-empty
  # buckets; this empties it first — published pages are gone with it.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "published_pages" {
  bucket = aws_s3_bucket.published_pages.id

  # Published HTML is served through the backend's /p/:slug route, not
  # directly from S3 — so the bucket itself stays private.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "published_pages" {
  bucket = aws_s3_bucket.published_pages.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Optional second bucket for Loki (logs) / Tempo (traces) backends, per
# claude2.md #2's "Object storage" row. Only created if observability
# is deployed with S3-backed storage instead of in-cluster PVCs.
resource "aws_s3_bucket" "observability" {
  count         = var.create_observability_bucket ? 1 : 0
  bucket        = var.observability_bucket_name
  tags          = var.tags
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "observability" {
  count  = var.create_observability_bucket ? 1 : 0
  bucket = aws_s3_bucket.observability[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
