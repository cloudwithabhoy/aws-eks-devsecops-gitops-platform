# wallet-service: local build and run. CI calls the same targets.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# -B: batch mode (no colour codes or download progress), as in CI
MVN := ./mvnw -B

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: test
test: ## Compile, run all tests and write the JaCoCo report (target/site/jacoco/)
	$(MVN) verify

.PHONY: run
run: ## Run the service locally on PORT (default 8080)
	$(MVN) spring-boot:run

.PHONY: clean
clean: ## Delete build output
	$(MVN) clean
