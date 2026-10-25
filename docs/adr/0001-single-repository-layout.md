# ADR-0001: Single repository with enforced internal boundaries

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

LedgerPay is a solo portfolio project. It covers application services, Terraform/Terragrunt infrastructure, a Helm library chart, GitOps config for Argo CD, and CI/CD. The main readers are recruiters and hiring managers who will usually spend a few minutes on **one** repo.

In larger organisations, these concerns typically sit in separate repos, split by owner and release cadence:

- one repo per service
- reusable CI workflows ("golden pipeline")
- Terraform modules vs. Terragrunt live config
- a Helm chart repo
- a GitOps repo, which Argo CD recommends keeping separate from app code

## Options considered

1. **Polyrepo (about 13 repos)**, mirroring a large-org layout.
   - Pro: realistic ownership boundaries; per-repo permissions come for free.
   - Con: a reviewer won't open 13 repos, so most of the work goes unseen. Cross-repo wiring (bot tokens, version bumps, Renovate) adds cost with no benefit for one person.
2. **Four repos** (docs umbrella, services, infra, gitops).
   - Pro: keeps the key app-vs-config split.
   - Con: still scatters the story; the umbrella repo ends up holding only links.
3. **Single repo with boundaries enforced inside it.**
   - Pro: everything is discoverable from one README.
   - Con: weaker isolation, which has to be enforced deliberately.

## Decision

Option 3. One public repo, `aws-eks-devsecops-gitops-platform`, with these top-level boundaries:

| Directory | Would be its own repo in a larger org | How the boundary is enforced here |
|---|---|---|
| `services/<svc>/` | Per-service repos | Path-filtered CI; only that service builds |
| `.github/workflows/service-ci.yml` | Shared `ci-workflows` repo | One reusable workflow; services call it, so security gates can't be skipped per service |
| `infra/modules/` | Terraform modules repo | Released with prefixed tags (`modules/vpc/v1.2.0`) |
| `infra/live/` | Terragrunt live repo | Pins modules with `?ref=<tag>`, so infra changes are promoted dev → staging → prod |
| `charts/ledgerpay-lib/` | Helm charts repo | Versioned chart pushed to ECR as an OCI artifact |
| `gitops/` | GitOps repo | Argo CD watches only this path; CI writes only via PRs here |

Supporting controls:

- **IAM isolation:** each workflow assumes its own AWS role via GitHub OIDC. The trust policy is scoped by `job_workflow_ref` and the GitHub Environment, so service CI can push to ECR but can't run Terraform.
- **Ownership:** CODEOWNERS per directory, branch rules on `main`, required checks.
- **No CI loops:** the bot's image-bump PRs touch only `gitops/apps/`, which no service workflow watches.
- **Promotion:** the same image digest moves dev → staging → prod through reviewed PRs, using GitHub Environments with required reviewers. Images are never rebuilt per environment.

## Consequences

- **Positive:** one landing page for the whole platform. Atomic changes across code, chart and config are possible when needed. One Renovate config and one set of branch rules.
- **Negative:** app code and deployment config share a commit history and write access. That is exactly the separation Argo CD's docs recommend, so we accept the trade-off consciously, for a single maintainer.
- **Negative:** Git tags are shared across modules and the chart, so tag prefixes are mandatory.
- **When to revisit:** if more than one team contributes, split `gitops/` into its own repo first (permissions and audit trail), then `infra/`. The directory boundaries above are drawn so each split is a `git filter-repo` away rather than a redesign.
