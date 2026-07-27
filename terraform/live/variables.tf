variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names and tags."
  type        = string
  default     = "landing-builder"
}

variable "environment" {
  description = "Free-text label for tagging only. Single environment — no dev/uat/prod split."
  type        = string
  default     = "demo"
}

# --- Compute ---------------------------------------------------------------

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_capacity_type" {
  description = "\"ON_DEMAND\" or \"SPOT\"."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# --- Database ---------------------------------------------------------------

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

# --- DNS ---------------------------------------------------------------------

variable "enable_dns" {
  description = "Issue an ACM certificate validated through the EXISTING public Route53 hosted zone for `domain_name` (the zone must already exist and be delegated — the module looks it up, it does not create one). The certificate validation step blocks until ACM resolves the DNS record, so enabling this without a real, delegated zone hangs the apply ~45 minutes and then fails it. Everything else in this stack works fine with this off; the app just has no HTTPS hostname."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain the ACM cert is issued for (apex + wildcard). A public Route53 hosted zone with exactly this name must already exist. Only used when enable_dns = true."
  type        = string
  default     = "example.com"
}

# --- Globally-unique names (S3 bucket names are unique across ALL of AWS,
# not just your account) -----------------------------------------------------

variable "published_pages_bucket_name" {
  description = "Must be globally unique across all AWS accounts. Override in terraform.tfvars."
  type        = string
  default     = "landing-builder-published-pages-CHANGE-ME"
}

# --- In-cluster (k8s.tf) -----------------------------------------------------

variable "migration_image_tag" {
  description = "Backend image tag to run `prisma migrate deploy` from, e.g. a git SHA. Empty string skips the migration Job entirely — required because the image must contain schema.prisma + migrations/ (images built before the Dockerfile fix that added them can't run migrations)."
  type        = string
  default     = ""
}
