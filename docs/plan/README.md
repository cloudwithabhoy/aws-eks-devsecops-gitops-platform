# Implementation plan

> **ID key:** **P** = Phase, **M** = Milestone. `P1-M3` = Phase 1, Milestone 3 · `P1-06` = Phase 1, task 06. Task numbers run through the whole phase, so every ID is unique and searchable in commits, PRs and issues.

How LedgerPay goes from design to running platform: big phases, broken into milestones, broken into small tasks.

## Three levels

| Level | Example | Size | Lives in |
|---|---|---|---|
| **Phase** | Phase 1: Foundation, CI-first and wallet core | 1–3 weeks | [Roadmap](../../README.md#roadmap) |
| **Milestone** | P1-M3: CI v1 (no AWS) | A few days, ending in a visible outcome | `phase-N.md` |
| **Task** | P1-06: Reusable service CI workflow | **One PR**, about 2–4 hours | `phase-N.md` + one GitHub Issue |

## Rules

1. **Draft ahead, finalise just in time.** Every phase has a task-level plan, but only the current phase's plan is final. Later plans are marked **draft** and are reviewed and adjusted before their phase starts, because what we learn earlier changes them.
2. **One task = one PR = one Conventional Commit** (`feat:`, `ci:`, `infra:`, `docs:` …). The PR description says `Closes #<issue>`.
3. **Pipeline first.** From P1-M3 onward, every change goes through the DevSecOps CI, and `main` is protected by required checks.
4. **Local first, AWS only when needed.** Each task says where it runs. Anything that creates AWS resources needs explicit approval before `apply` ([ADR-0002](../adr/0002-cost-model-ephemeral-clusters.md)).
5. **A task is done when its acceptance criteria pass in CI**, not when the code is written.
6. **Every task gets a build-log entry** in [`docs/implementation/phase-N.md`](../implementation/), written right after the task, in the same PR. The plan says what was *intended*; the build log records what was *actually done*, why, and what broke. A task without its entry isn't done.

## Task template

```markdown
### P<phase>-<nn>: <title>
- **Why:** one line
- **Scope:** what is included
- **Out of scope:** what is deliberately left out
- **Acceptance criteria:**
  - [ ] testable check 1
  - [ ] testable check 2
- **Depends on:** P<phase>-<nn>
- **Runs on:** local | GitHub Actions | AWS (cost: …)
- **Output:** files / directories touched
```

## Build log template

One section per task in `docs/implementation/phase-N.md`, using the same task ID as the plan:

```markdown
## P<phase>-<nn>: <title>

**Date:** YYYY-MM-DD · **PR / commits:** #<n> / <sha>

### What I built
### How (key steps and commands)
### Why these choices (alternatives considered)
### Problems I hit and how I fixed them
### How I verified it
### Concepts I learned
### Questions this answers
<!-- FAQ style: "Q: Why freeze hook revs to a SHA?" followed by a short answer -->
```

## Status

| Phase | Plan | Status |
|---|---|---|
| 1 | [phase-1.md](phase-1.md) | Final, not started |
| 2 | [phase-2.md](phase-2.md) | Draft |
| 3 | [phase-3.md](phase-3.md) | Draft |
| 4 | [phase-4.md](phase-4.md) | Draft |
| 5 | [phase-5.md](phase-5.md) | Draft |
| 6 | [phase-6.md](phase-6.md) | Draft |
| 7 | [phase-7.md](phase-7.md) | Draft |

### Cross-phase moves made while planning

| Item | Moved | Reason |
|---|---|---|
| External Secrets Operator | Phase 6 → **3** | The first EKS deployment needs DB credentials; no secrets in Git from day one |
| AuthorizationPolicies | Phase 6 → **4** | The call allow-list belongs with the mesh rollout |
| Minimal Prometheus | Phase 5 → **4** | Canary analysis needs it |
| k6 | Phase 7 → **4** | Canary analysis and the demo need steady traffic |
| Kiali | Phase 4 → **5** | Its service graph needs the full Prometheus setup |
