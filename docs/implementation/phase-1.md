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

---

## P1-04: Hardened multi-arch Dockerfile

**Date:** 2026-10-27 · **Commits:** `5d8f8fe` `8c99642` `52a3aa6`

### What I built
- `services/wallet-service/Dockerfile`: two stages. A Temurin 21 JDK build stage and a **distroless `java21-debian13:nonroot`** runtime
- `.dockerignore` as an **allow-list** (`.mvn/`, `mvnw`, `pom.xml`, `src/` only)
- Service `Makefile` targets: `image`, `image-multiarch`, `run-image`, `lint-docker` (Hadolint), `scan` (Trivy)

### How
- `docker buildx build --load -t wallet-service:<sha> .` for the local image; `--platform linux/amd64,linux/arm64` for both architectures.
- Hadolint and Trivy run as pinned containers, so nothing extra is installed on the laptop and CI can run the same commands.
- Docker Desktop's containerd image store handles multi-arch builds without a separate builder.

### Why these choices
- **Build stage on `$BUILDPLATFORM`:** Java bytecode is the same on every CPU, so the jar is built once at native speed and copied into both the amd64 and arm64 runtimes. Building "for arm64" would run Maven under QEMU emulation, many times slower, for an identical jar. (Go or native code would need cross-compilation instead.)
- **Distroless runtime:** only the JRE and CA certificates. No shell, no package manager, so a much smaller attack surface and CVE count, and nothing to `exec` into. Debugging uses `kubectl debug` with an ephemeral container instead.
- **Numeric `USER 65532:65532`:** Kubernetes' `runAsNonRoot` can only verify a numeric UID; a user *name* fails admission.
- **Works with a read-only root filesystem:** the only writable path is `/tmp` (Tomcat's work directory), mounted as tmpfs locally and `emptyDir` in Kubernetes.
- **Exec-form `ENTRYPOINT`:** java is PID 1 and receives SIGTERM directly. Shell form would wrap it in `/bin/sh -c`, which doesn't forward signals (and distroless has no shell anyway).
- **Spring Boot layered jar:** dependencies, loader, snapshots and application code go in separate layers, ordered by how often they change, so a code change only rebuilds and pushes the small application layer.
- **Dependencies before source:** `mvnw` + `pom.xml` are copied and resolved before `src/`, so the dependency layer is cached across code changes; a BuildKit cache mount keeps `~/.m2` between builds.
- **No tests in the image build:** CI runs them in its own stage before building; running them twice slows every build.
- **`-XX:MaxRAMPercentage=75`:** sizes the heap from the container's memory limit. `ExitOnOutOfMemoryError` lets Kubernetes restart a broken JVM instead of leaving it half-alive.
- **Every image pinned by digest** (base images and scanner images): a tag can be moved; a digest is the exact image. Renovate updates digests via PRs from Phase 2.
- **No `HEALTHCHECK`:** Kubernetes ignores it and uses its own probes (`/healthz`, `/readyz`); distroless also has no curl to run one.

### Problems I hit and how I fixed them
- **The first Trivy scan failed the gate**, which is the gate working:
  - **3 CRITICAL CVEs in Tomcat 11.0.24 and 5 HIGH in Jackson 3.1.5**, both from Spring Boot 4.1.1. Spring Boot 4.1.2 ships Tomcat 11.0.27 and Jackson 3.1.7, so I upgraded, even though 4.1.2 was only 5 days old. The two-week rule exists to avoid fresh regressions; a **security patch release is the exception**.
  - **17 OS CVEs (1 CRITICAL) in `distroless/java21-debian12`**, whose packages lag. Before switching, I scanned `java21-debian13` on its own: only 4 HIGH, all in `libuuid1` with **no fix released**. Switched to debian13.
  - `make scan` uses `--ignore-unfixed`: a CVE with no fix can't be acted on. These 4 clear automatically when a fixed base-image digest lands.
- **Trivy timed out on its first run** (`context deadline exceeded`): it downloads its vulnerability DB plus a several-hundred-MB Java DB, then opens every jar. Fixed with `--timeout 20m` and a `trivy-cache` volume; later scans take about a minute. CI will cache the DB too.
- **`docker` not found in WSL:** Docker Desktop's WSL integration was off. Fix: *Settings → Resources → WSL integration → Ubuntu*. Until then, the Windows CLI works (`cmd.exe /c "docker …"`).
- **Exit code 143 after `docker stop` looked like a failure.** It isn't: 143 = 128 + 15 (SIGTERM). The JVM reports termination by signal even after a clean graceful shutdown.

### How I verified it
- Hadolint: no findings.
- `docker image ls --tree`: both `linux/amd64` and `linux/arm64`, about 83 MB compressed each. The build log shows the build stage ran **once**, on amd64.
- `docker run --read-only --tmpfs /tmp --cap-drop=ALL --security-opt no-new-privileges`: starts as `nonroot` with java as PID 1; `/healthz` and `/readyz` return UP; `/actuator/env` returns 404; `docker exec … sh` fails (no shell).
- `docker stop` → "Commencing graceful shutdown" → "Graceful shutdown complete" in 1.2 s, well inside Docker's 10 s grace. **This also closes P1-03's open SIGTERM criterion.**
- Trivy (`--severity CRITICAL,HIGH --ignore-unfixed --exit-code 1`): 0 findings, exit 0.
- `mvnw verify` re-run after the Spring Boot upgrade: tests pass.

### Concepts I learned
- `$BUILDPLATFORM` vs `$TARGETPLATFORM` in multi-platform builds.
- Image index (manifest list) vs per-platform manifests; digests of each.
- Exec vs shell form, PID 1 and signal handling; exit code 128 + N.
- Why distroless and numeric UIDs matter for Kubernetes security contexts.
- Fixable vs unfixed CVEs, and why scanners have `--ignore-unfixed`.

### Questions this answers
- **Q: How do you build an arm64 image on an x86 laptop or runner?** `buildx` with `--platform`. For JVM apps, run the build stage on `$BUILDPLATFORM` so only the runtime stage is per-architecture, with no emulation.
- **Q: Your image scan fails on a CVE in a dependency. What do you do?** Find which library and which upstream version fixes it; upgrade the parent (here Spring Boot) rather than overriding one library; rebuild and re-run *all* checks. If there's no fix, document it with a reason and an expiry, never silently ignore.
- **Q: Why distroless instead of Alpine?** No shell or package manager at all, and glibc (Alpine's musl can behave differently for the JVM). Fewer packages means fewer CVEs.
- **Q: Your container ignores SIGTERM and gets killed after 30 s. Why?** Usually shell-form `ENTRYPOINT` (`sh -c` doesn't forward signals) or the app not handling SIGTERM.
- **Q: Why pin images by digest if you also use tags?** The tag is for humans; the digest guarantees the exact bytes, so builds are reproducible and a re-pushed tag can't slip in.

---

## P1-05: Repo-wide checks workflow

**Date:** 2026-10-27 · **Commit:** see `git log --grep "Refs: P1-05"`

### What I built
`.github/workflows/repo-checks.yml`, the first CI workflow. It runs on every push to `main`, every pull request, and on demand, with two parallel jobs:
- **pre-commit (all files):** the same hooks as on the laptop, on every file in the repo
- **gitleaks (full history):** every commit on every branch scanned for secrets, with a job summary table

### How
- `pre-commit` job: checkout → Python 3.12 → restore `~/.cache/pre-commit` → `pip install pre-commit==4.6.2` → `pre-commit run --all-files --show-diff-on-failure`.
- `gitleaks` job: checkout with `fetch-depth: 0` → download the Gitleaks 8.30.1 release binary, **verify its SHA-256** → `gitleaks git --log-opts="--all" --redact` → JSON report → Markdown summary.
- Checked before pushing: actionlint (with shellcheck on the `run:` scripts) clean, all pre-commit hooks pass, and a local full-history Gitleaks scan finds nothing (18 commits).

### Why these choices
- **Why CI repeats the local hooks:** `git commit --no-verify` skips local hooks, and a fresh clone has none installed. Local hooks give fast feedback; CI is the enforcement.
- **`permissions: contents: read` at workflow level:** the `GITHUB_TOKEN` gets read-only access. If a step or action were compromised, it couldn't push code, change releases or open PRs.
- **Actions pinned by commit SHA** (`@3d3c42e… # v7.0.1`): a tag can be force-moved to new code (as in the 2025 `tj-actions/changed-files` compromise); a SHA can't. The comment keeps the version readable, and Renovate updates both.
- **Versions at least two weeks old:** `actions/setup-python` v7.0.0 rather than v7.1.0 (5 days old).
- **`persist-credentials: false`:** checkout otherwise leaves the token in `.git/config` for every later step to read. Neither job pushes, so neither needs it.
- **`concurrency` with `cancel-in-progress` only for PRs:** a new push to a PR cancels the now-pointless run on the old commit (saves minutes). Runs on `main` are never cancelled, so every commit on `main` has a recorded result.
- **Gitleaks as a verified binary, not `gitleaks-action`:** one less third-party action with access to the job; the checksum proves it's the official release; and it's the same version as the local hook.
- **Full history, all refs:** deleting a secret in a later commit doesn't remove it from Git. Anyone who clones can check out the old commit, so history must be clean too.
- **Gitleaks hook skipped inside the pre-commit job (`SKIP: gitleaks`):** the hook scans *staged* changes, which is always empty in CI, so it would pass while checking nothing. The dedicated job covers it properly.
- **`--redact`:** CI logs and summaries never print the secret itself; a leaked log would otherwise leak it again.
- **Pinned runner image (`ubuntu-24.04`, not `ubuntu-latest`)** and **`timeout-minutes`** on every job: no surprise OS upgrades, and a hung job can't burn the free minutes for 6 hours.
- **Cache key = hash of `.pre-commit-config.yaml`:** hook environments (including the compiled Gitleaks) are rebuilt only when the hooks change.

### Problems I hit and how I fixed them
- **The Gitleaks pre-commit hook would have passed vacuously in CI**, because it only looks at staged files. Caught while reading the hook's definition (`.pre-commit-hooks.yaml` in the Gitleaks repo); fixed with `SKIP` plus the separate history scan.
- **The first CI runs failed although every hook passed on my laptop.** `.gitattributes` checks `*.cmd` files out with CRLF (correct for Windows batch files), but the `mixed-line-ending --fix=lf` hook then "fixed" `mvnw.cmd` to LF and failed. My local copy predated the CRLF rule, so it only showed up on a **fresh clone**, which is exactly what CI uses. Reproduced by cloning the repo into a temp folder and running the hooks there; fixed by excluding `\.(bat|cmd|ps1)$` from that hook. Lesson: when CI and local disagree, reproduce on a clean checkout, not in the working copy.

### How I verified it
- [ ] Pushed to `main`: both jobs green *(to be confirmed after the first run)*
- [ ] Planted-secret PR: a branch with a fake AWS key committed with `--no-verify`; the `gitleaks` job fails and its summary names the rule and file; PR closed and branch deleted *(to be confirmed)*

### Concepts I learned
- `GITHUB_TOKEN` and the `permissions:` block; workflow-level vs job-level permissions.
- Why pinning by SHA matters for third-party actions.
- `concurrency` groups and `cancel-in-progress`.
- Shallow vs full clones (`fetch-depth`), and why secret scanning needs the full history.
- `$GITHUB_STEP_SUMMARY` for readable results on the run page.

### Questions this answers
- **Q: How do you stop a compromised GitHub Action from stealing secrets or pushing code?** Pin by SHA, minimise third-party actions, give the token read-only permissions, `persist-credentials: false`, and expose secrets only to the steps that need them.
- **Q: A developer committed a secret, then deleted it in the next commit. Is it safe?** No. It's still in history; a full-history scan finds it. Rotate the secret first, then rewrite history if needed.
- **Q: Why have both local hooks and CI checks?** Local is fast feedback and can be bypassed; CI is the gate that can't be (once branch protection requires it, P1-07).
- **Q: Your CI is slow and runs on outdated commits. What do you do?** Cache dependencies (here, hook environments) and use `concurrency` to cancel superseded PR runs.

---

## P1-06: Reusable service CI workflow (golden pipeline v1)

**Date:** 2026-10-29 · **Commit:** see `git log --grep "Refs: P1-06"`

### What I built
- `.github/workflows/service-ci.yml`: a **reusable** workflow (`workflow_call`) with inputs `service` and `language`, three jobs:
  - **test** (stage 1): `./mvnw verify` = compile + tests + **JaCoCo gate (≥ 70 % lines)**; coverage % in the job summary; reports uploaded
  - **source-scan** (stages 2–4): **Semgrep CE** (`p/default` + `p/java`), **Trivy fs** (dependencies in `pom.xml` + Dockerfile misconfig), **Hadolint**
  - **image** (stages 5–7, only if both pass): **multi-arch buildx** (amd64 + arm64) with GHA layer cache → load amd64 → **Trivy image** → **Syft SBOM** (SPDX JSON) as an artifact
- `.github/workflows/wallet-service.yml`: a **thin caller**, path-filtered to `services/wallet-service/**` and the two workflow files
- `services/wallet-service/.trivyignore`: empty, with the rule that every exception needs a reason and a review date
- `pom.xml`: JaCoCo `check` execution; the bootstrap class (`main` → `SpringApplication.run`) excluded from coverage

### Why these choices
- **One reusable pipeline, thin callers:** security gates live in one file. A new service gets every gate by adding a 10-line caller; no service can quietly drop a scan. The same pattern a platform team uses for many repos.
- **Gates in parallel, image last:** tests and source scans don't depend on each other, so they run side by side; the image is only built if both pass (no point scanning an image of code that fails tests). Keeps the run well under the 10-minute target.
- **All scans run, then fail together** (`continue-on-error` + a final check step): one run shows *every* problem instead of one at a time.
- **No QEMU:** the Dockerfile's build stage runs on `$BUILDPLATFORM`, and the per-architecture runtime stage only has `COPY`, so building arm64 on an amd64 runner executes nothing under emulation.
- **Two builds, one cache:** the multi-arch build proves both architectures build and fills the GHA cache; the second build (amd64, `load: true`) comes straight from cache so the scanners can read it. Only amd64 is scanned: both arches have the same jars and the same distroless packages.
- **Scanner containers pinned by digest** (Trivy, Semgrep, Hadolint, Syft) instead of third-party actions: fewer actions with access to the job, exact versions, same commands as the local `make` targets.
- **`--ignore-unfixed` + `.trivyignore` with reasons:** CVEs with no released fix can't be acted on; anything else needs a written, dated exception.
- **Trivy DB cached once per day:** the vulnerability + Java DBs are ~1 GB; caching per day keeps data fresh without downloading it on every run.
- **Coverage gate excludes only the bootstrap class:** it's one line of framework wiring with nothing to test; excluding it keeps the gate honest for real code.
- **Path filters on the caller:** a docs-only change or (from Phase 3) a bot PR to `gitops/` doesn't rebuild the service.
- **`language` input already exists**, failing clearly for anything but `java`: Go, Python and Node.js arrive in P4-01 without changing callers.

### Problems I hit and how I fixed them
- **Trivy fs got rate-limited by Maven Central** (`429 Too Many Requests … blocks all subsequent requests from this IP` for 30 minutes). To scan `pom.xml`, Trivy downloads every dependency POM itself; shared CI runner IPs hit the limit too. Fix: resolve dependencies with Maven first (`dependency:resolve`, using the `setup-java` Maven cache) and mount `~/.m2/repository` read-only into the Trivy container, so it never calls Central.
- **A vacuous coverage gate:** with only the bootstrap class (now excluded), there are zero measured lines, so the gate passes trivially today. It bites from P1-15 onward; the failure test below proves it works.

### How I verified it
Locally, before pushing:
- actionlint (with shellcheck) clean on all workflows; pre-commit hooks pass
- `./mvnw verify`: 3 tests pass, "All coverage checks have been met"
- Semgrep with the exact CI flags: 203 rules, 11 files, 0 findings
- Trivy fs with the local Maven repository: `pom.xml` 0 vulnerabilities, Dockerfile 0 misconfigurations
- Syft against the P1-04 image: SPDX 2.3, 71 packages

On GitHub *(to be confirmed)*:
- [ ] First run on `main` green; total time ___ min (target < 10)
- [ ] A docs-only commit doesn't start `wallet-service`
- [ ] Each gate fails once on a PR, then reverted: vulnerable dependency (Trivy), Dockerfile lint error (Hadolint), coverage below the gate (JaCoCo)

### Concepts I learned
- Reusable workflows (`workflow_call`), inputs, and how permissions are capped by the caller.
- `needs:` for job ordering; `continue-on-error` + `steps.<id>.outcome` to collect results.
- BuildKit `$BUILDPLATFORM`, GHA cache (`type=gha`, `mode=max`, `scope`).
- SCA (Trivy fs on manifests) vs image scanning (Trivy image on what actually ships) vs SAST (Semgrep on code).
- SBOMs (SPDX) and why they matter for incident response ("are we affected by CVE-X?").

### Questions this answers
- **Q: How do you make sure every team's pipeline runs the security scans?** A reusable workflow owned by the platform team; services call it and can't remove gates. Branch protection then requires its checks (P1-07).
- **Q: SAST, SCA, image scanning: what's the difference?** SAST reads your code for bugs (Semgrep); SCA checks declared dependencies (Trivy fs on `pom.xml`); image scanning checks what's really in the shipped image, OS packages included (Trivy image).
- **Q: Why scan both the source and the image?** Source scans fail fast, before a build; the image scan sees the base image's OS packages and the exact resolved jars.
- **Q: What is an SBOM for?** An inventory of every package in an image. When a new CVE drops, you search SBOMs to know within minutes which images are affected, without rebuilding anything.
- **Q: Your CI hits rate limits from a public registry. What do you do?** Cache dependencies, resolve once and reuse (here `~/.m2`), and in production use a pull-through cache or proxy (ECR pull-through, Nexus).
