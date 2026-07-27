output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "Consumed by the irsa/ module to attach IAM roles to Kubernetes service accounts."
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}
