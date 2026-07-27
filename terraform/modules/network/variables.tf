variable "name" {
  description = "Base name used to prefix the VPC and its resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name that will live in this VPC — used for subnet auto-discovery tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Split into 2 public + 2 private /20 subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Common tags applied to all network resources."
  type        = map(string)
  default     = {}
}
