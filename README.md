


# 3-Tier AWS EKS GitOps Project
<img width="2218" height="1858" alt="image" src="https://github.com/user-attachments/assets/3e0bdbe4-2ca1-4bd8-b716-0aab0d48d771" />



---
## Interview FAQs

### 1. What are we deploying?

<img width="1044" height="548" alt="Screenshot 2026-11-22 at 17 53 06" src="https://github.com/user-attachments/assets/464de054-9ea7-4c37-ac41-6c71f8811e5b" />


- A landing page builder for marketing funnels, similar to WordPress, Squarespace or ClickFunnels.
- Users drag and drop components to build their pages.
- Each user has a dashboard and can publish their site to a custom domain, hosted on S3 static website hosting.

### 2. CI/CD Pipeline

1. Every push to the app repo triggers the GitHub Actions workflow.
2. The Github Actions runner pulls the latest app code.
3. SonarQube runs static code analysis, checking for bugs and security issues.
4. Builds the Docker image, tagged with the Git commit SHA.
5. Trivy scans the image for CVEs and fails the pipeline on any high or critical findings.
6. Pushes the image to our private ECR repo, using OIDC instead of long-lived AWS keys.
7. Updates the image tag in the Helm values.yaml in our infra repo.
8. Argo CD detects the change in the infra repo and syncs it to the cluster.

### 3. How is the application built?
- A 3-tier architecture: frontend, backend and database.
- Tech stack: Next.js, NestJS and PostgreSQL, built with Claude Code as an AI coding harness.

### 4. How did we build this pipeline?
<img width="922" height="512" alt="Screenshot 2026-11-22 at 17 54 29" src="https://github.com/user-attachments/assets/0a2acb53-0aa1-435d-858c-20e4ad57bdfb" />

- We keep two repos: one for the application and one for the infrastructure.
- 1: Built the app and verified it worked locally.
- 2: Containerised it with Docker and ran it on Kind, which gave us a multi-node Kubernetes cluster on one machine.
- 3: Provisioned the AWS infrastructure with Terraform, so the whole environment can be rebuilt from code.
- 4: Hardened security and added observability.

### 5. Observability
- Logs: container logs shipped to CloudWatch Logs.
- Metrics: Prometheus and Grafana, installed with Helm.
- In production we'd add OpenTelemetry, so the app code emits its own metrics, logs and traces.
- We'd define SLIs and SLOs around our key user journeys (e.g. login, publishing a page).
- We'd build a central dashboard for system health, with CloudWatch alerts to Slack on symptoms users feel (e.g. pages taking more than 2s to load).
- Each alert links to a runbook (a step-by-step guide on how to fix the problem).

### 6. Security
- Shift-left approach, AKA find the bug as early as possible.
- Multi-stage Docker build shrank the image from 2GB to ~200MB, reducing the attack surface.
- Containers run as a non-root user.
- TruffleHog pre-commit hook catches hardcoded secrets before they touch the remote repo.
- SonarQube = static code analysis for bugs and security issues.
- Trivy = scans the image for CVEs (known vulnerabilities).
- OIDC gives GitHub Actions short-lived AWS credentials, so no long-lived keys are stored.
- Argo CD pulls changes from Git, so CI never needs access to the cluster.

### 7. Kubernetes deep dive
- Load balancer: provisioned on AWS by the AWS Load Balancer Controller.
- Ingress: 1x Ingress (Gateway API is the recommended successor).
- Frontend: 1x Deployment and 1x ClusterIP Service.
- Backend: 1x Deployment and 1x ClusterIP Service.
- Database: Amazon RDS (Postgres), running outside the cluster.
- IRSA maps Kubernetes service accounts to IAM roles, so each pod only gets the AWS access it needs.
- Helm makes it simple to install tools like Argo CD, Prometheus and Grafana, though templated manifests are harder to read.
- cert-manager renews TLS certificates automatically, keeping traffic encrypted in transit.
- Secrets live in AWS Secrets Manager, outside the cluster.

### 8. Architectural decisions
- ECS could easily support 1K–10M+ users, so scale wasn't the reason for Kubernetes.
- We chose Kubernetes because we want access to the GitOps ecosystem (Argo CD, Helm, Prometheus, Grafana).
- Terraform and Kubernetes give us the option to stand the platform up on another cloud, e.g. during a major cloud outage, as our app layer is portable and all infrastructure is defined as code.
- We chose EKS on Fargate: EKS manages the control plane, and Fargate handles the compute for us.
- Fargate bills on the CPU and memory each pod requests, so we still have to define appropriate requests.
- The Horizontal Pod Autoscaler still scales pods when traffic spikes, and Fargate provides the compute.
- For GDPR and SOC 2, data is encrypted in transit with TLS and at rest with AWS KMS.

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
