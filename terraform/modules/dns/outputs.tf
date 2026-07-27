output "zone_id" {
  value = data.aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "The existing zone's name servers — the registrar's NS records should already point here (verify with `dig NS <domain>`)."
  value       = data.aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "Validated (issued) certificate ARN — set as frontend.ingress.certificateArn in the Helm values."
  value       = aws_acm_certificate_validation.this.certificate_arn
}
