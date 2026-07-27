# EKS cluster: t3.medium managed node group, per claude2.md's resource
# math. Wraps the community module — it also creates the OIDC provider
# IRSA needs, which the irsa/ module then attaches roles to.
#
# cluster_addons declares vpc-cni/coredns/kube-proxy explicitly (version
# tracked, not left to whatever EKS auto-installs by default) — but NOT
# aws-ebs-csi-driver, which needs its own IRSA role. That role can only be
# created after this module's OIDC provider exists (the irsa module
# depends on it), so wiring it back into cluster_addons here would be a
# circular module dependency. It's created as a standalone aws_eks_addon
# resource in live/main.tf instead, once both this module and irsa exist.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Portfolio cluster — reachable from your own machine without a bastion.
  # Tighten cluster_endpoint_public_access_cidrs before using this for
  # anything beyond a personal demo.
  cluster_endpoint_public_access = true

  # Required for IRSA (IAM Roles for Service Accounts) — the irsa/ module
  # attaches roles to this provider's OIDC issuer.
  enable_irsa = true

  # Grants the identity running `terraform apply` cluster-admin inside
  # Kubernetes, via an EKS access entry. The module defaults this to FALSE,
  # which means without it `kubectl` returns "You must be logged in to the
  # server (Unauthorized)" after apply — even for the identity that just
  # built the cluster — and there's no way in via kubectl to fix it.
  #
  # Consequence: whatever identity applies this becomes THE cluster admin.
  # Use the same identity for `terraform apply` and `kubectl`, or add more
  # principals via `access_entries` below.
  enable_cluster_creator_admin_permissions = true

  # Control-plane logging to CloudWatch. The module DEFAULTS to
  # ["audit", "api", "authenticator"] with 90-day retention, which nobody
  # picked on purpose — and `audit` is by far the loudest, one record per
  # API call. With ArgoCD reconciling on a loop and Prometheus scraping,
  # that's the kind of thing that quietly becomes the third-largest line
  # item on a demo cluster at $0.50/GB ingested.
  #
  # `authenticator` is the one worth keeping: it's how you debug the
  # "Unauthorized" IAM-to-Kubernetes mapping failures that are otherwise
  # invisible. Everything about workloads comes from Prometheus instead.
  cluster_enabled_log_types              = var.cluster_enabled_log_types
  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days

  cluster_addons = {
    vpc-cni = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      capacity_type  = var.node_capacity_type # "ON_DEMAND" or "SPOT"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  tags = var.tags
}
