variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state. S3 bucket names are global across all AWS accounts — no default provided on purpose, pick your own and pass it via -var or a gitignored terraform.tfvars."
  type        = string
}
