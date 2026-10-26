# LedgerPay platform: entry point for every local and cloud workflow.
# Targets are added phase by phase (up/destroy in Phase 2, demo in Phase 4).

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

PRE_COMMIT ?= pre-commit

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: bootstrap-dev
bootstrap-dev: ## Install the git hooks (needs pre-commit: `pipx install pre-commit`)
	@command -v $(PRE_COMMIT) >/dev/null || { echo "pre-commit not found. Install it with: pipx install pre-commit"; exit 1; }
	$(PRE_COMMIT) install --install-hooks

.PHONY: lint
lint: ## Run every pre-commit hook against all files
	$(PRE_COMMIT) run --all-files
