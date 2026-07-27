# Root module — wires every child module into the one demo stack. Read
# this file top to bottom to understand the whole AWS footprint; each
# module hides its own resource-level detail.
#
# Single environment — one VPC, one EKS cluster, one RDS instance, one
# set of buckets, one `landing-builder` namespace. No dev/uat/prod split.

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  cluster_name = "${var.project_name}-${var.environment}"
}

module "network" {
  source = "../modules/network"

  name         = var.project_name
  cluster_name = local.cluster_name
  tags         = local.common_tags
}

module "eks" {
  source = "../modules/eks"

  cluster_name       = local.cluster_name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_capacity_type = var.node_capacity_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
  tags               = local.common_tags
}

module "ecr" {
  source = "../modules/ecr"

  name_prefix = var.project_name
  tags        = local.common_tags
}

module "s3" {
  source = "../modules/s3"

  published_pages_bucket_name = var.published_pages_bucket_name
  tags                        = local.common_tags
}

# Looks up the EXISTING public hosted zone for domain_name (it does not
# create one) and issues an ACM certificate validated through it.
# `aws_acm_certificate_validation` BLOCKS until ACM can resolve the DNS
# validation record — safe here only because the zone is real and the
# registrar's NS records already point at it. If either stops being true,
# set enable_dns = false or the apply hangs ~45 min and fails.
module "dns" {
  source = "../modules/dns"
  count  = var.enable_dns ? 1 : 0

  domain_name = var.domain_name
  tags        = local.common_tags
}

module "rds" {
  source = "../modules/rds"

  name                          = local.cluster_name
  vpc_id                        = module.network.vpc_id
  private_subnet_ids            = module.network.private_subnet_ids
  eks_cluster_security_group_id = module.eks.cluster_security_group_id
  eks_node_security_group_id    = module.eks.node_security_group_id
  instance_class                = var.db_instance_class
  # Same value passed to module.irsa's secret_name_prefix — these must agree.
  secret_name_prefix = var.project_name
  tags               = local.common_tags
}

module "irsa" {
  source = "../modules/irsa"

  cluster_name                = local.cluster_name
  region                      = var.region
  oidc_provider_arn           = module.eks.oidc_provider_arn
  published_pages_bucket_name = module.s3.published_pages_bucket_name
  secret_name_prefix          = var.project_name
  tags                        = local.common_tags
}

# --- EBS CSI addon ----------------------------------------------------------
# Standalone resource, not inside the eks module — this needs irsa's
# ebs_csi_role_arn, which itself needs eks's OIDC output first. Putting it
# inside either module would create a circular module dependency; wiring
# it here (after both exist) breaks that cleanly.
#
# Required for kube-prometheus-stack: there's no default StorageClass on
# EKS without this, so Prometheus/Alertmanager's PVCs would sit Pending
# forever otherwise.

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.irsa.ebs_csi_role_arn

  tags = local.common_tags
}

# --- App secrets, handed off to Kubernetes via External Secrets Operator ---
# ESO (installed in-cluster after apply — see README.md's "What this does
# NOT do") reads these paths through the IRSA role from module.irsa and
# materializes them as native Secrets the backend Deployment mounts.
#
# SSM Parameter Store, not Secrets Manager: standard-tier parameters and the
# AWS-managed alias/aws/ssm encryption key are both free.
#
# DATABASE_URL already went to Parameter Store inside the rds module
# (co-located with the DB it describes). AUTH_SECRET has no natural home
# in another module, so it's created here — same /${var.project_name}/
# prefix, which is what module.irsa's read policy is scoped to.

resource "random_password" "auth_secret" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "auth_secret" {
  name  = "/${var.project_name}/auth-secret"
  type  = "SecureString"
  value = random_password.auth_secret.result
  tags  = local.common_tags
}
