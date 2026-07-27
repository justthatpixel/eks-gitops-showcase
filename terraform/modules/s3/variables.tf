variable "published_pages_bucket_name" {
  description = "Globally-unique S3 bucket name for published static pages."
  type        = string
}

variable "create_observability_bucket" {
  description = "Whether to create a second bucket for Loki/Tempo backends. Leave false until you actually deploy S3-backed observability."
  type        = bool
  default     = false
}

variable "observability_bucket_name" {
  description = "Globally-unique S3 bucket name for Loki/Tempo, if create_observability_bucket is true."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
