output "repository_urls" {
  description = "Map of short name (e.g. \"frontend\") -> full ECR repository URL, for CI to push to and Helm values to reference."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  value = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
