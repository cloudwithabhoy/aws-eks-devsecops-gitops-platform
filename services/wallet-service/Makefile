# wallet-service: local build and run. CI calls the same targets.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# -B: batch mode (no colour codes or download progress), as in CI
MVN := ./mvnw -B

IMAGE     ?= wallet-service
TAG       ?= $(shell git rev-parse --short HEAD)
PLATFORMS ?= linux/amd64,linux/arm64
# Scanner images pinned by digest, like everything else
HADOLINT  := hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d
TRIVY     := aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: test
test: ## Compile, run all tests and write the JaCoCo report (target/site/jacoco/)
	$(MVN) verify

.PHONY: run
run: ## Run the service locally on PORT (default 8080)
	$(MVN) spring-boot:run

.PHONY: image
image: ## Build the image for this machine's architecture and load it into Docker
	docker buildx build --load -t $(IMAGE):$(TAG) .

.PHONY: image-multiarch
image-multiarch: ## Build for amd64 and arm64 (proves the multi-arch build; nothing is pushed)
	docker buildx build --platform $(PLATFORMS) -t $(IMAGE):$(TAG) .

.PHONY: run-image
run-image: ## Run the image hardened as in Kubernetes: read-only root, no capabilities, non-root
	docker run --rm --name $(IMAGE) -p 8080:8080 --read-only --tmpfs /tmp --cap-drop=ALL \
	  --security-opt no-new-privileges $(IMAGE):$(TAG)

.PHONY: lint-docker
lint-docker: ## Lint the Dockerfile with Hadolint
	docker run --rm -i $(HADOLINT) < Dockerfile

.PHONY: scan
# --ignore-unfixed: CVEs with no released fix can't be acted on; they're tracked in the build log
# and picked up automatically once a fixed base image digest lands (Renovate).
scan: ## Scan the image for CRITICAL/HIGH CVEs with Trivy (fails if any are found; first run downloads the DBs)
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache \
	  $(TRIVY) image --timeout 20m --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 $(IMAGE):$(TAG)

.PHONY: clean
clean: ## Delete build output
	$(MVN) clean
