output "published_pages_bucket_name" {
  value = aws_s3_bucket.published_pages.id
}

output "published_pages_bucket_arn" {
  value = aws_s3_bucket.published_pages.arn
}

output "observability_bucket_name" {
  value = var.create_observability_bucket ? aws_s3_bucket.observability[0].id : null
}
