

# 3-Tier AWS EKS GitOps Project
<img width="1067" height="979" alt="Screenshot 2026-07-27 at 20 55 05" src="https://github.com/user-attachments/assets/cecd023d-8663-444e-890e-13ee46fcacc7" />

## Overview

This project focuses on deploying an EKS (Elastic Kubernetes Service) cluster on AWS, integrating key Kubernetes tools such as ArgoCD, Helm Charts, Cert-Manager, and ExternalDNS. The goal is to achieve a robust, automated, and scalable infrastructure setup with streamlined GitOps workflows, secure certificate management, and automated DNS updates.

## Architecture

Everything downstream of ECR — the app, monitoring stack, and ArgoCD's own upgrades — is GitOps-managed: nothing gets `kubectl apply`'d by hand except the one-time bootstrap.

# Key Features
- **Amazon EKS**: Managed Kubernetes for running containerized apps at scale with built-in HA and AWS integration.
- **ArgoCD**: Declarative GitOps delivery that auto-deploys applications straight from Git.
- **Helm Charts**: Reusable, version-controlled templates for deploying complex Kubernetes apps.
- **Cert-Manager**: Automates TLS/SSL issuance and renewal via ACME.
- **ExternalDNS**: Syncs Route 53 DNS records automatically from Kubernetes resources.

## Why This Setup Matters
- **GitOps with ArgoCD**: Ensures consistent, version-controlled deployments through automated Git sync.
- **Scalable Infrastructure**: EKS handles auto-scaling and high availability out of the box.
- **Secure Communication**: Cert-Manager enforces encrypted traffic via TLS/SSL.
- **Automated DNS Management**: ExternalDNS eliminates manual DNS record upkeep.

## Infrastructure Components
- **VPC (2 AZs)**: Public/private subnet split with a NAT gateway for an isolated cluster network.
- **EKS**: Managed control plane and node group with `vpc-cni`, `coredns`, `kube-proxy`, and `aws-ebs-csi-driver` add-ons.
- **RDS (Postgres)**: Private-subnet-only and encrypted at rest, reachable only from EKS security groups.
- **S3**: Hosts published static pages, app-writable via IRSA.
- **ECR**: Immutable-tagged image repositories with scan-on-push enabled.
- **Route53 + ACM**: Uses an existing hosted zone and issues a DNS-validated wildcard certificate.
- **IRSA Roles**: Per-workload IAM for the ALB controller, External Secrets, backend S3 access, and EBS CSI.
- **SSM Parameter Store**: Stores `DATABASE_URL`, `AUTH_SECRET`, and the Grafana admin password, read in-cluster via External Secrets Operator.
- **ArgoCD**: GitOps controller running an app-of-apps pattern with scoped `AppProject`s and automated sync.
- **kube-prometheus-stack**: Prometheus + Grafana, deployed through the same GitOps path as the app.


## Setup

### 1. Run it locally first

```sh
# See kind/README.md
```

No AWS account needed — validates the full chart and GitOps config on a local cluster before touching AWS.

### 2. Create the remote state bucket

```sh
cd terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=<your-unique-name>"
```

One-time step that creates the S3 bucket Terraform will use for remote state.

### 3. Point the live stack at that bucket

```sh
echo 'bucket = "<your state bucket name>"' > backend.hcl
terraform init -backend-config=backend.hcl
```

This file is gitignored, so the bucket name never gets committed.

### 4. Set your variables

```sh
cp terraform/live/terraform.tfvars.example terraform/live/terraform.tfvars
```

Fill in your own domain and bucket names — this file is also gitignored.

### 5. Provision the cluster

```sh
terraform plan
terraform apply
```

Terraform stops at the cluster boundary, so ArgoCD, the ALB controller, and StorageClass still need to be installed manually — see [terraform/live/README.md](terraform/live/README.md) for those steps.

> Nothing in this repo needs a real AWS account ID, domain, or ARN hardcoded anywhere — every real value lives in a gitignored file or an explicit placeholder that ArgoCD reads from git.

## Teardown

### 1. Remove ingress resources

```sh
kubectl delete ingress --all -A
```

This lets the ALB controller clean up the load balancer it created, since Terraform has no record of it.

### 2. Destroy the live stack

```sh
terraform destroy
```

Run this from `terraform/live`.

### 3. Destroy the bootstrap stack

```sh
terraform destroy
```

Run this from `terraform/bootstrap`, only after the live stack is fully gone.

> Confirm the ALB is actually gone (`aws elbv2 describe-load-balancers`) before tearing down the VPC underneath it, or it can get orphaned.

The ALB, its target groups, and its security group are created by the AWS Load Balancer Controller reacting to `Ingress` objects, not by Terraform — deleting the Ingresses *first* and confirming the ALB is actually gone (`aws elbv2 describe-load-balancers`) avoids orphaning it before tearing down the VPC underneath it.

## Status

Built, applied, and verified end-to-end on real AWS — cluster up, app live behind the ALB with a real domain and TLS cert, ArgoCD syncing, monitoring running, CI pushing through OIDC with Trivy actually blocking bad images. Infrastructure was subsequently torn down after verification to stop the AWS bill; every step above is what it takes to bring it back up from zero.

## What's Next

- **ArgoCD CLI access** — the ALB Ingress only serves the web UI today (`controller: generic`, not `aws`'s gRPC-aware mode); `argocd login` still needs a port-forward.
- **Autoscaling** — no HPA or Cluster Autoscaler/Karpenter wired up yet; node/pod counts are static.
- **Multi-environment** — every module already composes cleanly into dev/uat/prod; the single-environment scope here is a portfolio choice, not a structural limit.
