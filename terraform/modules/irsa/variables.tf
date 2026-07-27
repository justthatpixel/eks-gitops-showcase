variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "oidc_provider_arn" {
  description = "From the eks module's output — the OIDC provider these roles trust."
  type        = string
}

variable "published_pages_bucket_name" {
  description = "From the s3 module's output — scopes the backend's S3 policy to just this bucket."
  type        = string
}

variable "secret_name_prefix" {
  description = "Secrets Manager path prefix External Secrets is allowed to read, e.g. \"landing-builder\" grants /landing-builder/*."
  type        = string
  default     = "landing-builder"
}

variable "tags" {
  type    = map(string)
  default = {}
}
