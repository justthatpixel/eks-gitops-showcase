output "endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "address" {
  value = aws_db_instance.postgres.address
}

output "port" {
  value = aws_db_instance.postgres.port
}

output "database_name" {
  value = aws_db_instance.postgres.db_name
}

output "database_url_secret_arn" {
  description = "Target for an External Secrets Operator ClusterSecretStore using the AWS ParameterStore provider."
  value       = aws_ssm_parameter.database_url.arn
}

output "database_url_secret_name" {
  value = aws_ssm_parameter.database_url.name
}

output "database_url" {
  description = "Plaintext connection string, for Terraform-managed in-cluster resources (the migration Job) that need it before External Secrets is wired up. Everything else should read it from Parameter Store instead."
  value       = aws_ssm_parameter.database_url.value
  sensitive   = true
}
