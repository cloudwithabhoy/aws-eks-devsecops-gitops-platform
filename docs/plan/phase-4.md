# Phase 4: Payment path, mesh and progressive delivery

> **ID key:** **P** = Phase, **M** = Milestone. `P4-M3` = Phase 4, Milestone 3 · `P4-11` = Phase 4, task 11.

> **Status: draft.** Written ahead of time. Review and adjust it at the end of Phase 3, before starting.

**Goal:** the full payment path runs on EKS behind HTTPS. Users authenticate with Auth0 at the edge, services talk over mTLS with an explicit allow-list, and new versions roll out as canaries that **abort automatically** when the bank mock starts failing.

**Exit criteria:**

- [ ] Over HTTPS with a valid certificate: Auth0 token → top-up → send money → history, in dev
- [ ] `/internal/*` is unreachable from outside (404) and from any service except `transfer-service` (403)
- [ ] The same `Idempotency-Key` sent twice moves money once, end to end
- [ ] Raising `FAILURE_RATE` during a canary makes the Prometheus analysis fail, and the rollout **aborts and rolls back with no human action**
- [ ] OWASP ZAP baseline against staging reports no High alerts
- [ ] The golden pipeline builds Go, Python and Node.js services, not just Java

## Milestones

| Milestone | Outcome | Tasks |
|---|---|---|
| [P4-M1 Payment services](#p4-m1-payment-services) | transfer, fraud and bank-mock services built through the golden pipeline | P4-01 – P4-06 |
| [P4-M2 Edge and mesh](#p4-m2-edge-and-mesh) | HTTPS ingress, Istio mTLS, JWT at the gateway, allow-list AuthZ | P4-07 – P4-11 |
| [P4-M3 Progressive delivery](#p4-m3-progressive-delivery) | Canary with automated analysis and auto-rollback | P4-12 – P4-15 |
| [P4-M4 DAST and wrap-up](#p4-m4-dast-and-wrap-up) | ZAP in the pipeline, diagram #4 | P4-16 – P4-17 |

---

## P4-M1 Payment services

### P4-01: Golden pipeline for Go, Python and Node.js
- **Why:** the reusable workflow must really be reusable across languages.
- **Scope:** add a `language` input to `service-ci.yml` with per-language lint, test and coverage steps:
  - Go: golangci-lint, `go test -cover`
  - Python: ruff, mypy, pytest-cov
  - Node.js: eslint, test coverage
- **Acceptance criteria:**
  - [ ] Each language's gates are proven to fail once on a bad change
- **Depends on:** Phase 1 pipeline
- **Output:** `.github/workflows/service-ci.yml`

### P4-02: transfer-service
- **Why:** the orchestrator on the payment path.
- **Scope:**
  - Go service with the full service contract and JWT middleware
  - `POST /api/transfers`, `/api/topups` and `/api/withdrawals`, each requiring `Idempotency-Key`
  - Redis `SET NX` idempotency with stored responses
  - Calls `fraud-service`, then `wallet-service` (`/internal`), then `bank-gateway-mock`
  - Fail closed on fraud errors; compensating reversal when a payout fails
  - Distroless static image
- **Acceptance criteria:**
  - [ ] Unit + integration tests cover replay, fraud block, wallet failure and payout reversal
  - [ ] Coverage ≥ 80%
- **Depends on:** P4-01
- **Output:** `services/transfer-service/`

### P4-03: fraud-service
- **Why:** a realistic synchronous risk check with its own latency budget.
- **Scope:**
  - FastAPI service; `POST /internal/v1/score`
  - The rules from the application design; thresholds from env
  - Redis sliding-window velocity counters
- **Acceptance criteria:**
  - [ ] Every rule has a test
  - [ ] p99 latency < 50 ms locally under a k6 smoke test
- **Depends on:** P4-01
- **Output:** `services/fraud-service/`

### P4-04: bank-gateway-mock
- **Why:** the failure lever for every resilience demo.
- **Scope:**
  - Node.js service; `POST /v1/charges` and `/v1/payouts`
  - `FAILURE_RATE` and `LATENCY_MS` read at request time, so they can be changed live through config
- **Acceptance criteria:**
  - [ ] With `FAILURE_RATE=0.3`, about 30% of 1,000 requests return 503
- **Depends on:** P4-01
- **Output:** `services/bank-gateway-mock/`

### P4-05: Redis + ECR + secrets for the new services
- **Why:** infrastructure for the new services.
- **Scope:**
  - ElastiCache `cache.t4g.micro` single node in dev; TLS + AUTH; security group allows only EKS
  - ECR repositories for the three services
  - Secrets Manager entries, delivered via ESO
- **Acceptance criteria:**
  - [ ] Infracost diff reviewed
  - [ ] Redis is reachable only from the cluster, over TLS
- **Depends on:** Phase 2
- **Runs on:** AWS (~$0.02/hr) — **needs your approval to apply**
- **Output:** `infra/modules/redis/`, `infra/live/dev/redis/`, `infra/bootstrap/`

### P4-06: Deploy the payment path to dev
- **Why:** all four services running together through GitOps.
- **Scope:**
  - `gitops/apps/{transfer,fraud,bank-gateway-mock}-service/` using the library chart
  - Bot PRs and promotions work for each
- **Acceptance criteria:**
  - [ ] Via port-forward: top-up → transfer → withdrawal works, and balances reconcile
- **Depends on:** P4-02 – P4-05
- **Output:** `gitops/apps/`

## P4-M2 Edge and mesh

### P4-07: AWS Load Balancer Controller
- **Scope:** installed via Argo CD; Pod Identity role; creates the NLB for a `LoadBalancer` Service, tagged `project=ledgerpay`
- **Acceptance criteria:**
  - [ ] A test Service gets an internet-facing NLB
  - [ ] `make destroy` removes it (cost-reaper shows 0)
- **Depends on:** Phase 3
- **Output:** `gitops/platform/aws-load-balancer-controller/`

### P4-08: Istio + ingress gateway
- **Scope:**
  - `istio-base`, `istiod` and an ingress gateway (Service type `LoadBalancer` → NLB) via Argo CD, using sync waves
  - Sidecar injection on `ledgerpay-*` namespaces
  - Mesh-wide `PeerAuthentication` **STRICT**
- **Acceptance criteria:**
  - [ ] Plain-text pod-to-pod traffic is refused
  - [ ] `istioctl analyze` is clean
- **Depends on:** P4-07
- **Output:** `gitops/platform/istio/`

### P4-09: DNS + TLS
- **Scope:**
  - Route 53 hosted zone for a real domain (a cheap one, ~$3–12/year, or a subdomain you own)
  - ExternalDNS and cert-manager via Argo CD, each with a Pod Identity role
  - Let's Encrypt `ClusterIssuer` using DNS-01 (staging issuer first, then prod)
  - Wildcard certificate on the gateway
- **Acceptance criteria:**
  - [ ] `https://api.dev.<domain>` serves a valid certificate
  - [ ] The DNS record is created and removed automatically
- **Depends on:** P4-08
- **Runs on:** AWS ($0.50/month hosted zone + domain)
- **Output:** `gitops/platform/{external-dns,cert-manager}/`, `infra/live/dev/dns/`

### P4-10: Routing + JWT at the edge
- **Scope:**
  - `Gateway` + `VirtualService` routing `/api/wallets`, `/api/transfers`, `/api/topups` and `/api/withdrawals`; **no route** for `/internal/*`
  - `RequestAuthentication` (Auth0 issuer + JWKS)
  - `AuthorizationPolicy` requiring a valid JWT on `/api/*`
- **Acceptance criteria:**
  - [ ] No token → 401 at the gateway (the pod is never hit)
  - [ ] `/internal/...` from outside → 404
- **Depends on:** P4-09
- **Output:** `gitops/platform/istio/`, `charts/ledgerpay-lib/`

### P4-11: Service-to-service AuthZ + resilience
- **Scope:**
  - Deny-by-default `AuthorizationPolicy` per namespace, plus allow rules from the [call matrix](../application/README.md#who-may-call-whom), generated by the library chart from values
  - `DestinationRule` for `bank-gateway-mock`: timeouts, 2 retries with backoff, outlier detection (circuit breaker)
- **Acceptance criteria:**
  - [ ] `fraud-service` calling `wallet-service` → 403
  - [ ] With `LATENCY_MS=5000`, transfer-service times out in ~2 s instead of hanging
- **Depends on:** P4-10
- **Output:** `charts/ledgerpay-lib/`, `gitops/apps/*/`

## P4-M3 Progressive delivery

### P4-12: Minimal Prometheus
- **Scope:** kube-prometheus-stack with only Prometheus and the operator (no Grafana yet); scrapes Istio and service metrics; 3-day retention. Installed minimally here because canary analysis needs it; Phase 5 adds the rest
- **Acceptance criteria:**
  - [ ] An error-rate PromQL query per service returns data
- **Depends on:** P4-08
- **Output:** `gitops/platform/monitoring/`

### P4-13: Argo Rollouts + canary in the library chart
- **Scope:**
  - Argo Rollouts via Argo CD
  - The library chart can render a `Rollout` instead of a `Deployment`
  - Canary steps 10 → 25 → 50 → 100% with pauses
  - Istio `VirtualService` traffic routing
- **Acceptance criteria:**
  - [ ] A new digest for transfer-service rolls out step by step, visible in the Rollouts dashboard
- **Depends on:** P4-11
- **Output:** `gitops/platform/argo-rollouts/`, `charts/ledgerpay-lib/`

### P4-14: AnalysisTemplates
- **Scope:** shared `ClusterAnalysisTemplate`s querying Prometheus:
  - Error rate < 1%
  - p99 latency < 800 ms
  - Run at each canary step, with failure limits
- **Acceptance criteria:**
  - [ ] A healthy rollout passes analysis automatically
- **Depends on:** P4-12, P4-13
- **Output:** `gitops/platform/argo-rollouts/`

### P4-15: The canary rollback demo
- **Why:** the headline demo, proven and repeatable.
- **Scope:**
  - k6 script producing steady transfer traffic
  - Runbook: start a canary → raise `FAILURE_RATE` → analysis fails → automatic abort and rollback
  - `make demo-canary`
- **Acceptance criteria:**
  - [ ] Three runs in a row: abort within 2 analysis intervals, traffic back to stable, no manual action
- **Depends on:** P4-14
- **Output:** `tests/k6/`, `docs/runbooks/demo-canary.md`, `Makefile`

## P4-M4 DAST and wrap-up

### P4-16: OWASP ZAP baseline
- **Scope:** after each staging promotion, a workflow runs the ZAP baseline scan against the staging URL; report uploaded; High alerts fail the run and notify Slack
- **Acceptance criteria:**
  - [ ] Report attached to the run; documented exceptions only
- **Depends on:** P4-10
- **Output:** `.github/workflows/dast.yml`, `.zap/rules.tsv`

### P4-17: Phase 4 wrap-up
- **Scope:**
  - **Diagram #4, runtime and request flow**
  - ADR-0006 "Istio sidecar mode"; ADR-0007 "AuthZ at the mesh layer + JWT at the edge"
  - README status; retrospective
- **Acceptance criteria:**
  - [ ] All exit criteria ticked, with evidence (including the recorded canary abort)
- **Output:** `docs/architecture/`, `docs/adr/`

---

## Cost of Phase 4

| Item | ~USD |
|---|---|
| Added while up: NLB (~$0.025/hr), Redis (~$0.02/hr), Istio sidecars (more Spot capacity) | ~+$0.08–0.12/hr |
| Domain + hosted zone | ~$0.50/month + domain |
