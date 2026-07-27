# In-cluster foundations that DON'T conflict with ArgoCD-managed GitOps:
# the ALB controller, the default StorageClass, External Secrets, and the
# one-off DB migration Job. ArgoCD itself and everything it deploys (app
# chart, kube-prometheus-stack) stay OUT of Terraform on purpose — two
# owners fighting over the same resources is worse than one manual
# `helm install argocd` at bootstrap time.

# --- AWS Load Balancer Controller -------------------------------------------
# Watches Ingress resources with ingressClassName: alb and provisions real
# ALBs. Without this, an Ingress on EKS does nothing at all.

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.network.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    # Must be exactly this — modules/irsa's trust policy is scoped to
    # kube-system:aws-load-balancer-controller.
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.alb_controller_role_arn
  }

  # The controller registers webhooks — make sure nodes exist to schedule
  # onto before Helm waits on the rollout.
  depends_on = [module.eks, aws_eks_addon.ebs_csi]
}

# --- Default StorageClass ---------------------------------------------------
# EKS ships NO default StorageClass. The ebs-csi addon (live/main.tf) is the
# provisioner, but until a StorageClass points at it, every PVC — Prometheus,
# Alertmanager — sits Pending forever with no error beyond "no storage class".

resource "kubernetes_storage_class_v1" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  # WaitForFirstConsumer: volume is created in the AZ of the pod that claims
  # it — Immediate binding can put the volume in a different AZ than the
  # pod and deadlock scheduling on this 2-AZ cluster.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "gp3"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

# --- External Secrets Operator ----------------------------------------------
# Materializes SSM Parameter Store values as native Kubernetes Secrets.
# The app chart's ExternalSecret (kind/project/charts/backend) references
# the ClusterSecretStore below.

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
  set {
    # Must be exactly "external-secrets" — modules/irsa's trust policy is
    # scoped to external-secrets:external-secrets.
    name  = "serviceAccount.name"
    value = "external-secrets"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.external_secrets_role_arn
  }

  # Serialized behind the ALB controller, not for a real dependency but
  # because the controller registers a MutatingWebhook on all Services the
  # moment its chart installs — any Service created in the window before
  # its pods are Ready fails with "no endpoints available". Installing in
  # parallel hit exactly that race.
  depends_on = [helm_release.alb_controller]
}

# The store every ExternalSecret in the cluster reads through. ParameterStore
# service, NOT SecretsManager — that's where Terraform writes the secrets,
# and the only service the IRSA policy grants.
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: aws-parameter-store
    spec:
      provider:
        aws:
          service: ParameterStore
          region: ${var.region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [helm_release.external_secrets]
}

# --- App namespace ----------------------------------------------------------
# Created here (not left to ArgoCD's CreateNamespace=true) because the
# migration Job below needs it before ArgoCD exists.

resource "kubernetes_namespace_v1" "landing_builder" {
  metadata {
    name = "landing-builder"
  }
}

# --- Database migrations ----------------------------------------------------
# RDS is in private subnets, unreachable from a laptop — migrations must run
# in-cluster. Runs `prisma migrate deploy` from the backend image (which
# carries schema.prisma + migrations/ since the Dockerfile fix).
#
# Gated on var.migration_image_tag being set: the currently-pushed image
# (c96914d) predates that Dockerfile fix and contains no migrations dir.
# Rebuild + push with a new tag, set the variable, re-apply.
#
# Jobs are immutable — the tag is part of the name, so a new tag creates a
# NEW Job (old completed one is replaced) rather than failing the update.

resource "kubernetes_job_v1" "db_migrate" {
  count = var.migration_image_tag != "" ? 1 : 0

  metadata {
    name      = "db-migrate-${var.migration_image_tag}"
    namespace = kubernetes_namespace_v1.landing_builder.metadata[0].name
  }

  spec {
    backoff_limit = 2

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "db-migrate"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name        = "migrate"
          image       = "${module.ecr.repository_urls["backend"]}:${var.migration_image_tag}"
          working_dir = "/app"
          command     = ["./node_modules/.bin/prisma", "migrate", "deploy", "--schema", "schema.prisma"]

          env {
            name  = "DATABASE_URL"
            value = module.rds.database_url
          }
        }
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
    update = "5m"
  }

  depends_on = [module.rds]
}

# --- Grafana admin credentials -----------------------------------------
# kube-prometheus-stack's default Grafana admin/password ("prom-operator")
# is public knowledge — putting that on a real ALB would be a straight
# handout of cluster-visibility (Grafana queries Prometheus, which has full
# pod/node metrics) to anyone who finds the hostname. Generated here,
# same pattern as auth_secret, and consumed via grafana.admin.existingSecret
# in kind/monitoring/values-eks.yaml — never sits in a values file.

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name  = "/${var.project_name}/grafana-admin-password"
  type  = "SecureString"
  value = random_password.grafana_admin.result
  tags  = local.common_tags
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin-credentials"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}
