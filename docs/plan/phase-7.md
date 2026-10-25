# Phase 7: Complete and polish

> **ID key:** **P** = Phase, **M** = Milestone. `P7-M2` = Phase 7, Milestone 2 · `P7-06` = Phase 7, task 06.

> **Status: draft.** Written ahead of time. Review and adjust it at the end of Phase 6, before starting.

**Goal:** finish the product (async notifications, web UI), prove reliability under failure, and turn the work into a portfolio a reviewer can understand in five minutes: README, diagrams, ADRs, runbooks and a demo video.

**Exit criteria:** the project's [definition of done](../../README.md#definition-of-done):

- [ ] One-command bring-up and teardown of the full environment
- [ ] A commit to any service flows through scanning, signing, GitOps PR and canary rollout with no manual `kubectl`
- [ ] Unsigned or non-compliant images are rejected by the cluster
- [ ] Injected failure in `bank-gateway-mock` triggers canary auto-rollback, an SLO burn-rate alert in Slack and a traceable root cause in Grafana
- [ ] Velero restore drill documented and tested
- [ ] README with architecture diagram, setup guide and screenshots/GIFs; ADRs and runbooks written; 5-minute demo video recorded

## Milestones

| Milestone | Outcome | Tasks |
|---|---|---|
| [P7-M1 Async events](#p7-m1-async-events) | SQS events, notification-service, KEDA | P7-01 – P7-03 |
| [P7-M2 Web app](#p7-m2-web-app) | Next.js UI with Auth0 login | P7-04 |
| [P7-M3 Reliability](#p7-m3-reliability) | Restore drill, chaos experiments, load tests, Karpenter tuning, OpenCost | P7-05 – P7-09 |
| [P7-M4 Showcase](#p7-m4-showcase) | Demo, README, video, v1.0.0 | P7-10 – P7-13 |

---

## P7-M1 Async events

### P7-01: SQS queue + DLQ
- **Scope:**
  - Terraform: `transfer-events` queue + DLQ (`maxReceiveCount=3`), KMS-encrypted
  - Pod Identity roles: transfer-service can send only; notification-service can receive and delete only
  - DLQ alarm: CloudWatch alarm → SNS → email (free tier)
- **Acceptance criteria:**
  - [ ] Infracost reviewed; IAM is least-privilege (Checkov clean)
- **Depends on:** Phase 2
- **Runs on:** AWS (cents) — **needs your approval to apply**
- **Output:** `infra/modules/sqs/`, `infra/live/dev/sqs/`

### P7-02: Event publishing + notification-service
- **Scope:**
  - transfer-service publishes `transfer.completed` after the ledger commit, with `traceparent` as a message attribute
  - notification-service (Python): long-polls, dedupes by `event_id`, logs the "notification", continues the trace
  - Poison messages land in the DLQ
- **Acceptance criteria:**
  - [ ] One transfer → one notification log line → **one trace** spanning the async hop
  - [ ] A forced failure lands in the DLQ and the alarm fires
- **Depends on:** P7-01
- **Output:** `services/notification-service/`, `services/transfer-service/`

### P7-03: KEDA scaling on queue depth
- **Scope:** KEDA via Argo CD (Pod Identity); `ScaledObject` for notification-service on SQS depth, minimum **0** replicas
- **Acceptance criteria:**
  - [ ] Idle → 0 pods; a burst of 500 events scales out, then back to 0
- **Depends on:** P7-02
- **Output:** `gitops/platform/keda/`, `gitops/apps/notification-service/`

## P7-M2 Web app

### P7-04: web-app (Next.js)
- **Scope:**
  - Auth0 Next.js SDK login
  - Dashboard (balance), send money (generates an `Idempotency-Key` per submit and disables double-submit), history with pagination
  - Served at `/` through the gateway; the SPA callback URLs in the Auth0 Terraform are updated
  - Built and shipped through the golden pipeline
- **Acceptance criteria:**
  - [ ] Real-browser flow: sign up → top up → send → history
  - [ ] ZAP baseline clean
- **Depends on:** Phase 4
- **Output:** `services/web-app/`, `infra/modules/auth0/`

## P7-M3 Reliability

### P7-05: Velero + restore drill
- **Scope:**
  - Velero with an S3 bucket (Pod Identity), scheduled backups of the `ledgerpay-*` namespaces
  - **Drill:** delete `ledgerpay-staging` → restore → verify healthy, with ledger totals unchanged
  - Separate RDS point-in-time restore drill (Velero covers Kubernetes resources only; RDS has its own backups); measured RTO/RPO recorded
- **Acceptance criteria:**
  - [ ] Drill runbook followed end to end, with timings recorded
- **Depends on:** Phase 3
- **Output:** `gitops/platform/velero/`, `docs/runbooks/restore-drill.md`

### P7-06: Chaos experiments
- **Scope:** Chaos Mesh via Argo CD; experiments as code:
  - Kill a wallet-service pod during load
  - 2 s latency on bank-gateway-mock
  - Network partition between transfer and fraud
  - Spot-node interruption simulation
  - Each with an expected outcome stated up front
- **Acceptance criteria:**
  - [ ] Each experiment's hypothesis holds (or is fixed and re-run), with results documented
- **Depends on:** Phase 5
- **Output:** `chaos/`, `docs/reliability/chaos-results.md`

### P7-07: k6 load tests
- **Scope:** smoke and load suites; `workflow_dispatch` run against staging; thresholds tied to the SLOs; baseline numbers published
- **Acceptance criteria:**
  - [ ] Staging sustains the target load within SLO; results are in the README
- **Depends on:** Phase 4 k6 scripts
- **Output:** `tests/k6/`, `.github/workflows/load-test.yml`

### P7-08: Karpenter tuning
- **Scope:**
  - Right-size requests from real usage
  - Disruption budgets; consolidation policy
  - Spot interruption handling verified
  - Workloads spread across AZs (topology spread constraints)
- **Acceptance criteria:**
  - [ ] Measured lower $/hr with no SLO regressions (before/after recorded)
- **Depends on:** P7-07
- **Output:** `infra/modules/karpenter/`, `charts/ledgerpay-lib/`

### P7-09: OpenCost
- **Scope:** OpenCost via Argo CD using Prometheus; per-namespace and per-service cost dashboard
- **Acceptance criteria:**
  - [ ] The dashboard shows dev, staging and prod costs separately, close to the actual AWS bill
- **Depends on:** Phase 5
- **Output:** `gitops/platform/opencost/`

## P7-M4 Showcase

### P7-10: The full demo, scripted
- **Scope:** `make demo` plus a runbook for the complete [demo scenario](../../README.md#demo-scenario):
  1. Push → CI → bot PR → canary
  2. Inject a failure → abort
  3. Slack alert → Grafana → Tempo → Loki
- **Acceptance criteria:**
  - [ ] Runs end to end three times without surprises
- **Depends on:** all previous phases
- **Output:** `docs/runbooks/demo.md`, `Makefile`

### P7-11: README and docs polish
- **Scope:**
  - Final architecture diagrams (all 7, marked "built")
  - Setup guide from zero (AWS account → `make up`)
  - Screenshots/GIFs (pipeline, Argo CD, canary abort, Grafana click path, Kiali, Falco alert)
  - ADR index complete; every runbook linked; "what I'd do next" section
- **Acceptance criteria:**
  - [ ] Someone else follows the setup guide successfully (or a clean-account dry run)
- **Output:** `README.md`, `docs/`

### P7-12: Demo video
- **Scope:** 5-minute recording following the demo script; linked at the top of the README
- **Acceptance criteria:**
  - [ ] ≤ 5 minutes; covers pipeline, GitOps, canary rollback, observability and security rejection
- **Output:** README link

### P7-13: Definition-of-done audit + v1.0.0
- **Scope:**
  - Tick every item in the definition of done with linked evidence
  - Final cost report
  - Tag `v1.0.0` with release notes; project retrospective
- **Acceptance criteria:**
  - [ ] All exit criteria above ticked
- **Output:** GitHub Release, `docs/plan/phase-7.md`

---

## Cost of Phase 7

| Item | ~USD |
|---|---|
| SQS, Velero S3, KEDA, Chaos Mesh, OpenCost | ~+$0.02/hr while up, cents/month at rest |
| Demo recording sessions | a few environment-hours |
