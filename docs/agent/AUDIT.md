# Initial engineering audit

Date: 2026-11-22
Baseline: main at c8f12f5e075bbc47ed78da17af1acaf87a1a3216
Scope: repository, Flutter client, Supabase functions and migrations, Android, CI, and release preparation

## Executive assessment

The repository is an advanced product implementation with substantial domain logic and test assets. It is not release-ready yet. The main blockers are unauthenticated internal Edge Function jobs, incomplete security hardening of older SQL functions, unavailable local execution of the full Flutter and Supabase stacks in the current cloud runtime, absence of an iOS target, and release signing that intentionally falls back to a public test key.

The latest repository history is active through merged PR #107. docs/tasks/NEXT_TASK.md predates major profile, friends, Guardian, trophy, and avatar work. It cannot be treated as the current highest-priority task without reconciling it with code and ADRs.

## Findings

### AUD-SEC-001 — internal Guardian jobs accepted unauthenticated requests

- Severity: critical
- Classification: confirmed vulnerability
- Evidence: .github/workflows/deploy.yml deploys all functions with --no-verify-jwt. guardian-tick, guardian-notify, and guardian-retry used the service-role database client without checking the caller. test-telegram sent a message on any GET.
- User impact: an external caller could trigger Guardian state processing, notification retries, pending notification dispatch, or test Telegram messages.
- Resolution: commit 072ed76185930c893e5a83ace8af68b58a9751a1 adds exact service-role bearer verification, negative unit tests, and removes the test endpoint from future deployments.
- Required verification: targeted unit test, full Deno suite, deployment in a non-production Supabase project, and 401 checks without or with an invalid token.

### AUD-SEC-002 — administrative forest import RPC is executable by default roles

- Severity: critical
- Classification: confirmed vulnerability in migration source, production deployment status unverified
- Evidence: supabase/migrations/20261021120100_import_forest_zones_batch.sql defines a public SECURITY DEFINER function without a fixed search_path, REVOKE, or role-specific GRANT.
- User impact: if present with default PostgreSQL privileges, API roles can invoke an administrative geodata import and alter forecast inputs.
- Recommendation: add a dedicated hardening migration with an empty search path, schema-qualified objects, revoke from PUBLIC, anon, and authenticated, grant only to service_role, and add a negative SQL privilege test.
- Required verification: fresh database migration run and direct has_function_privilege assertions for all API roles.

### AUD-SEC-003 — rate limiting fails open

- Severity: high
- Classification: confirmed implementation weakness
- Evidence: supabase/functions/_shared/rate-limit.ts returns allowed true when both the RPC and fallback write fail. Its fallback upsert writes count 1, so it does not reproduce the atomic increment contract.
- User impact: abuse protection can disappear during a database or migration failure.
- Recommendation: remove the non-atomic fallback and define endpoint-specific failure behavior. Mutating and notification endpoints should fail closed.
- Required verification: injected RPC failure tests and concurrent limit tests.

### AUD-SEC-004 — broad no-verify-jwt deployment policy

- Severity: high
- Classification: systemic risk
- Evidence: .github/workflows/deploy.yml passes --no-verify-jwt to all 38 Edge Function directories.
- User impact: every endpoint depends on correct in-handler authentication. A newly added function is public until its own guard is implemented.
- Recommendation: maintain a reviewed public-endpoint allowlist and enable platform JWT verification by default. Keep explicit in-handler service-role or webhook-secret validation where platform JWT alone is insufficient.
- Required verification: endpoint authorization matrix covering missing, malformed, anonymous, authenticated, service-role, and webhook-secret requests.

### AUD-BE-001 — legacy notification handler schema omits alert_id

- Severity: high
- Classification: confirmed code defect
- Evidence: guardian-notify/index.ts reads bodyParse.data.alert_id, but NotifySchema does not declare alert_id.
- User impact: the trigger payload cannot select its intended alert, so the handler falls back to scanning pending alerts. The file is outside the blocking strict type-check list.
- Recommendation: add alert_id to the schema and a regression test, then include all deployed function entrypoints in blocking type checking.

### AUD-MOB-001 — iOS target is absent

- Severity: high release blocker
- Classification: confirmed
- Evidence: flutter_client/ contains Android sources and no ios/ directory.
- User impact: no iOS build, permissions, OAuth callback, Firebase configuration, entitlements, or signing flow can be validated.
- Recommendation: generate and review the iOS target on a pinned Flutter version, then add macOS CI. Apple signing and device validation remain owner dependencies.

### AUD-AND-001 — release build falls back to a public test signing key

- Severity: high release blocker
- Classification: confirmed configuration
- Evidence: flutter_client/android/app/build.gradle.kts signs release builds with android/app/test-signing.jks when release secrets are absent. android.yml can publish that APK as the rolling prerelease.
- User impact: such APKs are suitable for testing and cannot represent a store-ready release identity.
- Recommendation: keep the current testing convenience, clearly label artifacts, and add a store-release job that fails unless all release signing inputs exist.

### AUD-FL-001 — auth screen has an unverified small-screen accessibility risk

- Severity: medium
- Classification: potential UI risk
- Evidence: auth_screen.dart uses a fixed Column with multiple spacers and no scrolling.
- User impact: small devices, landscape mode, or large system fonts may overflow primary sign-in actions and legal text.
- Recommendation: validate with widget and golden tests at large text scale and compact constraints before changing layout.

### AUD-QA-001 — blocking CI omits strict checks for deployed legacy functions

- Severity: high
- Classification: confirmed quality gap
- Evidence: test.yml runs blocking deno check for selected v1 and Guardian files. The all-function check is continue-on-error.
- User impact: type defects in deployed functions can merge while CI remains green.
- Recommendation: repair reported legacy errors in bounded groups and expand the blocking list until every deployed entrypoint is covered.

### AUD-QA-002 — local release baseline is incomplete in the current runtime

- Severity: high verification blocker
- Classification: environment limitation
- Evidence: Flutter bootstrapping is blocked by a 403 to storage.googleapis.com. Deno imports from deno.land and jsr.io are blocked. The Supabase PostgreSQL image previously exhausted the Docker daemon's storage while unpacking.
- User impact: Flutter analyze/test, Android build, complete Deno checks, migrations, and SQL/RLS tests have not been reproduced locally.
- Recommendation: run these commands in GitHub Actions or a cloud image with the required network destinations and Docker storage.

## Positive controls observed

- Supabase Anonymous Sign-In and server-driven onboarding are implemented.
- v1 endpoints use server-side JWT verification through auth.getUser.
- Pick creation uses signed upload URLs, validates file format and metadata, and separates draft and final paths.
- Public pick coordinates use a server-side display geometry while owners receive precise coordinates.
- Guardian in-app reads check ownership or accepted Guardian membership before returning route details.
- RLS is enabled throughout current schema migrations and 13 SQL security/regression scripts exist.
- The project contains 666 Deno test declarations, 305 Flutter test declarations, and 41 Flutter test files.

## Audit limits

GitHub branch rules, open PR state, and current CI conclusions could not be queried because the supplied GH_TOKEN is rejected and unauthenticated GitHub API traffic is blocked. Production Supabase state was not inspected or modified. UI rendering, device behavior, performance, and iOS behavior remain unverified.
