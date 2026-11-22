# Initial engineering audit

Date: 2026-11-22 (Codex, first pass); updated 2026-11-22 by Claude (second pass, verified baseline)
Baseline: main at c8f12f5e075bbc47ed78da17af1acaf87a1a3216; second pass at 50f93ec (after PR #108)

> The repository is public. Findings describe affected components and fixes, not exploitation
> steps. Open critical items are fixed only after their PR is merged and deployed.
Scope: repository, Flutter client, Supabase functions and migrations, Android, CI, and release preparation

## Executive assessment

The repository is an advanced product implementation with substantial domain logic and test assets. It is
not release-ready yet. The initially confirmed P0 source vulnerabilities have fixes merged through PR #114;
remaining blockers include deployed verification without staging, absent iOS infrastructure, product/legal
release decisions and Android store-signing credentials. Test APKs must remain visibly separate from store
artifacts.

The latest repository history is active through merged PR #107. docs/tasks/NEXT_TASK.md predates major profile, friends, Guardian, trophy, and avatar work. It cannot be treated as the current highest-priority task without reconciling it with code and ADRs.

## Findings

### AUD-SEC-001 — internal Guardian jobs accepted unauthenticated requests

- Severity: critical
- Classification: confirmed vulnerability
- Evidence: .github/workflows/deploy.yml deploys all functions with --no-verify-jwt. guardian-tick, guardian-notify, and guardian-retry used the service-role database client without checking the caller. test-telegram sent a message on any GET.
- User impact: an external caller could trigger Guardian state processing, notification retries, pending notification dispatch, or test Telegram messages.
- Resolution: commit 072ed76185930c893e5a83ace8af68b58a9751a1 adds exact service-role bearer verification, negative unit tests, and removes the test endpoint from future deployments.
- Status: merged in PR #108 (2026-11-22). Staging 401 checks still pending (no staging project).
- Required verification: targeted unit test, full Deno suite, deployment in a non-production Supabase project, and 401 checks without or with an invalid token.

### AUD-SEC-002 — administrative forest import RPC is executable by default roles

- Severity: critical
- Classification: confirmed vulnerability in migration source, production deployment status unverified
- Evidence: supabase/migrations/20261021120100_import_forest_zones_batch.sql defines a public SECURITY DEFINER function without a fixed search_path, REVOKE, or role-specific GRANT.
- User impact: if present with default PostgreSQL privileges, API roles can invoke an administrative geodata import and alter forecast inputs.
- Recommendation: add a dedicated hardening migration with an empty search path, schema-qualified objects, revoke from PUBLIC, anon, and authenticated, grant only to service_role, and add a negative SQL privilege test.
- Required verification: fresh database migration run and direct has_function_privilege assertions for all API roles.
- Second pass (verified on a fresh database with all 61 migrations, scripts/dev/local-db): confirmed. The
  cause is broader: migration 20260911000006 revoked only schema-level default privileges, while the global
  PUBLIC EXECUTE default remained, so every SECURITY DEFINER function created without an explicit
  REVOKE FROM PUBLIC is executable by anon and authenticated. Eight functions were affected: the forest
  import, four PostGIS lookups (which also bypass Edge Function rate limits), and three trigger functions.
  All server callers use service_role.
- Status: fixed in PR #109 (migration 20261122100000 + regression test security_definer_privileges.sql,
  which fails CI for any future SECURITY DEFINER function reachable by API roles or lacking search_path).

### AUD-SEC-003 — rate limiting fails open

- Severity: high
- Classification: confirmed implementation weakness
- Evidence: supabase/functions/_shared/rate-limit.ts returns allowed true when both the RPC and fallback write fail. Its fallback upsert writes count 1, so it does not reproduce the atomic increment contract.
- User impact: abuse protection can disappear during a database or migration failure.
- Recommendation: remove the non-atomic fallback and define endpoint-specific failure behavior. Mutating and notification endpoints should fail closed.
- Required verification: injected RPC failure tests and concurrent limit tests.
- Current state: fixed in merged PR #112; seven regression tests cover RPC failures, invalid results,
  PostgREST response shape, 429 and retryable 503 behavior. Staging verification remains blocked.

### AUD-SEC-004 — broad no-verify-jwt deployment policy

- Severity: high
- Classification: systemic risk
- Evidence: before SEC-005/SEC-004, .github/workflows/deploy.yml passed --no-verify-jwt to every Edge
  Function directory. The current source has 17 deployed function directories.
- User impact: every endpoint depends on correct in-handler authentication. A newly added function is public until its own guard is implemented.
- Recommendation: maintain a reviewed public-endpoint allowlist and enable platform JWT verification by default. Keep explicit in-handler service-role or webhook-secret validation where platform JWT alone is insufficient.
- Required verification: endpoint authorization matrix covering missing, malformed, anonymous, authenticated, service-role, and webhook-secret requests.
- Current state: fixed in merged PR #113. The deploy workflow now
  reads a fail-closed 17-function matrix; only seven reviewed public/mixed/webhook functions bypass gateway
  JWT verification. CI rejects missing classifications and config drift. Deployed smoke tests are still
  pending because no staging Supabase project is available.

### AUD-BE-001 — legacy notification handler schema omits alert_id

- Severity: high
- Classification: confirmed code defect
- Evidence: guardian-notify/index.ts reads bodyParse.data.alert_id, but NotifySchema does not declare alert_id.
- User impact: the trigger payload cannot select its intended alert, so the handler falls back to scanning pending alerts. The file is outside the blocking strict type-check list.
- Recommendation: add alert_id to the schema and a regression test, then include all deployed function entrypoints in blocking type checking.
- Second pass: guardian-notify belongs to the legacy Guardian v0 pipeline that ADR-022 replaced (see
  AUD-SEC-005). Retiring the pipeline removes this defect; fixing it in place is not worth it.

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
- Current state: fixed on branch `codex/and-001-store-release-signing` at `2184704`. The normal workflow
  always produces an explicitly named test APK and never receives store secrets. A separate manual workflow
  produces an AAB only after all four signing secrets are present; Gradle fails closed when real signing is
  required or partially configured. PR CI and one owner-authorized store build with the real key are pending.

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
- Second pass: `deno check supabase/functions/*/index.ts` reports 33 errors: 25 in guardian-demo-create
  (duplicate imports), 7 in the legacy Guardian notification modules (_shared/guardian/notifications/queue.ts,
  templates.ts) plus guardian-notify, 2 in the legacy forecast function. All belong to code slated for
  retirement by AUD-SEC-005; after it only the legacy forecast remains.

### AUD-QA-002 — local release baseline is incomplete in the current runtime (resolved in the Claude runtime)

- Severity: high verification blocker
- Classification: environment limitation
- Evidence: Flutter bootstrapping is blocked by a 403 to storage.googleapis.com. Deno imports from deno.land and jsr.io are blocked. The Supabase PostgreSQL image previously exhausted the Docker daemon's storage while unpacking.
- User impact: Flutter analyze/test, Android build, complete Deno checks, migrations, and SQL/RLS tests have not been reproduced locally.
- Recommendation: run these commands in GitHub Actions or a cloud image with the required network destinations and Docker storage.
- Second pass: reproduced in the Claude Code cloud runtime on main 50f93ec — flutter analyze clean,
  flutter test 309 passed, Deno 637 passed (supabase/tests, with scripts/agent/deno_import_map.json mapping
  deno.land imports to jsr/npm), all 61 migrations and 13 SQL tests pass on PostgreSQL 16 + PostGIS +
  pg_cron without Docker (scripts/dev/local-db/run.sh). GitHub Actions on main are green, including the
  migrations job. Tools are restored in a fresh container by scripts/agent/bootstrap.sh.

### AUD-SEC-005 — legacy Guardian v0 and demo endpoints are still deployed (second pass)

- Severity: high
- Classification: confirmed attack surface and ADR-022 violation
- Evidence: deploy.yml deploys every function directory. Fourteen legacy Guardian v0 owner endpoints
  (guardian-session-create, -ping, -sos, -close, …), guardian-tick/-notify/-retry and their pg_cron jobs
  (every minute and every 30 seconds) remain, although the client uses only v1-guardian (ADR-022 §22.8:
  Guardian only in the app, no links). guardian-demo-create is unauthenticated, writes rows and returns a
  link-based Guardian URL. No current client calls any of them (Flutter uses only v1-* and /regions).
- User impact: unnecessary public attack surface (including an unauthenticated write path), legacy phone
  number storage, background jobs consuming function invocations, and code that cannot pass type checking.
- Recommendation: retire the v0 pipeline in one reviewed PR: stop deploying and delete the functions
  through the existing deletion loop, unschedule the legacy cron jobs and trigger in a migration, update the
  smoke test, keep data tables until the owner decides on deletion (retention is a product decision).
- Required verification: deploy dry-run, migrations and SQL tests on a fresh database, smoke test updated.

### AUD-SEC-006 — public weather proxy without authentication or rate limit (second pass)

- Severity: medium
- Classification: confirmed
- Evidence: forecast-weather accepts arbitrary coordinates without a token or rate limit and forwards them to
  the weather provider; no client uses it (v1-forecast replaced it).
- User impact: third-party quota and cost abuse attributed to the project (BACKEND_PLAN §5.1 requires a
  commercial Open-Meteo key before publication).
- Recommendation: retire together with AUD-SEC-005 or put behind JWT and the IP limiter.

### AUD-PRIV-001 — private-photo storage isolation lacked a direct RLS regression test

- Severity: medium (regression risk; no confirmed data leak)
- Classification: test coverage gap
- Evidence: handler tests already reject foreign upload paths and SQL/handler suites cover exact pick
  coordinates, private picks, Guardian routes, friendships and trophies. The private `mushroom-photos`
  bucket has owner-folder policies, but no SQL test directly exercised SELECT/INSERT/UPDATE/DELETE as two
  different authenticated users and anon.
- User impact: a future storage-policy regression could expose draft photos or allow a client to target a
  foreign or server-only object path without a focused failing test.
- Resolution: `rls_storage_picks.sql` on `codex/sec-006-private-data-idor-tests` verifies the bucket remains
  private, user-folder isolation, denial of foreign writes, denial of the server-only `picks/` prefix and
  denial for anon. The targeted PostgreSQL 16 run passes; full migration/SQL CI is pending.

### AUD-PROD-001 — rating has no sources, so levels never progress (second pass)

- Severity: high (product correctness)
- Classification: confirmed gap
- Evidence: no rating_events table or award functions in migrations; users.rating stays 0. Levels (ADR-013),
  public picks (ADR-010/019), avatars by level (ADR-021 §21.7) and wave alerts for «Слідопит» depend on it.
  docs/tasks/NEXT_TASK.md (B3.7 + B3.2) describes this work and is still relevant, but must be reconciled
  with ADR-019 limits and the trophy rules (ADR-021 §21.10) before implementation.
- User impact: nobody can reach higher levels, publish points or unlock avatars.

### AUD-WEB-001 — web-guardian app calls removed link-based endpoints (second pass)

- Severity: low
- Classification: confirmed dead code
- Evidence: web-guardian/src calls guardian-session-get/-track/-gpx and guardian-rescue-get, deleted by
  deploy.yml under ADR-022. The app is not deployed by any workflow in this repository.
- Recommendation: remove the link pages or the whole app after confirming nothing external hosts it.

## Positive controls observed

- Supabase Anonymous Sign-In and server-driven onboarding are implemented.
- v1 endpoints use server-side JWT verification through auth.getUser.
- Pick creation uses signed upload URLs, validates file format and metadata, and separates draft and final paths.
- Public pick coordinates use a server-side display geometry while owners receive precise coordinates.
- Guardian in-app reads check ownership or accepted Guardian membership before returning route details.
- RLS is enabled throughout current schema migrations and 13 SQL security/regression scripts exist.
- The project contains 666 Deno test declarations, 305 Flutter test declarations, and 41 Flutter test files.

## Audit limits

First pass: GitHub metadata could not be queried (invalid GH_TOKEN in the Codex runtime). Second pass: the
Claude runtime reads PRs and CI through its GitHub connection; branch protection settings are not visible to
it and remain an owner check. Production Supabase state was not inspected or modified. UI rendering, device behavior, performance, and iOS behavior remain unverified.
