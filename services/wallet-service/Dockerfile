# syntax=docker/dockerfile:1

# wallet-service image: built once per commit, signed, and promoted by digest.
# Base images are pinned by digest (tags can be moved); Renovate keeps them current.

# ---- Build stage -------------------------------------------------------------
# Runs on the build machine's own architecture ($BUILDPLATFORM): Java bytecode is
# platform-independent, so one native-speed build serves both amd64 and arm64
# runtimes instead of compiling under QEMU emulation.
FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jdk-noble@sha256:67cb2fe42ef924ac8e63d0a4896923d0a10ba242536f517222ffadd57e8d642e AS build
WORKDIR /build

# Wrapper and POM first, so the dependency layer is reused when only src/ changes
COPY mvnw pom.xml ./
COPY .mvn/ .mvn/
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -q dependency:go-offline

ADD src/ src/
# Tests run in CI's test stage, not inside the image build
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -q -DskipTests package \
 && cp target/*.jar application.jar \
 && java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# ---- Runtime stage -----------------------------------------------------------
# Distroless: JRE and CA certs only. No shell, no package manager, so far fewer
# CVEs and nothing for an attacker to `exec` into.
# Debian 13 (current stable): Trivy found 17 HIGH/CRITICAL OS CVEs in the debian12 variant, 4 (unfixed) here
FROM gcr.io/distroless/java21-debian13:nonroot@sha256:a2aeb5a7a714cfe928b31fdf67b2d23f503ea6b9612705af062de22e0c50ba77

LABEL org.opencontainers.image.title="wallet-service" \
      org.opencontainers.image.description="LedgerPay balances and double-entry ledger" \
      org.opencontainers.image.source="https://github.com/cloudwithabhoy/aws-eks-devsecops-gitops-platform" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /app

# Spring Boot layers, least to most frequently changed, so a code change only
# ships the small application layer
COPY --from=build /build/extracted/dependencies/ ./
COPY --from=build /build/extracted/spring-boot-loader/ ./
COPY --from=build /build/extracted/snapshot-dependencies/ ./
COPY --from=build /build/extracted/application/ ./

# Numeric UID (distroless "nonroot"), so Kubernetes runAsNonRoot can verify it
USER 65532:65532

# Size the heap from the container's memory limit, not the node's RAM.
# java.io.tmpdir is /tmp: the only path that must be writable (mounted as tmpfs/emptyDir)
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"

EXPOSE 8080

# Exec form: java is PID 1 and receives SIGTERM directly, which triggers
# Spring's graceful shutdown. No HEALTHCHECK: Kubernetes probes /healthz and /readyz.
ENTRYPOINT ["/usr/bin/java", "-jar", "application.jar"]
