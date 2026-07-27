# kind/argocd

GitOps config for the `kind` deployment. The same pattern carries over to EKS — see "Taking this to EKS" in `../README.md`.

```
bootstrap/
  namespace.yaml           landing-builder namespace — applied manually, once
  argocd-projects.yaml     AppProject — scopes what this app-of-apps can touch
app-of-apps.yaml          the one thing you `kubectl apply` yourself
applications/
  project.yaml              your app chart (../project), automated sync
  monitoring.yaml            Prometheus + Grafana, values from ../../monitoring/values.yaml, automated sync
  argocd.yaml                 ArgoCD managing its own install — MANUAL sync only, see the file's own comments
```

## Bootstrap order

ArgoCD itself is already installed (`kubectl create namespace argocd` + the install manifest, done earlier). From this repo's root:

```sh
# 1. Namespace the app will live in
kubectl apply -f kind/argocd/bootstrap/namespace.yaml

# 2. AppProject
kubectl apply -f kind/argocd/bootstrap/argocd-projects.yaml

# 3. Hand the rest to GitOps
kubectl apply -f kind/argocd/app-of-apps.yaml
```

## Before step 3 will actually do anything

ArgoCD polls `repoURL` over the network — it doesn't read your local disk. Every file in this folder only takes effect once it's **committed and pushed** to `main` on `github.com/justthatpixel/eks-configuration` (this repo — note this is a *different* repo from the app itself, which lives at `github.com/justthatpixel/Three-Tier-Kubernetes-DevSecOps-Project`). Until this repo is pushed, `app-of-apps-kind` and `project` will show as `Unknown`/missing in the ArgoCD UI.

## What happens to the releases you already installed manually

Same story for all three:

- `project` — sitting in `default` right now. Once `applications/project.yaml` syncs, ArgoCD installs its *own* copy into `landing-builder`. Clean up the manual one after confirming the GitOps-managed copy works: `helm uninstall project`.
- `monitoring` — `applications/monitoring.yaml` is pinned to the exact chart version already installed (`87.19.1`), so ArgoCD should *adopt* the existing release in place rather than creating a duplicate — but verify this with `argocd app diff monitoring` before trusting `selfHeal` with it.
- `argocd` itself — **do not** just let `applications/argocd.yaml` auto-sync (it can't; there's no automated block on purpose). Review the diff first — see the warning comment in that file.

```sh
helm uninstall project        # the old one in `default`, once landing-builder's copy is confirmed working
```
