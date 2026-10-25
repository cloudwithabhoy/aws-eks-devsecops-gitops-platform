# Phase 5: Observability

> **ID key:** **P** = Phase, **M** = Milestone. `P5-M2` = Phase 5, Milestone 2 · `P5-07` = Phase 5, task 07.

> **Status: draft.** Written ahead of time. Review and adjust it at the end of Phase 4, before starting.

**Goal:** metrics, logs and traces are all connected. From a spike on a Grafana panel you click into the exact failing trace in Tempo, and from that span into its log lines in Loki. SLOs are code, and their burn-rate alerts reach Slack with a runbook link.

**Exit criteria:**

- [ ] Click path works: error spike (exemplar) → Tempo trace → Loki logs for that `trace_id`
- [ ] Injecting failures fires a **burn-rate** alert in Slack, with a working runbook link
- [ ] Every dashboard, alert and SLO is in Git; nothing is created by hand in the Grafana UI
- [ ] Retention is 3–7 days and enforced; the observability stack's memory and CPU footprint is measured and documented
- [ ] A trace crosses all services in the payment path with no gaps

## Milestones

| Milestone | Outcome | Tasks |
|---|---|---|
| [P5-M1 Metrics and dashboards](#p5-m1-metrics-and-dashboards) | Full Prometheus/Alertmanager/Grafana, dashboards as code | P5-01 – P5-03 |
| [P5-M2 Logs](#p5-m2-logs) | Fluent Bit → Loki, structured and PII-safe | P5-04 – P5-05 |
| [P5-M3 Traces and correlation](#p5-m3-traces-and-correlation) | OTel → Tempo, linked to metrics and logs | P5-06 – P5-08 |
| [P5-M4 SLOs, alerts and runbooks](#p5-m4-slos-alerts-and-runbooks) | Sloth SLOs, burn-rate alerts, runbooks, Kiali | P5-09 – P5-11 |
| [P5-M5 Wrap-up](#p5-m5-wrap-up) | Diagram #6, ADR on the observability stack | P5-12 |

---

## P5-M1 Metrics and dashboards

### P5-01: Full kube-prometheus-stack
- **Scope:**
  - Expand the Phase 4 install with Alertmanager (Slack receiver; webhook via ESO) and Grafana (GitHub OAuth, anonymous access off, HTTPS behind the Istio gateway)
  - Retention 7 days / size cap
  - `ServiceMonitor`/`PodMonitor` for every service, Istio, Argo CD, Argo Rollouts and Karpenter
  - **Exemplar storage enabled**
- **Acceptance criteria:**
  - [ ] All targets are `UP`
  - [ ] A test alert reaches Slack
- **Depends on:** Phase 4
- **Output:** `gitops/platform/monitoring/`

### P5-02: Dashboards as code
- **Scope:**
  - Provisioned through the Grafana sidecar from ConfigMaps under `gitops/platform/monitoring/dashboards/`
  - Dashboards: service RED (one template for all services), payment path overview, Istio golden signals, cluster/Karpenter capacity and Spot, Argo Rollouts
- **Acceptance criteria:**
  - [ ] Wiping Grafana's storage and resyncing brings back every dashboard
- **Depends on:** P5-01
- **Output:** `gitops/platform/monitoring/dashboards/`

### P5-03: Business metrics
- **Why:** platform metrics alone don't tell you whether payments work.
- **Scope:** add counters/histograms such as `ledgerpay_transfers_total{outcome}`, `ledgerpay_fraud_decisions_total{decision}` and `ledgerpay_ledger_entries_total`, plus a business panel
- **Acceptance criteria:**
  - [ ] The panels match transfers made in a k6 run
- **Depends on:** P5-02
- **Output:** `services/*`, dashboards

## P5-M2 Logs

### P5-04: Loki + Fluent Bit
- **Scope:**
  - Loki monolithic on S3 (Pod Identity role; bucket with a 7-day lifecycle rule)
  - Fluent Bit DaemonSet parsing the JSON logs
  - Low-cardinality labels (`namespace`, `service`, `level`); `trace_id` kept as structured metadata, not a label
- **Acceptance criteria:**
  - [ ] `{service="transfer-service"} | json | level="error"` works in Grafana
- **Depends on:** P5-01
- **Output:** `gitops/platform/logging/`, `infra/live/dev/observability-buckets/`

### P5-05: Log hygiene
- **Scope:**
  - Never log tokens, passwords or full emails (masked)
  - Semgrep rule + Fluent Bit filter as a second line of defence
  - Log levels configurable by env
- **Acceptance criteria:**
  - [ ] A test that logs a JWT is caught by the Semgrep rule in CI
- **Depends on:** P5-04
- **Output:** `.semgrep/`, `gitops/platform/logging/`

## P5-M3 Traces and correlation

### P5-06: OTel Collector + Tempo
- **Scope:**
  - Collector (Deployment): OTLP in, batch, sampling (100% in dev, 10% head sampling in prod), export to Tempo
  - Tempo monolithic on S3 with 7-day retention
- **Acceptance criteria:**
  - [ ] Traces from all services appear in Tempo
- **Depends on:** P5-01
- **Output:** `gitops/platform/tracing/`

### P5-07: Instrumentation across all services
- **Scope:**
  - Java agent (already present) enabled
  - OTel SDKs in Go, Python and Node.js
  - W3C `traceparent` propagated on every outbound call
  - Spans for DB and Redis calls
- **Acceptance criteria:**
  - [ ] One transfer produces **one** trace spanning gateway → transfer → fraud → wallet → bank mock
- **Depends on:** P5-06
- **Output:** `services/*`

### P5-08: Correlation wiring
- **Why:** the headline feature of the observability stack.
- **Scope:** Grafana datasources:
  - Prometheus exemplars → Tempo
  - Tempo trace-to-logs → Loki (by `trace_id`)
  - Loki derived field `trace_id` → Tempo
  - Tempo service graph / trace-to-metrics
- **Acceptance criteria:**
  - [ ] A screen recording of the click path, metric → trace → logs, saved for the README
- **Depends on:** P5-04, P5-07
- **Output:** `gitops/platform/monitoring/`

## P5-M4 SLOs, alerts and runbooks

### P5-09: SLOs with Sloth
- **Scope:** SLO specs (transfer availability 99.5% / 30 days, transfer latency 95% < 800 ms) → generated `PrometheusRule`s with multi-window, multi-burn-rate alerts; SLO dashboard
- **Acceptance criteria:**
  - [ ] Raising `FAILURE_RATE` triggers the fast-burn alert within ~5 minutes
- **Depends on:** P5-01
- **Output:** `gitops/platform/slos/`

### P5-10: Alert rules + runbooks
- **Scope:**
  - Platform alerts (pod crash-looping, node pressure, Karpenter errors, Argo CD out of sync, cert expiry, DLQ depth from Phase 7)
  - **Every alert carries a `runbook_url` annotation**, with one runbook per alert in `docs/runbooks/`
- **Acceptance criteria:**
  - [ ] A CI check fails if any alert lacks a `runbook_url` or its runbook file is missing
- **Depends on:** P5-09
- **Output:** `gitops/platform/monitoring/rules/`, `docs/runbooks/`

### P5-11: Kiali
- **Scope:** Kiali via Argo CD, using Prometheus; read-only; behind the gateway with SSO
- **Acceptance criteria:**
  - [ ] The service graph shows the payment path, with mTLS padlocks
- **Depends on:** P5-01
- **Output:** `gitops/platform/kiali/`

## P5-M5 Wrap-up

### P5-12: Phase 5 wrap-up
- **Scope:**
  - **Diagram #6, observability and correlation**
  - ADR-0008 "Prometheus + Loki + Tempo instead of ELK / Datadog" (referenced since the project brief)
  - Footprint and cost table; README GIF of the click path; retrospective
- **Acceptance criteria:**
  - [ ] All exit criteria ticked, with evidence
- **Output:** `docs/architecture/`, `docs/adr/`, `README.md`

---

## Cost of Phase 5

| Item | ~USD |
|---|---|
| Extra Spot capacity for the observability stack (~3–4 GB RAM) | ~+$0.03–0.05/hr |
| S3 for Loki/Tempo (7-day expiry) + gp3 PVC for Prometheus | < $1/month |
