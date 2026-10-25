# ADR-0002: Cost model: ephemeral clusters

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

This is a personal project paid for out of pocket. Every tool is open source, so the only spend is AWS infrastructure, which is billed **per hour**. A dev environment left running 24/7 in `ap-south-1` would cost roughly **$300+/month** (estimate; validate with Infracost once the Terraform exists):

| Item | ~USD/month (24/7) |
|---|---|
| EKS control plane | 73 |
| Interface VPC endpoints (ECR api, ECR dkr, STS × 3 AZs) | ~85 |
| NAT gateway | ~40 + data |
| Nodes (2 on-demand + ~2 Spot, x86) | 60–90 |
| NLB | ~18 |
| RDS db.t4g.micro + ElastiCache t4g.micro | ~25 |
| EBS, S3, Secrets Manager, Route 53 | ~10 |

The biggest cost driver is **hours running**, not tool choice.

## Options considered

1. **Always-on dev cluster.** Convenient, but too expensive for a personal budget.
2. **Run everything locally (kind) and never use AWS.** Free, but it can't demonstrate EKS, IAM, OIDC, Karpenter or the AWS networking this project exists to show.
3. **Ephemeral cloud plus local-first development.** Build and iterate locally; bring AWS up only when the cloud itself is being worked on or demoed.

Also considered and **rejected**: replacing the NAT gateway with a NAT instance (fck-nat). It would save about $37/month, but it adds a self-managed component, and the managed NAT gateway is the production-standard choice reviewers expect.

## Decision

Option 3, with these specifics:

- **Ephemeral environments:** `make up` at the start of a session and `make destroy` at the end. Everything, including RDS, is created and destroyed by Terraform, so nothing is left running by accident.
- **Safety nets:** a scheduled GitHub Actions workflow runs the destroy every night. AWS Budgets alert at **$10, $25 and $50**. [`tools/cost-reaper`](../../tools/cost-reaper/) (Python) runs after every destroy, because `terraform destroy` misses resources created by in-cluster controllers (NLBs, Karpenter nodes, EBS volumes).
- **Local-first:** Phase 1 and most of Phases 3, 5 and 6 are developed on Docker Compose and kind. CI runs on GitHub Actions, which is free for public repos.
- **Cheaper compute:** Graviton (arm64) instances everywhere (~20% cheaper than x86). Karpenter Spot NodePools for workloads. **One** on-demand managed node for platform add-ons.
- **Network:** one NAT gateway in dev. Only the **free S3 gateway endpoint** in dev; interface endpoints (ECR, STS) are a prod-only toggle.
- **Data:** single-AZ `db.t4g.micro` RDS and one `cache.t4g.micro` Redis node in dev. Multi-AZ and replicas only in prod.
- **Retention:** 3–7 days for metrics, logs and traces; S3 lifecycle rules on Loki, Tempo and Velero buckets.

## Consequences

- **Positive:** expected cost is about **$0.30–0.50 per hour** while up. At ~40 cloud hours a month, that's roughly **$15–25/month** instead of $300+.
- **Positive:** `make up` / `make destroy` gets exercised constantly, so "one-command bring-up and teardown" is proven, not just claimed.
- **Negative:** each session pays the bring-up time (EKS plus add-ons, roughly 15–25 minutes). Mitigation: keep the bootstrap fully automated, and batch cloud work into fewer, longer sessions.
- **Negative:** state is lost on destroy. RDS data is disposable seed data. Anything that must survive (Terraform state, Velero backups) lives in S3, outside the destroy scope.
- **Negative:** CI must build `linux/arm64` images. Containers must use multi-arch base images, and the build uses Buildx.
- **Negative:** Spot nodes can be interrupted. That's acceptable, and even useful: it shows PodDisruptionBudgets and Karpenter consolidation working.
- **Revisit if:** the project needs a long-running public demo URL. Options then are a scheduled up/down window or a smaller always-on footprint.
