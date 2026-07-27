# kind — local kind testing

A hand-built Helm chart (`project/`, an umbrella chart with `backend`/`frontend` as subcharts) plus everything needed to run it locally against [kind](https://kind.sigs.k8s.io/) before ever touching AWS. `../terraform` provisions the real AWS side; this chart is what gets deployed onto it (see "Taking this to EKS" below).

```
kind/
  kind-cluster.yaml       kind config: control-plane node, ingress-nginx port mappings
  project/
    Chart.yaml              parent chart — declares backend/frontend as dependencies
    values.yaml              shared defaults (ALB by default — see below)
    values-kind.yaml          local overrides: nginx ingress, image tag "local", host.docker.internal DB/storage
    templates/
      _helpers.tpl             project.name / project.fullname — shared across parent + both subcharts
      ingress.yaml              single rule, / -> frontend only (see note below)
    charts/
      backend/                 Deployment, Service, ConfigMap, Secret — port 4000
      frontend/                Deployment, Service — port 3000
  argocd/                   GitOps config for this chart — see argocd/README.md
```

## This repo deploys a separate app repo

The app itself — `apps/frontend`, `apps/backend`, `packages/`, `database/` — lives in its own repo: [Three-Tier-Kubernetes-DevSecOps-Project](https://github.com/justthatpixel/Three-Tier-Kubernetes-DevSecOps-Project), a self-contained pnpm workspace under `application/`. This repo (`eks-configuration`) only ever references it by image tag (once built) or by path when both are checked out locally for a build. The commands below assume both repos are cloned as **sibling directories**:

```
~/dev/Three-Tier-Kubernetes-DevSecOps-Project/    <- the app repo, application/ is its pnpm workspace root
~/dev/eks-configuration/                          <- this repo
```

## Why only the frontend has an Ingress rule

The app repo's `application/apps/frontend/next.config.ts` sets `output: "standalone"`; the actual `/api/*` and `/p/:slug` proxying to the backend lives in `application/apps/frontend/middleware.ts`, evaluated per-request against the live `API_URL` env var. That middleware runs inside the frontend container itself, so the public Ingress only ever needs to reach the frontend Service — the backend stays ClusterIP-only.

(This mattered for a real bug: `next.config.ts`'s old `rewrites()` config is resolved once at **build time** — an `API_URL` set later via `docker run -e` or a Kubernetes env var had no effect. Moving the proxy into middleware, which runs per-request, fixed it. Caught by actually running the built image, not by `helm lint`/`helm template`.)

## Bring-up (verified working end to end)

Run from wherever you keep the app repo checked out — adjust the relative path if it's not a sibling of this repo:

```sh
brew install kind                      # one-time
APP_REPO=../Three-Tier-Kubernetes-DevSecOps-Project

docker compose -f $APP_REPO/application/docker-compose.yml up -d   # Postgres + MinIO

# Build both images — context is application/ (the pnpm workspace root) inside the app repo
docker build -f $APP_REPO/application/apps/backend/Dockerfile  -t landing-builder/backend:local  $APP_REPO/application
docker build -f $APP_REPO/application/apps/frontend/Dockerfile -t landing-builder/frontend:local $APP_REPO/application

kind create cluster --config kind-cluster.yaml --name landing-builder
kind load docker-image landing-builder/frontend:local landing-builder/backend:local --name landing-builder

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s

helm dependency update project
helm install project project -f project/values.yaml -f project/values-kind.yaml

curl http://localhost/login          # through ingress-nginx -> frontend
```

Full flow, same as a real user:

```sh
curl -c /tmp/cookies.txt -X POST http://localhost/api/auth/signup \
  -H "Content-Type: application/json" -d '{"email":"you@example.com","password":"testpass123"}'
curl -b /tmp/cookies.txt http://localhost/api/templates
# create a page, publish it, then:
curl http://localhost/p/<slug>       # served straight from the docker-compose MinIO
```

## Teardown

```sh
helm uninstall project
kind delete cluster --name landing-builder
```

`docker compose -f $APP_REPO/application/docker-compose.yml down` separately if you're done with Postgres/MinIO too — kind never touched them; that's the point (mirrors RDS/S3 being external to the real cluster — see `../terraform/modules/rds` and `../terraform/modules/s3`).

## Taking this to EKS

`../terraform` provisions the AWS side; this chart is what gets deployed onto it. Four things this chart needs before it works against real EKS rather than kind:

1. **Ingress class `alb`, not `nginx`** — `project/templates/ingress.yaml` already switches its ALB annotations on `ingress.className == "alb"`, so this is a values change plus the ACM cert ARN from `terraform output acm_certificate_arn`. There's no `values-eks.yaml` yet; `values-kind.yaml` is the only overlay.
2. **Real image registry** — `image.registry` set to the ECR host from `terraform output ecr_repository_urls`, and images pushed there instead of `kind load docker-image`.
3. **RDS and S3 instead of `host.docker.internal`** — `values-kind.yaml` points the backend at the docker-compose containers. On EKS that becomes the RDS endpoint and the real bucket (`terraform output rds_endpoint`, `published_pages_bucket_name`).
4. **IRSA + ExternalSecret** — the backend has no ServiceAccount annotation, and secrets come from a plain `Secret` populated by values. Terraform already created the IRSA role and wrote both secrets to SSM Parameter Store (`terraform output irsa_role_arns`, `parameter_store_paths`) — the chart side (annotated ServiceAccount, `ExternalSecret`, External Secrets Operator installed in-cluster) is the missing piece.

`../terraform/live/README.md` covers the cluster-side bootstrap Terraform doesn't do (ALB controller, default StorageClass, ArgoCD, ESO).

## Bugs this local pass caught (things `helm lint`/`helm template` alone couldn't)

- Missing `_helpers.tpl`, malformed `backend-deployment.yaml`, empty `frontend-deployment.yaml`/`frontend-service.yaml`, `Ingress` → Service name mismatch (`flowops-*` vs the chart's real generated names) — all from the review before this pass; fixed here.
- The app repo's `database/` wasn't a real pnpm workspace member, so a fresh `pnpm install` (as Docker does) never installed its `prisma`/`@prisma/client` deps — triggering Prisma's internal self-heal `pnpm add`, which fails silently in sandboxed/CI-like environments. Fixed by adding `database` to the app repo's `application/pnpm-workspace.yaml`.
- `pnpm deploy` (used in the app repo's `apps/backend/Dockerfile` to flatten workspace deps for the runtime image) resolves `node_modules` fresh from the lockfile/store — it does **not** preserve `node_modules/.prisma/client`, since that's written directly to disk by `prisma generate`, not something deploy resolves from a registry. Fixed by regenerating inside the deployed output.
- The `next.config.ts` build-time-rewrites bug above — only visible once an actual built image ran with a runtime-injected `API_URL`.
- `templates/ingress.yaml` had `backend.service.number` instead of `backend.service.port.number` — valid YAML, valid Helm template, but rejected by the real Kubernetes API server's schema validation on `helm install`. `helm template` never sends anything to a real API server, so it can't catch this class of bug — only an actual cluster (kind, here) can.
