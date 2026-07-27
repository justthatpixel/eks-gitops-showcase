output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this after apply to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "published_pages_bucket_name" {
  value = module.s3.published_pages_bucket_name
}

output "route53_name_servers" {
  description = "Delegate your domain's NS records to these, if it's registered elsewhere. Null when enable_dns = false."
  value       = var.enable_dns ? module.dns[0].name_servers : null
}

output "acm_certificate_arn" {
  description = "Set as the Ingress's ACM certificate annotation in the Helm values. Null when enable_dns = false."
  value       = var.enable_dns ? module.dns[0].certificate_arn : null
}

output "irsa_role_arns" {
  description = "Copy these into the ALB controller's Helm values, the external-secrets ServiceAccount annotation, and the app chart's backend ServiceAccount annotation (see ../../kind/project — that chart needs an IRSA-annotated ServiceAccount added before it can use this on EKS)."
  value = {
    alb_controller   = module.irsa.alb_controller_role_arn
    external_secrets = module.irsa.external_secrets_role_arn
    backend          = module.irsa.backend_role_arn
    ebs_csi          = module.irsa.ebs_csi_role_arn
  }
}

output "parameter_store_paths" {
  description = "Read these via an External Secrets Operator ClusterSecretStore (AWS provider, service: ParameterStore) + ExternalSecret in the app chart, so DATABASE_URL/AUTH_SECRET never land in a values file."
  value = {
    database_url = module.rds.database_url_secret_name
    auth_secret  = aws_ssm_parameter.auth_secret.name
  }
}
