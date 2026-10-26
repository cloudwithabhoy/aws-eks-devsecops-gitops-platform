# Build log

What was actually done for each task in the [implementation plan](../plan/README.md): how, why, what broke and how it was fixed. The plan records what was *intended*; this log records what *happened*.

One file per phase, one section per task, using the same task IDs as the plan (`P1-03` = Phase 1, task 03).

| Phase | Log |
|---|---|
| 1. Foundation, CI-first and wallet core | [phase-1.md](phase-1.md) |

**How this project is built:** the platform work (repo guardrails, CI/CD, infrastructure, Kubernetes, GitOps, security, observability) is mine. Application code in `services/` is written with an AI pair (Claude Code), because the app is only the vehicle for the platform; I review it and can explain every part of it.
