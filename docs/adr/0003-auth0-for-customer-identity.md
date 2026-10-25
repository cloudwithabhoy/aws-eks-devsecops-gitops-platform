# ADR-0003: Auth0 for customer identity

- **Status:** Accepted
- **Date:** 2026-10-14

## Context

LedgerPay needs customer sign-up, login and token issuance, and the platform needs JWTs it can validate at the Istio gateway. The original design had a home-grown `auth-service` (Go + Postgres) that hashed passwords and issued JWTs.

In industry, teams rarely build authentication themselves. It is security-critical, full of edge cases (password reset, email verification, MFA, brute-force protection, key rotation), and it isn't the product. They use a dedicated identity provider instead.

The project's rule is open-source and free tools only, so adopting any SaaS needs a deliberate exception.

## Options considered

1. **Home-grown `auth-service`.** Free and self-contained, but it's the anti-pattern reviewers look for ("rolled their own auth"). We'd also own password storage and key rotation.
2. **Keycloak (self-hosted, open source).** An industry-standard IdP that fits the open-source rule. But it's a heavy JVM workload (~1 GB RAM plus its own database) running on an ephemeral cluster, so it gets torn down and rebuilt every session and adds cost (see ADR-0002).
3. **Okta Workforce Identity.** Built for *employees* signing into company tools, so it's the wrong category for wallet customers.
4. **Auth0.** Built for *customers* (CIAM). Standard OIDC/OAuth 2.0, a free plan, SDKs for Next.js, Java and Go, and an official Terraform provider.

## Decision

Option 4: **Auth0 is the customer identity provider from day one.** There is no `auth-service`.

- Browser login uses Universal Login with Authorization Code + PKCE, through the Auth0 Next.js SDK.
- APIs accept Auth0 access tokens (RS256) for the LedgerPay API audience. They're validated at the Istio gateway (`RequestAuthentication` + `AuthorizationPolicy`) **and** in each service, for defense in depth and so local development works without Istio.
- Services identify users by the token's `sub` claim and never see passwords.
- Service-to-service calls use Istio mTLS identities, not Auth0 tokens, so internal traffic doesn't depend on Auth0.
- The tenant (API, application, connections, MFA policy, branding) is code, via the Auth0 Terraform provider under `infra/`. Its management credentials live in AWS Secrets Manager and CI reads them through its OIDC role.
- Auth0 is the **only** SaaS exception to the open-source rule. It uses the free plan, so the cost is $0.

## Consequences

- **Positive:** industry-standard setup. We get sign-up, password reset, email verification, MFA and brute-force protection without writing them, and we never store passwords. Clear interview story: Auth0 for customer identity, Okta for workforce identity.
- **Positive:** the JWT/JWKS contract is standard OIDC. Switching to Keycloak or Cognito later only changes the issuer and JWKS URLs in Istio and the services, plus the web-app login SDK.
- **Negative:** an external dependency. Login and JWKS fetches need internet access (cluster egress to Auth0 must be allowed, and local development needs connectivity). JWKS responses are cached, so a short Auth0 outage doesn't break already-issued tokens.
- **Negative:** free-plan limits (monthly active users, features such as custom domains) apply. They're far beyond a portfolio's needs, but check them before relying on paid-only features.
- **Negative:** one long-lived credential (the Terraform provider's client secret) has to exist. We keep it in Secrets Manager, never in GitHub, and rotate it if exposed.
- **Changes from the earlier design:** `auth-service` is removed (6 services instead of 7). The `wallet` database stores `user_sub` and `email` from the token. Phase 1 is now "Auth0 tenant as code + `wallet-service`".
