# Services

LedgerPay microservices, one directory per service. Each one follows the service contract in the [application design](../docs/application/README.md#what-every-service-must-provide): health, readiness and metrics endpoints, OpenTelemetry tracing, JSON logs, env-only config, graceful shutdown, tests, and a distroless arm64 image.

| Service | Language | Status |
|---|---|---|
| `wallet-service` | Java (Spring Boot) | Phase 1 (next) |
| `transfer-service` | Go | Phase 4 |
| `fraud-service` | Python (FastAPI) | Phase 4 |
| `bank-gateway-mock` | Node.js | Phase 4 |
| `notification-service` | Python | Phase 7 |
| `web-app` | Next.js | Phase 7 |

There is no auth service: customer identity is delegated to Auth0 ([ADR-0003](../docs/adr/0003-auth0-for-customer-identity.md)).
