# Runbook: GitHub repository settings

**Repo:** `cloudwithabhoy/aws-eks-devsecops-gitops-platform` · **Owner:** repo admin · **Introduced in:** P1-07

GitHub settings live outside Git, so this page is their source of truth. Change a setting → update this page in the same PR. If the UI and this page disagree, the UI is wrong.

## 1. General (Settings → General)

| Setting | Value | Why |
|---|---|---|
| Wikis, Issues, Discussions, Projects | Off | Docs live in `docs/`, work in `docs/plan/`. One place to look, nothing to moderate |
| Allow merge commits | Off | Merge commits break linear history |
| Allow rebase merging | Off | Would put every WIP commit on `main` |
| Allow squash merging | **On, the only method** | One task = one PR = one commit on `main` |
| Squash default commit message | **Pull request title and description** | The PR title becomes the commit subject, so it must be a Conventional Commit; the `Refs: P1-xx` footer goes in the description |
| Automatically delete head branches | On | No stale branches after merge |
| Interaction limits (Moderation) | Prior contributors / collaborators only | Public repo, solo project: no drive-by issues or PRs |

## 2. Ruleset `protect-main` (Settings → Rules → Rulesets)

| Field | Value |
|---|---|
| Enforcement | Active |
| Target | **Include default branch** (`~DEFAULT_BRANCH`) |
| Bypass list | **Empty**, not even the admin |

| Rule | Setting | Why |
|---|---|---|
| Restrict deletions | On | `main` can't be deleted |
| Block force pushes | On | History on `main` is the audit log; it's never rewritten |
| Require linear history | On | Easy to read, bisect and revert; matches squash-only |
| Require a pull request | 0 approvals, no code-owner review, merge method **squash** | Solo project: GitHub won't let you approve your own PR, so the required checks are the gate. In a team: 1–2 approvals + CODEOWNERS review |
| Require status checks | See the list below, **branches must be up to date** | Every change is tested against the latest `main`, so two green PRs can't combine into a red `main` |

### Required status checks

| Check | Workflow | Runs on |
|---|---|---|
| `pre-commit (all files)` | `repo-checks.yml` | Every PR |
| `gitleaks (full history)` | `repo-checks.yml` | Every PR |
| `wallet-service result` | `wallet-service.yml` | Every PR (pipeline skipped if wallet-service didn't change) |

**Adding a service:** its caller workflow gets the same `changes` → `ci` → `result` jobs, and `<svc> result` is added here and in the ruleset in the same PR. Always pick the check **from the dropdown** (source: GitHub Actions); a typed name that no job reports blocks every PR.

## 3. Why the `result` job exists (path filters vs required checks)

A required check must report on **every** PR. A workflow filtered with `on.pull_request.paths` doesn't start at all when its paths don't change, so its check never reports and the PR waits forever ("Expected — Waiting for status").

GitHub counts a job **skipped by `if:`** as passing, but a workflow that **never started** as missing. So each service caller:

1. always starts on `pull_request` (no `paths:`);
2. `changes` lists the PR's files (`gh pr diff --name-only`) and outputs `run=true|false`;
3. `ci` (the golden pipeline) runs only `if: run == 'true'`;
4. `result` runs `if: always()` and fails only if `changes` didn't succeed or `ci` failed or was cancelled. This is the one required check.

Pushes to `main` keep a trigger-level `paths:` filter: rulesets don't gate pushes, so there's nothing to wait for.

## 4. Local guard

The `no-commit-to-branch` pre-commit hook refuses commits on `main` locally, so the mistake is caught before a push is rejected. CI skips it (`SKIP` in `repo-checks.yml`) because pushes to `main` run with `main` checked out.

## 5. Verify the protection

```bash
# Expect: GH013 "Changes must be made through a pull request" (use a throwaway local commit, then reset)
git commit --allow-empty -m "test: direct push should be rejected" --no-verify && git push
git reset --hard origin/main

# Which rules apply to main? An empty list means the ruleset targets nothing
curl -s https://api.github.com/repos/cloudwithabhoy/aws-eks-devsecops-gitops-platform/rules/branches/main
```

## 6. Break-glass

Only when CI itself is broken (e.g. GitHub Actions outage, a bad required-check name) and a fix can't go through a PR:

1. Ruleset `protect-main` → Enforcement **Disabled**. Never delete it, never add a bypass actor.
2. Make the minimum fix.
3. Set Enforcement back to **Active** immediately and run the checks in section 5.
4. Record what happened and why in the current phase's build log.
