output "alb_controller_role_arn" {
  description = "Annotate onto the aws-load-balancer-controller ServiceAccount (kube-system) when installing that Helm chart at cluster-bootstrap time."
  value       = module.alb_controller_irsa.iam_role_arn
}

output "ebs_csi_role_arn" {
  description = "Passed to the standalone aws_eks_addon.ebs_csi resource in live/main.tf — can't be wired inside the eks module itself without a circular module dependency (this role needs the eks module's OIDC output first)."
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "external_secrets_role_arn" {
  description = "Annotate onto the external-secrets ServiceAccount when installing the External Secrets Operator."
  value       = module.external_secrets_irsa.iam_role_arn
}

output "backend_role_arn" {
  description = "Annotate onto the backend ServiceAccount. Trust policy is scoped to landing-builder:backend — see modules/irsa/main.tf if you deploy into a different namespace."
  value       = module.backend_irsa.iam_role_arn
}
