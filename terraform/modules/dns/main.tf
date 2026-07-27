# ACM certificate + automated DNS validation, against an EXISTING Route53
# hosted zone. The zone itself is looked up, not created — the zone was
# made by hand in the console (and if the domain was registered through
# Route53, the registrar's NS records already point at it). Creating a
# second zone here would be a real bug: Route53 happily allows duplicate
# zones for the same name, the validation records would land in the
# duplicate, the registrar would still point at the original, and ACM
# would never see them — the apply would hang ~45 min and fail.

data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  domain_name = var.domain_name
  # Wildcard SAN so app.<domain>, grafana.<domain>, argocd.<domain> etc. are
  # covered by this one cert — certs can't be modified in place, so leaving
  # this off would mean issuing a whole new cert the first time a subdomain
  # is needed.
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# One CNAME record per domain_validation_options entry — ACM tells you
# exactly what record to create; this creates it automatically instead of
# you copy-pasting it from the console.
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # The apex and wildcard SANs share one validation record; without this,
  # the duplicate for_each entries would collide on create.
  allow_overwrite = true
}

# Waits for ACM to actually see the validation records resolve — the
# certificate isn't ISSUED (usable) until this completes, which can take
# a few minutes after the records above are created.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
