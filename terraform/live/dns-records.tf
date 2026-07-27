# Points your domain (+ grafana./argocd. subdomains) at the shared
# ALB the AWS Load Balancer Controller provisions from the app/monitoring/
# argocd Ingresses (kind/project, kind/monitoring, kind/argocd — all three
# use the same alb.ingress.kubernetes.io/group.name: landing-builder-shared,
# so there's exactly one ALB to find).
#
# Looked up by tag, not hardcoded DNS name: the ALB's name/hash is
# regenerated if it's ever recreated (annotation changes, cluster rebuild),
# but the controller re-applies this tag automatically every time, so this
# stays correct without manual updates.
#
# Resolves to an empty list (not an error) before the ALB exists — safe to
# apply before ArgoCD has synced anything. Records are simply skipped until
# it does; re-apply once the app is deployed.

data "aws_resourcegroupstaggingapi_resources" "app_alb" {
  tag_filter {
    key    = "ingress.k8s.aws/stack"
    values = ["landing-builder-shared"]
  }
  resource_type_filters = ["elasticloadbalancing:loadbalancer"]
}

locals {
  app_alb_arn = try(data.aws_resourcegroupstaggingapi_resources.app_alb.resource_tag_mapping_list[0].resource_arn, null)

  app_hostnames = {
    apex    = var.domain_name
    grafana = "grafana.${var.domain_name}"
    argocd  = "argocd.${var.domain_name}"
  }
}

data "aws_lb" "app" {
  count = local.app_alb_arn != null ? 1 : 0
  arn   = local.app_alb_arn
}

# ALIAS, not CNAME — CNAMEs aren't valid at a zone apex (var.domain_name
# itself, no subdomain), and ALIAS is free (no extra Route53 query charge)
# where a real CNAME-to-ALB setup would incur one.
resource "aws_route53_record" "app_hosts" {
  for_each = var.enable_dns && local.app_alb_arn != null ? local.app_hostnames : {}

  zone_id = module.dns[0].zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = data.aws_lb.app[0].dns_name
    zone_id                = data.aws_lb.app[0].zone_id
    evaluate_target_health = true
  }
}
