variable "name_prefix" {
  description = "Prefix for repo names, e.g. \"landing-builder\" -> \"landing-builder/frontend\"."
  type        = string
  default     = "landing-builder"
}

variable "repository_names" {
  description = "Short names of the repos to create, one per deployable service."
  type        = list(string)
  default     = ["frontend", "backend"]
}

variable "keep_last_n_images" {
  description = "How many images to retain per repo before lifecycle policy expires the rest."
  type        = number
  default     = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
