# Phase 2: Infrastructure

> **ID key:** **P** = Phase, **M** = Milestone. `P2-M3` = Phase 2, Milestone 3 · `P2-07` = Phase 2, task 07.

> **Status: draft.** Written ahead of time. Review and adjust it at the end of Phase 1, before starting (see the just-in-time rule in [README](README.md)).

**Goal:** one command builds a cost-optimised EKS platform on AWS from nothing, and one command tears it down leaving **zero** billable resources behind. Infrastructure changes go through the same review and CI as code.

**Exit criteria:**

- [ ] `make up` creates VPC, EKS, Karpenter and RDS from a clean account in **< 25 minutes**
- [ ] A test workload makes Karpenter launch a **Graviton Spot** node, which is consolidated away once the workload is deleted
- [ ] `make destroy` followed by `cost-reaper report` finds **nothing** left
- [ ] Terraform `plan` runs on every infra PR (with an Infracost comment); `apply` runs on merge, with manual approval for prod
- [ ] The nightly destroy has run successfully at least once
- [ ] Measured cost while up is within the ADR-0002 estimate (~$0.30–0.50/hr)

## Milestones

| Milestone | Outcome | Tasks |
|---|---|---|
| [P2-M1 Terraform foundations](#p2-m1-terraform-foundations) | Terragrunt layout, CI roles, plan/apply pipeline | P2-01 – P2-03 |
| [P2-M2 Network](#p2-m2-network) | VPC ready for EKS | P2-04 |
| [P2-M3 EKS + Karpenter](#p2-m3-eks--karpenter) | Cluster with Graviton Spot autoscaling | P2-05 – P2-07 |
| [P2-M4 Data](#p2-m4-data) | RDS reachable only from the cluster | P2-08 – P2-09 |
| [P2-M5 Lifecycle and cost safety](#p2-m5-lifecycle-and-cost-safety) | `make up` / `make destroy`, nightly destroy, cost-reaper | P2-10 – P2-14 |
| [P2-M6 Wrap-up](#p2-m6-wrap-up) | Evidence, diagrams, retrospective | P2-15 |

---

## P2-M1 Terraform foundations

### P2-01: Terragrunt root and module conventions
- **Why:** every environment is built the same way, and every resource is tagged for cost tracking and for the cost-reaper.
- **Scope:**
  - `infra/live/terragrunt.hcl`:
    - remote state in the bootstrap bucket (one key per stack)
    - generated provider blocks with `default_tags` (`project=ledgerpay`, `env`, `managed-by=terraform`)
  - `infra/live/{dev,staging,prod}/env.hcl` (sizing and toggles per environment, e.g. `single_nat`, `interface_endpoints`)
  - Module convention: `infra/modules/<name>/` with pinned provider versions and a README; releases tagged `modules/<name>/vX.Y.Z`; `live` pins modules by `?ref=`
- **Acceptance criteria:**
  - [ ] `terragrunt run-all validate` passes for dev
  - [ ] Module tagging and release convention documented in `infra/README.md`
- **Depends on:** Phase 1 (bootstrap bucket)
- **Runs on:** local
- **Output:** `infra/live/terragrunt.hcl`, `infra/live/*/env.hcl`, `infra/README.md`

### P2-02: Terraform CI roles
- **Why:** CI can plan and apply without keys, with the least privilege for each job.
- **Scope:** extend `infra/bootstrap` with:
  - `ledgerpay-tf-plan`: read-only access, trusted for pull-request workflows of this repo
  - `ledgerpay-tf-apply`: trusted **only** for `main` + the matching GitHub Environment (`infra-dev`, `infra-prod`), with a permissions boundary that blocks IAM user creation and changes to the bootstrap stack
- **Acceptance criteria:**
  - [ ] A PR workflow can't assume the apply role (proven)
  - [ ] Checkov is clean
- **Depends on:** P2-01
- **Runs on:** AWS ($0) — **needs your approval to apply**
- **Output:** `infra/bootstrap/`

### P2-03: Infra CI v2: plan, cost, apply
- **Why:** infrastructure changes are reviewed with their real plan and cost impact.
- **Scope:** extend `infra-ci.yml`:
  - On PRs: `terragrunt plan` for the affected stacks, posted as a PR comment, plus an **Infracost** comment
  - On merge: `apply` through GitHub Environments (dev automatic; staging and prod require approval)
  - Plan artifacts stored, and `apply` uses the reviewed plan
- **Acceptance criteria:**
  - [ ] A PR changing an instance size shows both the plan diff and the cost diff
  - [ ] A prod apply waits for approval
- **Depends on:** P2-02
- **Runs on:** GitHub Actions + AWS
- **Output:** `.github/workflows/infra-ci.yml`

## P2-M2 Network

### P2-04: VPC module
- **Why:** the network design from diagram #1, as code.
- **Scope:**
  - Pinned terraform-aws-modules `vpc` module, wrapped in our own thin module
  - 3 AZs; public `/24`, private-app `/20` and private-data `/24` subnets (CIDRs from the diagram)
  - Single NAT gateway (toggle for one per AZ in prod)
  - **S3 gateway endpoint** always; interface endpoints (ECR api/dkr, STS) behind a toggle that is **off in dev**
  - Subnet tags for the AWS Load Balancer Controller (`kubernetes.io/role/elb`, `internal-elb`) and Karpenter discovery
- **Out of scope:** VPC flow logs (optional; documented as a prod toggle)
- **Acceptance criteria:**
  - [ ] Infracost for dev shows **one** NAT gateway and **no** interface endpoints
  - [ ] Checkov is clean (or each skip has a written reason)
- **Depends on:** P2-03
- **Runs on:** AWS (NAT ~$0.06/hr while up)
- **Output:** `infra/modules/network/`, `infra/live/dev/network/`

## P2-M3 EKS + Karpenter

### P2-05: EKS cluster
- **Why:** the managed control plane and the base for everything else.
- **Scope:**
  - EKS via the pinned terraform-aws-modules `eks` module, wrapped in our own; newest Kubernetes version in **standard support** (extended support costs $0.60/hr instead of $0.10/hr)
  - Private + IP-restricted public endpoint (CI never needs cluster access because Argo CD pulls)
  - KMS envelope encryption of Kubernetes secrets
  - Access entries: your SSO admin role, and the Terraform apply role
  - Managed add-ons: `vpc-cni` (network policy support enabled for Phase 6), `coredns`, `kube-proxy`, `eks-pod-identity-agent`, `aws-ebs-csi-driver` (via Pod Identity)
  - One managed node group: 1× `t4g.large` on-demand, tainted/labelled for platform add-ons
  - Control-plane logs: `api` and `audit` only, 3-day retention
- **Acceptance criteria:**
  - [ ] `kubectl get nodes` shows 1 arm64 node through SSO
  - [ ] Secrets are KMS-encrypted (checked with `describe-cluster`)
  - [ ] No access from a non-allow-listed IP
- **Depends on:** P2-04
- **Runs on:** AWS (~$0.10/hr control plane + node)
- **Output:** `infra/modules/eks/`, `infra/live/dev/eks/`

### P2-06: Pod Identity pattern
- **Why:** each workload gets its own least-privilege AWS role, without any credentials in pods.
- **Scope:**
  - A small module `pod-identity-role` (role + policy + association for namespace/service account)
  - Used first by the EBS CSI driver and Karpenter
- **Acceptance criteria:**
  - [ ] A test pod using the association can call `sts get-caller-identity` and gets the expected role
  - [ ] A pod without the association gets nothing
- **Depends on:** P2-05
- **Runs on:** AWS
- **Output:** `infra/modules/pod-identity-role/`

### P2-07: Karpenter
- **Why:** cheap, right-sized, fast autoscaling on Graviton Spot.
- **Scope:**
  - Controller role (Pod Identity) and node role
  - **Interruption queue** (SQS + EventBridge rules for Spot interruption and rebalance)
  - Helm release from Terraform (Terraform installs only Karpenter and Argo CD; Argo CD installs everything else)
  - `EC2NodeClass`: AL2023 arm64, tags `project=ledgerpay`, gp3 root volume
  - `NodePool`: arm64, Spot first with on-demand fallback, families `t4g`/`m7g`/`c7g`, consolidation `WhenEmptyOrUnderutilized`, CPU limit as a cost cap
- **Acceptance criteria:**
  - [ ] Scaling a test `inflate` deployment launches a Spot Graviton node in < 2 minutes
  - [ ] Deleting it consolidates the node away
  - [ ] The node carries `project=ledgerpay` (needed by the cost-reaper)
- **Depends on:** P2-06
- **Runs on:** AWS (Spot nodes only while used)
- **Output:** `infra/modules/karpenter/`, `infra/live/dev/karpenter/`

## P2-M4 Data

### P2-08: RDS PostgreSQL
- **Why:** the ledger database, managed and outside the cluster.
- **Scope:**
  - `db.t4g.micro`, single-AZ in dev (Multi-AZ toggle for prod), gp3 20 GB, storage encrypted
  - Private data subnets; security group allowing 5432 **only** from the EKS node/pod security group
  - `rds.force_ssl=1`
  - **Master password managed by RDS in Secrets Manager** (never in Terraform state)
  - `deletion_protection` and `skip_final_snapshot` set per environment (dev: disposable)
  - Tagged `project=ledgerpay`
- **Acceptance criteria:**
  - [ ] A pod in the cluster connects with TLS; nothing outside the VPC can reach it
  - [ ] No password appears in Terraform state or outputs
- **Depends on:** P2-05
- **Runs on:** AWS (~$0.02/hr)
- **Output:** `infra/modules/rds/`, `infra/live/dev/rds/`

### P2-09: Per-service database provisioning design
- **Why:** each service gets its own logical database and user, which needs a mechanism that runs *inside* the VPC.
- **Scope:**
  - Design and document a Kubernetes Job (run as an Argo CD PreSync hook in Phase 3) that, using the RDS master secret, idempotently creates database `wallet` and a least-privilege role whose password lives in Secrets Manager
  - In this phase: the Secrets Manager entries + IAM, plus a manual one-off run to prove it
- **Out of scope:** automation through Argo CD (Phase 3)
- **Acceptance criteria:**
  - [ ] Running the Job twice is a no-op the second time
  - [ ] The `wallet` role can't access other databases
- **Depends on:** P2-08
- **Runs on:** AWS
- **Output:** `docs/runbooks/db-provisioning.md`, `infra/live/dev/rds/`

## P2-M5 Lifecycle and cost safety

### P2-10: `make up` / `make destroy`
- **Why:** one command each way. This is the core of the cost model.
- **Scope:**
  - `make up`: `terragrunt run-all apply` in dependency order, update kubeconfig, wait for nodes and Karpenter to be ready, print elapsed time
  - `make destroy`, in order:
    1. Delete Kubernetes-created AWS resources: `LoadBalancer` services, PVCs, Karpenter NodeClaims
    2. `terragrunt run-all destroy`
    3. Run `cost-reaper report`
  - Both refuse to run without the expected AWS account and SSO session
- **Acceptance criteria:**
  - [ ] Clean `up` in < 25 minutes, and a clean `destroy`, each run three times in a row without manual fixes
- **Depends on:** P2-07, P2-08
- **Runs on:** local + AWS
- **Output:** `Makefile`, `scripts/up.sh`, `scripts/destroy.sh`

### P2-11: Nightly destroy safety net
- **Why:** a forgotten environment is destroyed automatically every night.
- **Scope:**
  - Scheduled workflow (e.g. 23:30 IST) that checks whether `ledgerpay-dev` exists, runs the destroy sequence with the apply role, runs the cost-reaper, and reports to Slack
  - `workflow_dispatch` for manual runs
- **Acceptance criteria:**
  - [ ] Left running on purpose, the environment is gone the next morning and the Slack report shows $0 leftover
- **Depends on:** P2-10, P2-13
- **Runs on:** GitHub Actions + AWS
- **Output:** `.github/workflows/nightly-destroy.yml`

### P2-12: cost-reaper: discovery and report
- **Why:** find what `terraform destroy` missed ([design](../../tools/cost-reaper/README.md)).
- **Scope:**
  - Python package with a Typer CLI (`report`)
  - Discovery through the tagging API and EC2/ELBv2/EBS APIs
  - Cost estimate from a price table; table and JSON output; exit codes 0/1/2
  - pytest + moto tests; ruff, mypy
  - Its own CI workflow, using the same gates as the services
- **Acceptance criteria:**
  - [ ] Moto tests plant one of each leak type, and all are reported with costs
  - [ ] Coverage ≥ 85%
- **Depends on:** P2-01
- **Runs on:** local + GitHub Actions
- **Output:** `tools/cost-reaper/`, `.github/workflows/cost-reaper.yml`

### P2-13: cost-reaper: apply and safety rules
- **Why:** safe automatic cleanup.
- **Scope:**
  - `apply` with dependency-ordered deletion
  - Refuses while the cluster is `ACTIVE`
  - Skips `ledgerpay/protected=true`
  - Structured audit log; Slack summary (webhook from Secrets Manager)
  - Dedicated IAM role with tag-conditioned delete permissions
- **Acceptance criteria:**
  - [ ] Tests prove that protected resources and resources from other projects are never deleted
  - [ ] Against real AWS: a deliberately leaked EBS volume is found and deleted
- **Depends on:** P2-12
- **Runs on:** local + AWS — **needs your approval for the real-AWS test**
- **Output:** `tools/cost-reaper/`, `infra/bootstrap/`

### P2-14: Renovate
- **Why:** pinned versions stay current without manual work.
- **Scope:**
  - `renovate.json` covering Terraform providers and modules, GitHub Actions (by SHA), Docker base-image digests and Maven
  - Grouped, weekly schedule
  - Major versions need manual review
- **Acceptance criteria:**
  - [ ] The first Renovate PRs pass CI and are readable (grouped, with changelogs)
- **Depends on:** Phase 1 CI
- **Runs on:** GitHub (Renovate GitHub App, free)
- **Output:** `renovate.json`

## P2-M6 Wrap-up

### P2-15: Phase 2 wrap-up
- **Scope:**
  - Update diagram #1 from "target" to "built", fixing any differences
  - Record measured `up`/`destroy` times and the real $/hr against the Infracost estimate
  - ADR-0004: "Terraform installs Karpenter and Argo CD; Argo CD installs everything else"
  - README status; retrospective
- **Acceptance criteria:**
  - [ ] All exit criteria ticked, with links to evidence
- **Depends on:** all of the above
- **Output:** `docs/architecture/`, `docs/adr/0004-*.md`, `docs/plan/phase-2.md`

---

## Cost of Phase 2

| Item | ~USD |
|---|---|
| Environment while up (control plane, NAT, 1 add-on node, Spot nodes, RDS) | ~$0.30–0.50/hr |
| Long-lived (state, ECR, Secrets Manager) | < $1/month |
| **Typical month** (~40 hours up) | **~$15–25** |
