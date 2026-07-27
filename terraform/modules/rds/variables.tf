variable "name" {
  description = "Prefix for the DB instance, subnet group, and security group names."
  type        = string
}

variable "secret_name_prefix" {
  description = "Secrets Manager path prefix for the generated DATABASE_URL. MUST match modules/irsa's secret_name_prefix, or the External Secrets read policy won't cover it."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_cluster_security_group_id" {
  description = "From the eks module's output — allows pods/control plane to reach Postgres."
  type        = string
}

variable "eks_node_security_group_id" {
  type = string
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  description = "Free-tier eligible for 12 months on a new AWS account; ~$0.017/hr after (see the cost estimate)."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20 # RDS free-tier ceiling
}

variable "max_allocated_storage_gb" {
  type    = number
  default = 50
}

variable "database_name" {
  type    = string
  default = "landing_builder"
}

variable "master_username" {
  type    = string
  default = "postgres"
}

variable "backup_retention_days" {
  type    = number
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
