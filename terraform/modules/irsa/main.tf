# IRSA (IAM Roles for Service Accounts) — pod-level AWS permissions instead
# of node-wide roles, per claude2.md #2's IAM row: ALB controller, External
# Secrets, ECR pull, plus the backend app's own S3 access for published
# pages, plus the EBS CSI driver (needed for kube-prometheus-stack's
# Prometheus/Alertmanager PVCs — there's no default StorageClass on EKS
# without it).
#
# Each of these creates an IAM role trusting the EKS OIDC provider, scoped
# to one specific Kubernetes namespace+ServiceAccount via the trust policy
# condition — so a pod can only assume the role its own ServiceAccount is
# annotated for.

# --- AWS Load Balancer Controller ---------------------------------------
# Provisions the ALB when the Ingress in helm/landing-builder is applied.

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-alb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# --- EBS CSI driver -------------------------------------------------------
# The community submodule has a built-in policy attachment for this —
# no hand-written IAM policy document needed, unlike the custom ones below.

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# --- External Secrets Operator -------------------------------------------
# Reads app secrets (DATABASE_URL, AUTH_SECRET, ...) from SSM Parameter
# Store and materializes them as native Kubernetes Secrets in-cluster.
# The ClusterSecretStore must use the `parameterStore` provider, not
# `secretsManager` — see terraform/live/README.md.

data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:DescribeParameters",
    ]
    # SSM's ARN format joins the parameter name directly onto `parameter`,
    # so a parameter literally named "/landing-builder/database-url" has the
    # ARN ".../parameter/landing-builder/database-url" — one slash, not two.
    # Writing "parameter//${prefix}/*" here would match nothing.
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.secret_name_prefix}/*",
    ]
  }

  # SecureString parameters are encrypted with the AWS-managed alias/aws/ssm
  # key, so reading one with WithDecryption=true needs kms:Decrypt as well.
  # Scoped by ViaService rather than key ARN because the managed key's id
  # isn't known until the account's first SecureString is created.
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  name   = "${var.cluster_name}-external-secrets"
  policy = data.aws_iam_policy_document.external_secrets.json
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-secrets"

  role_policy_arns = {
    parameter_store_read = aws_iam_policy.external_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = var.tags
}

# --- Backend app: S3 access for published pages ---------------------------
# Lets the backend's StorageService (application/apps/backend/src/storage) talk to S3
# with zero static credentials — replaces STORAGE_ACCESS_KEY/SECRET_KEY.

data "aws_iam_policy_document" "backend_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.published_pages_bucket_name}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.published_pages_bucket_name}"]
  }
}

resource "aws_iam_policy" "backend_s3" {
  name   = "${var.cluster_name}-backend-s3"
  policy = data.aws_iam_policy_document.backend_s3.json
}

module "backend_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-backend"

  role_policy_arns = {
    s3_published_pages = aws_iam_policy.backend_s3.arn
  }

  oidc_providers = {
    main = {
      provider_arn = var.oidc_provider_arn
      # Single environment — one namespace, one trust entry.
      namespace_service_accounts = [
        "landing-builder:backend",
      ]
    }
  }

  tags = var.tags
}

data "aws_caller_identity" "current" {}
