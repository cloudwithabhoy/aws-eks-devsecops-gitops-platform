# Phase 3: GitOps

> **ID key:** **P** = Phase, **M** = Milestone. `P3-M2` = Phase 3, Milestone 2 · `P3-06` = Phase 3, task 06.

> **Status: draft.** Written ahead of time. Review and adjust it at the end of Phase 2, before starting.

**Goal:** Git is the only way to change what runs. A merge to a service makes CI open a PR that updates dev; promotion to staging and prod is a reviewed PR that moves the **same image digest**; rollback is `git revert`. Nobody runs `kubectl apply`.

**Exit criteria:**

- [ ] A merge to `wallet-service` reaches `ledgerpay-dev` with **no manual step and no `kubectl`**
- [ ] Promotion to staging and prod happens only through approved PRs, and all three environments run the **same digest**
- [ ] `git revert` of a promotion PR rolls the environment back
- [ ] Argo CD login is GitHub SSO only; the local admin is disabled
- [ ] Nothing secret is in Git: DB credentials arrive through External Secrets
- [ ] GitOps CI rejects a manifest that breaks policy (no limits, `latest` tag, root user)

## Milestones

| Milestone | Outcome | Tasks |
|---|---|---|
| [P3-M1 Charts and local loop](#p3-m1-charts-and-local-loop) | Library chart, versioned, testable on kind for free | P3-01 – P3-04 |
| [P3-M2 Argo CD](#p3-m2-argo-cd) | Argo CD bootstrapped and hardened, app-of-apps + ApplicationSets | P3-05 – P3-07 |
| [P3-M3 First real deployment](#p3-m3-first-real-deployment) | wallet-service running in dev with secrets and migrations | P3-08 – P3-11 |
| [P3-M4 Promotion flow](#p3-m4-promotion-flow) | CI bot PRs, reviewed promotions, GitOps CI | P3-12 – P3-14 |
| [P3-M5 Wrap-up](#p3-m5-wrap-up) | Diagram #3, runbooks | P3-15 |

---

## P3-M1 Charts and local loop

### P3-01: kind cluster for local GitOps
- **Why:** develop charts, Argo CD config and policies for free before using EKS.
- **Scope:**
  - `kind` config (1 control plane + 1 worker) and `make kind-up` / `make kind-down`
  - Images built locally and loaded with `kind load`
- **Acceptance criteria:**
  - [ ] `make kind-up` gives a working cluster in < 2 minutes
- **Depends on:** —
- **Runs on:** local ($0)
- **Output:** `local/kind.yaml`, `Makefile`

### P3-02: Helm library chart `ledgerpay-lib`
- **Why:** every service gets the same hardened deployment from one place.
- **Scope:** named templates for:
  - Deployment with a restricted security context: non-root, read-only root filesystem, all capabilities dropped, seccomp `RuntimeDefault`
  - Liveness, readiness and startup probes on `/healthz` / `/readyz`
  - **Required** resources
  - Service, ServiceAccount, PodDisruptionBudget, HPA
  - Prometheus scrape annotations (ServiceMonitor arrives in Phase 5)
  - `values.schema.json` that **fails rendering** if limits or probes are missing
- **Acceptance criteria:**
  - [ ] `helm template` for a minimal values file produces manifests that pass `trivy config` with no HIGH findings
  - [ ] Missing `resources` fails the render
- **Depends on:** —
- **Runs on:** local
- **Output:** `charts/ledgerpay-lib/`

### P3-03: Publish the chart to ECR (OCI)
- **Why:** services depend on a **versioned** chart, not copied templates.
- **Scope:**
  - ECR repository for charts (added in `infra/bootstrap`)
  - Workflow that runs on tag `charts/ledgerpay-lib/vX.Y.Z`, then lints, packages and pushes via OIDC
  - Chart CHANGELOG
- **Acceptance criteria:**
  - [ ] `helm pull oci://<ecr>/charts/ledgerpay-lib --version 0.1.0` works
- **Depends on:** P3-02
- **Runs on:** GitHub Actions + AWS (cents)
- **Output:** `.github/workflows/chart-release.yml`, `infra/bootstrap/`

### P3-04: wallet-service deployment config
- **Why:** the first application expressed as GitOps config.
- **Scope:**
  - `gitops/apps/wallet-service/` with a thin chart depending on `ledgerpay-lib`
  - `values.yaml` (common) plus `dev/`, `staging/` and `prod/` overrides (replicas, resources, image digest)
- **Acceptance criteria:**
  - [ ] Deploys on kind via `helm install` and reports Ready
- **Depends on:** P3-01, P3-03
- **Runs on:** local
- **Output:** `gitops/apps/wallet-service/`

## P3-M2 Argo CD

### P3-05: Argo CD bootstrap + app-of-apps
- **Why:** the controller that makes Git the source of truth.
- **Scope:**
  - Argo CD Helm release from Terraform (Terraform bootstraps only Karpenter and Argo CD), pinned, on the add-on node; no repo credentials needed because the repo is public
  - A root `Application` pointing at `gitops/platform/`
  - Platform add-ons as child apps, ordered with **sync waves**
  - Added to `make up`
- **Acceptance criteria:**
  - [ ] After `make up`, the root app and its children are Synced/Healthy with no manual steps
- **Depends on:** Phase 2
- **Runs on:** AWS (and kind for development)
- **Output:** `infra/modules/argocd-bootstrap/`, `gitops/platform/`

### P3-06: AppProjects + ApplicationSets
- **Why:** per-environment apps are generated, and permissions are scoped.
- **Scope:**
  - `AppProject`s: `platform` (platform namespaces) and `ledgerpay` (only `ledgerpay-*` namespaces, only this repo, no cluster-scoped resources)
  - `ApplicationSet` using a git directory generator over `gitops/apps/*/*`, creating `<svc>-<env>` apps
  - **dev auto-syncs** with self-heal; staging and prod sync automatically too, but only change through reviewed PRs
- **Acceptance criteria:**
  - [ ] Adding a new `gitops/apps/x/dev` directory creates an app with no other changes
  - [ ] An app in the `ledgerpay` project can't deploy into `kube-system`
- **Depends on:** P3-05
- **Output:** `gitops/platform/argocd/`

### P3-07: Argo CD hardening
- **Why:** the deployment tool is a high-value target.
- **Scope:**
  - GitHub SSO through the built-in Dex (GitHub OAuth app; client secret via ESO)
  - Local `admin` disabled
  - RBAC: `role:admin` for you, read-only by default
  - Notifications to Slack on sync failure or health degradation
- **Acceptance criteria:**
  - [ ] Admin login is impossible; SSO login works; an anonymous user sees nothing
- **Depends on:** P3-06, P3-09
- **Output:** `gitops/platform/argocd/`

## P3-M3 First real deployment

### P3-08: Application namespaces and guardrails
- **Why:** environments are isolated, and their cost is capped.
- **Scope:**
  - Namespaces `ledgerpay-dev`, `ledgerpay-staging` and `ledgerpay-prod`, with Pod Security Standards labels (`enforce: restricted`)
  - `ResourceQuota` and `LimitRange` per namespace
- **Acceptance criteria:**
  - [ ] A privileged pod is rejected by PSS
  - [ ] Exceeding the quota fails clearly
- **Depends on:** P3-06
- **Output:** `gitops/platform/namespaces/`

### P3-09: External Secrets Operator
- **Why:** secrets come from Secrets Manager; Git only holds *references*. (ESO moved here from Phase 6 so no secret is ever in Git.)
- **Scope:**
  - ESO via Argo CD; Pod Identity role scoped to `ledgerpay/*` secrets
  - `ClusterSecretStore`
  - `ExternalSecret` templates in the library chart
- **Acceptance criteria:**
  - [ ] Rotating a secret value in Secrets Manager updates the Kubernetes Secret within the refresh interval
  - [ ] `git grep` finds no secret values
- **Depends on:** P3-05
- **Output:** `gitops/platform/external-secrets/`, `charts/ledgerpay-lib/`

### P3-10: DB provisioning + migrations as PreSync hooks
- **Why:** schema changes go out *before* the new code, automatically.
- **Scope:**
  - The Phase 2 DB-provisioning Job becomes an Argo CD **PreSync** hook
  - The Flyway migration Job is a second PreSync hook (it uses the service image)
  - Both are idempotent, with a deadline and backoff limit
- **Acceptance criteria:**
  - [ ] Fresh environment: database, role and schema are created on first sync
  - [ ] A failing migration blocks the rollout (proven)
- **Depends on:** P3-09
- **Output:** `charts/ledgerpay-lib/`, `gitops/apps/wallet-service/`

### P3-11: wallet-service live in dev
- **Why:** the first end-to-end deployment on EKS.
- **Scope:**
  - Synced through the ApplicationSet; runs on Karpenter Spot nodes
  - Auth0 issuer and audience from config
  - Metrics Server installed (for HPA)
- **Acceptance criteria:**
  - [ ] Via port-forward: get a token, check the balance and run a transfer, as in the Phase 1 local test
  - [ ] Killing a pod is self-healed
- **Depends on:** P3-04, P3-10
- **Runs on:** AWS
- **Output:** `gitops/`

## P3-M4 Promotion flow

### P3-12: CI bot PR (golden pipeline stage 11)
- **Why:** CI never deploys; it proposes a change to Git.
- **Scope:**
  - GitHub App `ledgerpay-bot` with contents + pull-request permissions on this repo only: short-lived installation tokens, no personal token
  - After sign and push on `main`, `service-ci` opens a PR setting the new **digest** in `gitops/apps/<svc>/dev/values.yaml`, with the commit, scan summary and SBOM link in the PR body
  - Auto-merge once GitOps CI passes
- **Acceptance criteria:**
  - [ ] Merge to the service → bot PR → auto-merged → dev running the new digest, end to end with no human step
- **Depends on:** P3-06, P3-14
- **Output:** `.github/workflows/service-ci.yml`

### P3-13: Promotion workflow
- **Why:** moving to staging and prod is deliberate, reviewed and traceable.
- **Scope:**
  - `promote.yml` (`workflow_dispatch`: service, from, to) opens a PR that copies the digest from the source environment
  - GitHub Environments `staging` and `prod` with required reviewers
  - CODEOWNERS on `gitops/apps/*/prod/`
- **Acceptance criteria:**
  - [ ] A promotion PR can't merge without approval
  - [ ] After merge, prod runs the exact digest that was tested in staging
  - [ ] Reverting the PR rolls prod back
- **Depends on:** P3-12
- **Output:** `.github/workflows/promote.yml`, `.github/CODEOWNERS`

### P3-14: GitOps CI
- **Why:** catch bad manifests before Argo CD ever sees them.
- **Scope:** `gitops-ci.yml`, path-filtered to `gitops/**` and `charts/**`:
  - `helm lint`
  - Render every app × environment
  - **Trivy config** on the rendered output
  - **Conftest** policies (`policy/`): image by digest from our ECR, resources set, probes present, non-root, no `hostPath`
- **Acceptance criteria:**
  - [ ] Each policy is proven to fail once on a bad example
  - [ ] Runs in < 3 minutes
- **Depends on:** P3-04
- **Output:** `.github/workflows/gitops-ci.yml`, `policy/`

## P3-M5 Wrap-up

### P3-15: Phase 3 wrap-up
- **Scope:**
  - **Diagram #3, CD/GitOps and promotion** (Mermaid)
  - Runbooks: "promote a release", "roll back", "Argo CD app out of sync"
  - ADR-0005: "Promotion by digest through PRs"
  - README status; retrospective
- **Acceptance criteria:**
  - [ ] All exit criteria ticked, with evidence
- **Output:** `docs/architecture/`, `docs/runbooks/`, `docs/adr/`

---

## Cost of Phase 3

Same as Phase 2 (environment-hours). Argo CD runs on the existing add-on node. kind work is free.
