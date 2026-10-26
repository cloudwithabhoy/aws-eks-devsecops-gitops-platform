# Phase 1 build log

Plan: [phase-1.md](../plan/phase-1.md)

---

## P1-01: Repo hygiene and first push

**Date:** 2026-10-25 / 26 · **Commits:** `31a9a76` `dcf16b7` `1fcd87d` `3637df8` `1c806b2` `5226f66` `2784914`

### What I built
- `.gitattributes` (LF everywhere), `.editorconfig`, `.gitignore`
- `LICENSE` (MIT), `.github/CODEOWNERS`, `.github/pull_request_template.md`
- All design docs (architecture, ADRs, application design, plan) committed and pushed to a public GitHub repo

### How
- Connected the remote, committed in small logical groups, pushed `main`.
- Commits are made from IntelliJ on Windows; tooling (`make`) runs in WSL.

### Why these choices
- **`* text=auto eol=lf`**: the repo is edited on Windows but built on Linux (CI runners, containers). CRLF breaks shell scripts (`bash\r: not found`), Makefiles and some YAML tooling. `.gitattributes` enforces LF in the repo itself, so it works regardless of each machine's `core.autocrlf`.
- **`*.drawio.svg merge=binary`**: draw.io stores the whole diagram on one line, so a text merge would corrupt it.
- **No `CONTRIBUTING.md`:** this is a solo portfolio project and doesn't accept contributions; the README says so. Issues, Discussions and Wiki are off.
- **CODEOWNERS kept, but code-owner review won't be required** (P1-07): GitHub doesn't let you approve your own PR, so requiring it would lock me out. The path groups still show how ownership would be split in a team.
- **MIT licence:** others may read and reuse the code with credit; it doesn't invite contributions.

### Problems I hit and how I fixed them
- **Files silently left out of commits.** IntelliJ's default *changelist* mode commits only ticked files and ignores git's staging area, so `README.md`, `LICENSE` and `Makefile` stayed staged but uncommitted, and GitHub had no README. Fix: *Settings → Version Control → Git → Enable staging area*, so the IDE commits exactly what `git status` shows. Lesson: always check `git status` / the Git log after committing.
- **Malformed commit messages.** Several pushed messages had stray text ("+ blank line"), a body merged into the subject, a missing type, and no `Refs:` footer. I first left them, to avoid rewriting public history. After P1-03 added more of them, I rewrote all 13 once: each commit was recreated with the same tree, author and dates but a corrected message (`git commit-tree`), checked with `git diff old new` (only the intended `mvnw` mode change), kept a backup branch, and pushed with `--force-with-lease`. This was acceptable only because the repo was two days old with no other clones, and before branch protection (P1-07) makes force-pushes impossible. From now on I check the message preview before every push.

### How I verified it
- `git ls-files --eol | grep -v "i/lf\|i/-text\|i/none"` prints nothing (empty `.gitkeep` files show as `i/none`, which is fine).
- On GitHub: README, both diagrams and the Mermaid charts render; `CLAUDE.md` and `.idea/` are not in the repo.

### Concepts I learned
- `.gitattributes` vs `core.autocrlf`: the first is committed and applies to everyone; the second is per-machine.
- `i/` vs `w/` in `git ls-files --eol`: line endings in the index vs the working tree.
- IntelliJ changelists vs the git staging area.

### Questions this answers
- **Q: Why `.gitattributes` instead of telling everyone to set `core.autocrlf`?** It's in the repo, so it can't be forgotten on a new machine or CI runner.
- **Q: When is it OK to rewrite pushed history?** Almost never on a shared branch: a force-push breaks everyone else's clones. I did it once, on a two-day-old solo repo before branch protection, with a backup branch and `--force-with-lease` (which refuses to overwrite remote commits you haven't seen). Once `main` is protected (P1-07), force-pushes are blocked.
- **Q: Why have CODEOWNERS on a solo repo?** It documents ownership boundaries (ADR-0001: one repo, team-style boundaries) and auto-requests reviews if the repo ever gains collaborators.

---

## P1-02: pre-commit and Makefile skeleton

**Date:** 2026-10-25 / 26 · **Commits:** `bf43afd` `3868d48`

### What I built
- `.pre-commit-config.yaml`: whitespace, end-of-file, line-ending, YAML/JSON, large-file, merge-conflict, case-conflict and private-key checks, plus **Gitleaks** for secrets
- Root `Makefile` with `help`, `bootstrap-dev` (installs the hooks) and `lint` (runs every hook on every file)

### How
- pre-commit installed with **pipx** on both Windows and WSL; hooks installed with `pre-commit install --install-hooks`.
- `make lint` (WSL) / `pre-commit run --all-files` (PowerShell) on the whole repo.

### Why these choices
- **Hook revs frozen to commit SHAs** (`rev: <sha>  # frozen: v6.0.0`), not tags. A tag can be moved to point at different code; a SHA can't. Hook code runs on my machine with my credentials, so it's a supply-chain risk like any GitHub Action. `pre-commit autoupdate --freeze` (later Renovate) keeps them current.
- **Hooks chosen explicitly.** A hook repo is a menu, not a package. I skipped e.g. `pretty-format-json` (it would rewrite exported Grafana dashboards) and language-specific hooks that arrive with each service.
- **`check-yaml --allow-multiple-documents`**, with Helm `templates/` excluded: Kubernetes files often hold several documents, and Helm templates aren't valid YAML until rendered (`helm lint` covers them in Phase 3).
- **`no-commit-to-branch` defined but set to `manual`** until branch protection lands in P1-07.
- **Make as the single entry point.** Short, discoverable commands (`make help`); later `make up` / `make destroy` encode multi-step workflows in the right order; laptop and CI run the same targets. Alternatives were shell scripts (not self-listing) and `just`/Taskfile (extra install).
- **Local hooks are fast feedback, not enforcement.** They can be skipped with `--no-verify`, so CI runs the same checks (P1-05).

### Problems I hit and how I fixed them
- **`pip install pre-commit` refused** with *externally-managed-environment* (PEP 668: the distro protects its system Python). Fix: `pipx`, which gives each CLI tool its own virtualenv.
- **The first run took ~20 minutes.** pre-commit's Gitleaks hook builds Gitleaks from Go source, so it first downloaded a Go toolchain. Everything is cached in `~/.cache/pre-commit` afterwards; later runs take ~6 seconds.
- **`end-of-file-fixer` reported Failed** on the two `.drawio.svg` files: they had no final newline. A hook that modifies files fails on purpose so the change gets reviewed; restage and re-run.
- **Hooks depend on the environment running git.** Commits come from IntelliJ (Windows git) but tools live in WSL. The hook script points at the Python that installed it and falls back to `pre-commit` on PATH, so I installed pre-commit on **both** sides. A hook generated on Windows starts with `#!/bin/sh` and won't run under WSL's `dash`; re-running `make bootstrap-dev` in WSL produces one that works from both.
- **`make` doesn't exist in PowerShell.** Make targets run in a WSL terminal tab; `pre-commit install` is the PowerShell equivalent of `make bootstrap-dev`.
- **Testing with AWS's documentation key proved nothing:** Gitleaks deliberately ignores keys ending in `EXAMPLE`. I tested with a realistic fake key instead.

### How I verified it
- `make lint` / `pre-commit run --all-files`: every hook Passed or Skipped.
- Staged a file containing a fake `aws_access_key_id` and committed **from IntelliJ** (the path I actually use): the commit was blocked with `RuleID: aws-access-token` ("Detect hardcoded secrets…Failed"). The file was never committed.

### Concepts I learned
- pre-commit (the framework) vs `pre-commit/pre-commit-hooks` (one hook collection) vs any repo with a `.pre-commit-hooks.yaml`.
- `rev`: the exact version of a hook repo; tags vs SHAs.
- Make: targets are files by default; `.PHONY` marks commands; recipes need tabs; `$$` escapes `$`; `.SHELLFLAGS := -eu -o pipefail -c` for strict mode.
- `pre-commit install` is once per clone, because `.git/hooks/` isn't pushed.

### Questions this answers
- **Q: Hooks can be bypassed with `--no-verify`, so why have them?** They catch mistakes in seconds, before a secret ever leaves the laptop. CI is the real gate and runs the same checks.
- **Q: What does `.PHONY` do?** It tells Make a target is a command, not a file. Without it, a stray file called `lint` makes `make lint` print "up to date" and run nothing: a green check that checked nothing.
- **Q: Why pin hooks by SHA?** A tag can be moved; a SHA is the code itself. Same reasoning as pinning GitHub Actions by SHA.
- **Q: A secret was committed and pushed. What now?** Rotate it first (assume it's compromised the moment it's public), then remove it from history. Deleting it in a new commit doesn't remove it from history.

---

## P1-03: wallet-service skeleton

**Date:** 2026-10-26 · **Commits:** `438e6d0` `24dbeef` `13a4a7e` `dd32616`

### What I built
- `services/wallet-service`: Spring Boot 4.1.1 on **Java 21**, Maven Wrapper (Maven 3.10.0), Spring Web + Actuator only
- `/healthz` (liveness) and `/readyz` (readiness) on the main port; only the `health` actuator endpoint exposed
- Config from environment variables (`PORT`, `SHUTDOWN_TIMEOUT`); graceful shutdown
- `HealthEndpointsTest`: starts the real server on a random port and calls the probes over HTTP; checks that `/actuator/env` and `/actuator/beans` return 404
- JaCoCo coverage report on `verify`; service `Makefile` with `test`, `run` and `clean`

### How
- Generated with Spring Initializr, then trimmed (empty POM metadata, `HELP.md`, the default context-load test).
- Built from PowerShell with `.\mvnw.cmd -s $HOME\.m2\settings-personal.xml -B verify` (see problems below).

### Why these choices
- **Java 21, not 25.** 21 is the most widely deployed LTS, has virtual threads, has a distroless runtime image (`java21-debian12`) and was already installed. Nothing in this service needs 25; moving up is a one-line change.
- **Spring Boot 4.1.1, not 4.1.2:** 4.1.2 was only days old. The project rule is versions at least two weeks old, so early regressions are found by others first.
- **Maven Wrapper:** laptop and CI use exactly the same Maven version with nothing to install. `distributionType=only-script`, so no wrapper jar in Git.
- **Liveness vs readiness.** Liveness failing means "restart me", so it checks only the process. Readiness failing means "stop sending me traffic", so dependencies (the database, from P1-15) go there. A DB check in liveness turns a DB outage into a restart storm across every pod.
- **Probes on the main port via health groups** (`additional-path: "server:/healthz"`), so Kubernetes probes and the app share one port and one path convention across all services.
- **Expose only `health`:** `env`, `beans` and `heapdump` leak configuration and internals. A test enforces it.
- **Shutdown timeout 20 s**, below Kubernetes' default `terminationGracePeriodSeconds` of 30 s; otherwise the kubelet SIGKILLs the JVM mid-request.
- **No per-environment profile files:** dev, staging and prod differ only in injected environment variables (12-factor config).
- **No fake unit test:** there's no logic yet. Real unit tests arrive with the ledger (P1-16).

### Problems I hit and how I fixed them
- **Maven couldn't download anything:** `No such host is known (rmb-rbvprnxs01…)`. A global `~/.m2/settings.xml` left over from a corporate project mirrors **everything** (`<mirrorOf>*</mirrorOf>`) to a company Nexus that's unreachable outside that network. I didn't delete it (still needed for that work). Fix: a minimal `settings-personal.xml` passed with `-s`, and IntelliJ's per-project *User settings file → Override*. CI and WSL are unaffected because they have no global settings.
- **JDK mismatch:** the project first targeted Java 25, but only JDK 17 and 21 were installed. I switched to 21 (see above) instead of installing another JDK.
- **`mvnw` committed without the executable bit** (`100644`). Windows has no Unix file modes and the repo has `core.filemode=false`, so Linux CI would fail with `./mvnw: Permission denied`. Fix: `git update-index --chmod=+x services/wallet-service/mvnw` (expect `100755` in `git ls-files -s`); I folded it into the scaffold commit during the history rewrite (see P1-01).
- **Spring Boot 4 renamed starters** (`spring-boot-starter-web` → `spring-boot-starter-webmvc`, plus per-module test starters). Generating the project instead of copying from older tutorials avoided this.

### How I verified it
- `mvnw verify`: BUILD SUCCESS, 3 tests passed, `target/site/jacoco/index.html` generated.
- Ran the jar with `PORT=9090`: started on 9090; `/healthz` and `/readyz` → `{"status":"UP"}`; `/actuator/env` → 404.
- **Not yet verified:** graceful shutdown on SIGTERM. Windows can't send SIGTERM to a JVM; this is checked in P1-04 with `docker stop`, which sends SIGTERM to the container.

### Concepts I learned
- Actuator health groups and probe paths; liveness vs readiness vs startup probes.
- Graceful shutdown and how it relates to `terminationGracePeriodSeconds`.
- Maven mirrors and `settings.xml` precedence; the `-s` flag.
- Git stores an executable bit per file (`100755` vs `100644`), and Windows can't set it.

### Questions this answers
- **Q: What's the difference between liveness and readiness probes?** Liveness → restart; readiness → remove from Service endpoints. Never put dependencies in liveness.
- **Q: How does a Spring Boot app shut down cleanly in Kubernetes?** SIGTERM → stop accepting requests, finish in-flight ones within `timeout-per-shutdown-phase`, exit, all before the grace period ends.
- **Q: Why Java 21 rather than the newest LTS?** It's mainstream and supported, nothing needed 25, and upgrading later is trivial. Choose by need, not novelty.
- **Q: Builds fail on your laptop but nowhere else, with a host you've never heard of. Where do you look?** `~/.m2/settings.xml` mirrors, proxy settings, and environment variables like `MAVEN_OPTS`.
