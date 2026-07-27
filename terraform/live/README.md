# terraform/live

The one real environment: VPC (2 AZs), EKS (t3.medium managed node group + vpc-cni/coredns/kube-proxy/ebs-csi add-ons), RDS Postgres, S3, ECR, Route53 + ACM, and the IRSA roles pods need. Single environment — nothing to select here, just apply.

## First-time setup

1. Run `../bootstrap` once (creates the S3 state bucket) — see its README.
2. Point Terraform at that bucket without hardcoding it into a committed file:
   ```sh
   echo 'bucket = "<your state bucket name>"' > backend.hcl   # gitignored
   terraform init -backend-config=backend.hcl
   ```
3. Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored) and fill in your own values — a globally-unique `published_pages_bucket_name`, and `domain_name` set to a domain whose **public Route53 hosted zone already exists** (Terraform looks the zone up, it does not create one, and issues an ACM certificate validated through it). Verify delegation with `dig NS <domain>` before applying: if the registrar's NS records don't point at that zone, ACM never sees the validation record and the apply hangs ~45 minutes before failing. Set `enable_dns = false` to skip all of this.

## Apply

```sh
cd terraform/live
terraform init -backend-config=backend.hcl   # from step 2 above
terraform plan
terraform apply
```

Then, to actually reach the cluster:

```sh
$(terraform output -raw configure_kubectl)
```

## What this does NOT do

Provisioning the AWS resources here is only half of "up." Terraform stops at the cluster boundary — nothing inside Kubernetes is its job. After `apply` succeeds you still need to, once per fresh cluster:

1. **AWS Load Balancer Controller** into `kube-system`, with its ServiceAccount annotated from `terraform output -json irsa_role_arns | jq -r .alb_controller`. Without this, an `Ingress` provisions no ALB.
2. **A default StorageClass** (`gp3`, provisioner `ebs.csi.aws.com`). The `aws-ebs-csi-driver` addon is installed by Terraform, but a StorageClass to bind against is not — without one, any PVC (Prometheus, Alertmanager) sits `Pending` forever.
3. **ArgoCD**, then your app chart. `../../kind/argocd` is the working GitOps setup — its `Application`/`AppProject` manifests carry over to EKS with the destination namespace and values file swapped.
4. **External Secrets Operator**, if you want `DATABASE_URL`/`AUTH_SECRET` pulled from SSM Parameter Store rather than pasted into a values file. Terraform already wrote both parameters and the IRSA role (`terraform output parameter_store_paths`, `irsa_role_arns.external_secrets`); the cluster-side `ClusterSecretStore` + `ExternalSecret` don't exist yet. The store must use `provider.aws.service: ParameterStore` — the `SecretsManager` service won't find these, and the IRSA policy doesn't grant it.

Fill in `kind/project/values-eks.yaml`'s and `kind/monitoring/values-eks.yaml`'s `<PLACEHOLDER>` values from this stack's `terraform output` before syncing — ArgoCD reads those files directly from git, so they can't be gitignored the way `terraform.tfvars` is; see the comment at the top of each file for exactly which outputs map to which field.

## Teardown

```sh
terraform destroy
```

RDS has `skip_final_snapshot = true` for this demo setup — if you want the database to survive a teardown, either flip that in `../modules/rds/main.tf` before destroying, or manually snapshot first:

```sh
aws rds create-db-snapshot --db-instance-identifier <name>-postgres --db-snapshot-identifier <name>-pre-teardown
```

`../bootstrap`'s state bucket is a separate Terraform state (see `../bootstrap/README.md`), so this `destroy` leaves it alone — run `terraform destroy` there too, and only after this one, since it holds the state describing everything above.

The Route53 hosted zone is **not** destroyed: the dns module reads it via a data source rather than owning it, so only the ACM certificate goes away. Your NS delegation survives a teardown, and the zone keeps costing $0.50/month until you delete it by hand in the console.
