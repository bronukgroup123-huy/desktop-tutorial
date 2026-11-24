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

## 2026-11-22 08:27 UTC — SEC-006 private-data / IDOR negative coverage (Codex)
- Branch / SHA: `codex/sec-006-private-data-idor-tests` @
  `40490e4937b0fec15fcd897afe7bbfb866c2195c`
- Done: audited existing endpoint and RLS coverage for precise/private picks, Guardian routes, friends and
  trophies; added the missing direct RLS regression for the private `mushroom-photos` bucket. It proves
  two-user folder isolation, denial of foreign and server-only paths, and denial for anon.
- Checks: targeted PostgreSQL 16 bootstrap + storage migration + new SQL test → pass; `git diff --check` →
  pass. Targeted Deno suite did not execute because `jsr.io/@std/assert` was unavailable in this runtime.
  Full local Supabase startup was also blocked by ECR access and the rootless Docker extraction quota;
  blocking PR CI must run all 63 migrations, 16 SQL scripts and Deno tests.
- Problems / residual risks: no staging project for deployed IDOR smoke tests; full PR CI pending.
- PR: branch will be pushed; creation may require the compare URL because Codex GitHub API auth remains
  unavailable (BLK-001).
- Next: AND-001 — ensure store artifacts can never fall back to the public test signing key.
- Blockers: BLK-001 (PR creation), BLK-007 (staging verification).

## 2026-11-22 08:44 UTC — AND-001 Android signing separation (Codex)
- Branch / SHA: `codex/and-001-store-release-signing` @
  `2184704397941e10d2662ceb71b6d9e31290a34c`
- Done: made the rolling Android workflow test-only and removed all store secrets from it; added a separate
  manual store AAB workflow requiring four signing secrets; added Gradle fail-closed checks for required,
  partial or missing release signing; clearly renamed artifacts and documentation; added a blocking CI guard.
- Checks: Android signing Node tests → 6 passed / 0 failed; repository signing guard → pass; existing Edge
  auth tests/matrix → pass; workflow YAML parse → pass; Bash syntax for all changed workflow scripts → pass;
  `git diff --check` → pass.
- Problems / residual risks: Flutter/Gradle could not run locally because the restored Flutter checkout lacks
  Dart SDK artifacts and `storage.googleapis.com` is denied. Android PR CI must compile both Gradle and the
  test APK. A real store AAB cannot be validated without the owner's signing identity (BLK-011).
- PR: branch will be pushed; creation may require the compare URL because Codex GitHub API auth remains
  unavailable (BLK-001).
- Next: check this PR's Android/Tests CI; after merge, continue the highest-priority backend/CI task without
  entering Claude's product/UI files.
- Blockers: BLK-001 (PR creation), BLK-011 (real store signing validation).

## 2026-11-22 16:09 UTC — QA-003 Flutter/OpenAPI model contract (Codex)
- Branch / SHA: `codex/qa-003-openapi-model-contract` @
  `91cd6207d9a541b094dbe7c52bb1f07c556b9c9b` (implementation; documentation commit follows).
- Done: added a blocking compatibility guard for 18 core Flutter/OpenAPI model bindings and five focused
  parser/drift tests. The initial red run found genuine analysis contract drift; documented the implemented
  `refresh: weather`, weather freshness, day parts, rain spans, hazards and per-day other-species fields.
- Checks: contract tests 5 passed / 0 failed; repository guard 18 models passed; Android signing tests 6/6;
  Edge auth tests 4/4 and 17-function matrix; OpenAPI/workflow YAML parsing and `git diff --check` passed.
- Problems / residual risks: the focused static guard checks top-level consumed/required keys, not complete
  nested types, enums or nullability. Flutter analyze/tests did not run locally because the restored SDK is
  incomplete; blocking PR CI remains authoritative.
- PR: branch pushed. GitHub GraphQL creation returned `403 Forbidden`; create/review without automerge at
  https://github.com/bronukgroup123-huy/desktop-tutorial/pull/new/codex/qa-003-openapi-model-contract
- Environment: onboarding draft revision 5 was saved with Flutter 3.47.9 setup, lockfile-safe dependency
  restore, current verification commands and `storage.googleapis.com`. It requires owner Review/Save and
  Publish before a fresh-task Flutter validation; saving the draft did not alter this running instance.
- Next: verify QA-003 PR CI after it is opened/merged, then select the next backend/security/CI backlog item
  without entering Claude's product/UI files.
- Blockers: BLK-001 (API PR creation only); onboarding draft publication for reproducible local Flutter;
  no implementation blocker.

## 2026-11-22 18:38 UTC — CI-001 workflow permissions and credential scope (Codex)
- Branch / SHA: `codex/ci-001-workflow-permissions` @
  `410888b` (permissions guard plus production-secret scoping; documentation commit follows).
- Done: gave all 17 workflows explicit top-level permissions; constrained deploy/smoke to `contents: read`;
  removed production secrets from job scope; made API-key extraction fail closed; masked dynamic anon,
  service-role and user JWT values; added a blocking repository guard with seven regression tests.
- Checks: workflow-permission tests 7 passed / 0 failed; repository guard reports 17 explicit and four
  reviewed write-scoped workflows; three YAML files and 26 shell blocks parse; existing OpenAPI, Android
  signing and Edge auth guards pass; `git diff --check` passes.
- Problems / residual risks: GitHub repository-default rights remain unobservable because the API returns
  403. Live smoke/deploy was not run and must remain outside an agent branch.
- Owner decision: Codex API automation is paused; `codex/aut-001-five-hour-cycle` must not be merged. Work
  continues only interactively after an owner message (BLK-005).
- PR: branch pushed; GitHub GraphQL creation returned `403 Forbidden`. Review without automerge at
  https://github.com/bronukgroup123-huy/desktop-tutorial/pull/new/codex/ci-001-workflow-permissions
- Next: verify CI-001 PR CI, then select another Codex-owned security/backend/CI item.
- Blockers: BLK-001 affects direct PR creation only; no implementation blocker.

## 2026-11-24 — manual state reconciliation (Codex)
- Baseline: `main` / `origin/main` at `b710d10e1061719c7a7bb0357935910e8b76cf9b` (merge PR #119).
- GitHub: PRs #108–115 and #117–119 are merged. PR #116 is open, docs-only, `CONFLICTING/DIRTY`, and stale
  relative to merged UI-001, AND-001, QA-003 and CI-001 work. No PROD-001 implementation PR is open.
- Main CI: `Tests` (Flutter, Deno, fresh migrations), `Security` and `Deploy to Supabase` passed on `b710d10e`.
  The most recent Android test APK passed on `f0e2a829` (PR #115 merge), not on the final documentation/CI SHA.
- Confirmed open defect: scheduled `Wave alerts` failed three consecutive runs with curl exit 22, most recently
  run `45211395928` on `b710d10e`. Exact HTTP response is absent from check annotations; no production retry
  or probe was performed.
- Data workflow findings: Dependabot PRs #3/#23 fail the secret-dependent `Supabase public config` job;
  PR #23 additionally fails the OSM-label download step with curl exit 22 and no artifact. Generator unit/type
  checks pass, so these failures do not currently demonstrate a generator regression.
- Code/docs reconciliation: `rating_events`, `compute_level` and rating award sources are absent; public picks
  still use the temporary hard-coded 201-point/5-per-day rule. `flutter_client/ios` is absent. NEXT_TASK,
  BACKEND_PLAN, AUTH_FLOW and DB_SCHEMA contain material historical assumptions and require DOC-001.
- Changes in this session are documentation only: BACKLOG status/priority corrections plus current GitHub/CI
  evidence. No workflow, product code, production system or external automation was changed.
- Recommended next Codex task: OPS-001, because a current scheduled product workflow is failing and it does
  not overlap the historically Claude-assigned PROD/UI work. Wait for the owner's explicit command.

