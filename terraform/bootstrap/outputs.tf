output "state_bucket_name" {
  description = "Copy this into ../live/backend.tf's `bucket` field."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.terraform_state.arn
}
