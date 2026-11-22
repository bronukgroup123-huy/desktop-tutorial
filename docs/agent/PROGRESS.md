# Engineering progress

## Session 2026-11-22

Date and commit: 2026-11-22, branch codex/security-guard-service-endpoints, security commit 072ed76185930c893e5a83ace8af68b58a9751a1, baseline c8f12f5e075bbc47ed78da17af1acaf87a1a3216.

### Completed

- Reconciled the current repository with ADRs, backend plan, API, auth flow, database documentation, recent merge history, and CI workflows.
- Confirmed that NEXT_TASK.md is stale relative to merged work through PR #107.
- Audited Flutter structure, Supabase functions and migrations, Android configuration, test inventory, and iOS presence.
- Implemented SEC-001. Internal Guardian tick, notify, and retry jobs now require the exact service-role bearer token.
- Protected the Telegram test endpoint and excluded it from future deployments. The deployment workflow deletes an existing deployed copy after merge.
- Added four negative and positive service-auth tests.
- Prepared persistent audit, roadmap, backlog, quality, security, progress, and blocker records.
- Prepared a disabled-by-default scheduled Codex workflow with concurrency and PR-only delivery.

### Verified

- Targeted Guardian service-auth test passed 4 tests.
- Deno check on the new service-auth helper passed.
- Web Guardian Vitest suite passed 16 tests.
- Web Guardian Next.js production build completed successfully.
- Git diff whitespace check passed before the security commit.

### Problems and residual risks

- Full Deno checks and tests are blocked by denied access to deno.land and jsr.io.
- Flutter analyze, tests, and Android builds are blocked because the Dart SDK download from storage.googleapis.com returns 403.
- Fresh database and SQL/RLS checks require more Docker storage than this runtime provides.
- GitHub metadata and PR creation are blocked by an invalid GH_TOKEN and blocked unauthenticated API access.
- SEC-002, SEC-003, and the remaining endpoint authorization matrix are unresolved.

### PR

Branch codex/security-guard-service-endpoints was pushed to origin. PR creation failed because GitHub GraphQL returned 403 with the configured invalid token. Review URL:

https://github.com/bronukgroup123-huy/desktop-tutorial/pull/new/codex/security-guard-service-endpoints

### Next task

SEC-002. Harden public.import_forest_zones_batch(jsonb) and add negative privilege tests.

### Blockers

See docs/agent/BLOCKERS.md.

## 2026-11-22 02:35 UTC — second pass: verified baseline, audit, SEC-002, autonomous cycle (Claude)
- Branch / SHA: main @ 50f93ec (baseline); claude/sec-002-definer-privileges @ PR #109; claude/agent-state (this)
- Done:
  - Reproduced the full baseline that was blocked in the Codex runtime (Flutter, Deno, fresh DB).
  - Second-pass audit: SECURITY DEFINER privileges on a real database (8 functions exposed), Edge Function
    authentication matrix, legacy Guardian v0 / demo / weather proxy still deployed (SEC-005), rating has no
    sources (PROD-001), web-guardian dead link pages (WEB-001). AUDIT, SECURITY_REPORT, QUALITY_REPORT,
    BACKLOG and BLOCKERS updated.
  - SEC-002 fixed: migration + regression test + local DB harness → PR #109.
  - Autonomous cycle: docs/agent/AUTONOMY.md runbook, scripts/agent/bootstrap.sh, deno import map,
    scheduled task trig_01Bc28cWHYwhYc8uHrE2t8iF («Mushroom Radar — autonomous cycle», every 4 h at :30,
    first run 2026-11-22 04:38 UTC) delivering into session_01QAqVzCi4Q7QaBgkAWQxUoK.
- Checks:
  - `flutter analyze` → no issues; `flutter test` → 309 passed
  - `deno test … supabase/tests/` → 637 passed, 0 failed
  - `deno check … supabase/functions/*/index.ts` → 33 errors (legacy only, see QUALITY_REPORT)
  - `scripts/dev/local-db/run.sh` → 61/61 migrations, 13/13 SQL tests (main); 62/62 and 14/14 with PR #109;
    new test fails without the migration
  - bootstrap.sh Deno step → installs deno 2.5.6 into a clean directory
- Problems / residual risks: production changes only after owner merges (BLK-008); no staging (BLK-007).
- PR: #109 (SEC-002); agent-state PR (this)
- Next: SEC-005 — retire legacy Guardian v0, demo and weather-proxy endpoints
- Blockers: see BLOCKERS.md (owner: merge #109; optional Codex setup)

## 2026-11-22 04:40 UTC — scheduled run 1: SEC-005 + QA-002
- Branch / SHA: claude/sec-005-retire-legacy-endpoints (PR #111)
- Open agent PRs checked first: #109 and #110 — Tests (incl. migrations job on Supabase CLI) and Security green.
- Done: retired legacy Guardian v0 (14 owner functions, guardian-tick/-notify/-retry + cron jobs + notify
  trigger), guardian-demo-create, forecast-weather and the legacy forecast; 18 unused _shared/guardian modules
  removed (static import graph); deploy.yml deletes them from the project; migration 20261122110000 +
  SQL regression retired_guardian_v0.sql; smoke-test.yml rewritten for v1 (200 / 401 / 404 checks);
  full deno check made blocking (QA-002); docs updated.
- Checks:
  - `scripts/dev/local-db/run.sh` → 62/62 migrations, 15/15 SQL tests; new test red without the migration
  - `deno test … supabase/tests/ supabase/functions/_shared/` → 579 passed, 0 failed
  - `deno check supabase/functions/*/index.ts supabase/tests/ supabase/functions/_shared/` → 0 errors (was 33)
  - Flutter not touched
- Problems / residual risks: production deletion happens on merge; legacy v0 tables kept (BLK-009);
  deploy.yml still sets legacy SMS/TextBee secrets (harmless, cleanup later).
- PR: #111
- Next: SEC-003 — rate limiting must not fail open
- Blockers: unchanged (owner merges #109, #111, #110)

## 2026-11-22 07:39 UTC — SEC-003 fail-closed rate limiting (Codex)
- Branch / SHA: `codex/sec-003-rate-limit-fail-closed` @ `569e6212d19802ca6bd161b5f6d29fb13591172e`
- Done: removed the non-atomic direct-table fallback and fail-open path; validated object and PostgREST
  array RPC results; mapped undecidable rate limits to retryable `503 rate_limit_unavailable` for v1,
  legacy public reads and the legacy mutation endpoint; added seven regression tests.
- Checks: targeted Deno tests → 7 passed / 0 failed; type-check of shared limiter, v1 HTTP, regions,
  catalog and test → pass; lint of all changed TypeScript files excluding the repository-wide existing
  `no-import-prefix` rule → pass; `git diff --check` → pass.
- Problems / residual risks: isolated `picks` type-check is blocked before analysis because `jsr.io` cannot
  provide the existing `djwt` dependency in this runtime; blocking CI must run the full suite.
- PR: branch pushed; creation pending because the Codex `GH_TOKEN` is invalid (BLK-001). Compare URL:
  https://github.com/bronukgroup123-huy/desktop-tutorial/pull/new/codex/sec-003-rate-limit-fail-closed
- Next: SEC-004 — enable platform JWT verification by default with an explicit public/service/webhook matrix.
- Blockers: BLK-001 (PR creation), BLK-007 (staging verification).

## 2026-11-22 07:55 UTC — SEC-004 Edge Function JWT matrix (Codex)
- Branch / SHA: `codex/sec-004-edge-jwt-matrix` @ `cb96b1c299900d6fdedd0fc10792adeb527e8c4a`
- Done: classified all 17 deployed Edge Functions in one machine-readable auth matrix; made gateway JWT
  verification the deployment default; limited bypass to seven reviewed public/mixed/webhook functions;
  mirrored the bypasses in `config.toml`; added a blocking CI drift checker and manual deployed smoke checks
  for public access, missing/malformed/anon-role tokens, service endpoints and webhook secrets.
- Checks: Node matrix tests → 4 passed / 0 failed; repository matrix check → 17 classified, 7 bypasses;
  workflow YAML parse → pass; Supabase CLI parsed config and then stopped because no local container is
  running; `git diff --check` → pass.
- Problems / residual risks: platform behavior cannot be exercised pre-merge without staging; production
  smoke is intentionally manual and has not been run. Full repository CI is pending on the PR.
- PR: branch will be pushed; creation may require the compare URL because Codex `GH_TOKEN` remains invalid.
- Next: SEC-006 — private-data and IDOR/BOLA negative tests.
- Blockers: BLK-001 (PR creation), BLK-007 (staging verification).

