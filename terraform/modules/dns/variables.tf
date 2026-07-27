variable "domain_name" {
  description = "Domain the certificate is issued for, e.g. \"example.com\". A PUBLIC Route53 hosted zone with exactly this name must already exist — this module looks it up, it does not create it."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
