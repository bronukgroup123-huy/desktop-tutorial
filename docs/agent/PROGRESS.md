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

## 2026-11-24 — OPS-001 wave-alert workflow recovery (Codex)
- Baseline: `main` at `ec7eba26799f62c205038fdeab0b916b57e58e2a` (PR #120 merged); branch
  `codex/ops-001-wave-alert-workflow`.
- Evidence: every scheduled `Wave alerts` run since the workflow was introduced failed immediately in the
  single `Send wave alerts` step with curl exit 22. The workflow omitted the `apikey` header that the same
  repository uses for service-role Supabase calls, and combined Management API/key lookup and Edge Function
  invocation into one opaque shell step.
- Done: replaced the inline curl with a tested Node runner; the Edge Function request now sends both
  `Authorization` and `apikey`; missing secrets/key, Management API failures, Edge HTTP failures and malformed
  success payloads fail closed with stage-specific diagnostics. Only a validated snake_case remote error code
  may reach logs; key material and response messages do not. Production secrets are scoped to the consumer
  step, and the dynamic service key is masked before use.
- Regression protection: the blocking workflow guard requires the tested runner and rejects job-scoped
  secrets for `wave-alerts.yml`; the old `main` workflow fails this new guard as expected.
- Local checks: `run-wave-alerts.test.mjs` 8/8; `check-workflow-permissions.test.mjs` 8/8; repository workflow
  guard passed (17 workflows, four reviewed write-scoped); Node syntax, workflow YAML parse and
  `git diff --check` passed.
- Safety: no scheduled/manual dispatch, production request, secret read or deployment was performed. A live
  success can only be confirmed after owner review/merge through the next schedule or an owner-authorized run.
- Ownership: PR #116 was reviewed for boundaries. Codex retains OPS/CI/security/release infrastructure;
  Claude retains UI/PERF/PROD/WEB/DOC work unless the owner directly reassigns it.
- Commit / PR: `6935859` / PR #121. No auto-merge; full PR CI and post-merge scheduled verification pending.

## 2026-11-25 00:40 UTC — scheduled run 3: PROD-001 step 0 (Claude)
- Outage: 15 runs queued 2026-11-22 16:34 → 2026-11-25 00:34 while the session worker restarted; processed as
  one run (BLK-012).
- Sync: merged since run 2 — #115 (UI-001), Codex #117 (AND-001), #118 (QA-003), #119 (CI-001), #120 (DOC-001
  state reconciliation). Open: Codex #121 (OPS-001). No open claude/* PRs.
- Branch: claude/prod-001-spec
- Done: reconciled docs/tasks/NEXT_TASK.md (written 2026-11-11) with current code and ADR-019 §19.10 into a
  PROD-001 spec with three bounded PRs; numbers checked against ADR-019 §19.10.
- Checks: docs only (no code changed).
- Next: PROD-001a — rating_events, level_of, +1 for EXIF private picks, ADR-019 limits (migration + SQL tests)
- Blockers: BLK-012 (owner confirmation of the Claude cycle), others unchanged.

## 2026-11-25 04:35 UTC — scheduled run 4: PROD-001a (Claude)
- Branch / SHA: claude/prod-001a-rating-server (PR #123)
- Done: migration 20261125100000 — rating_events + trigger (rating = sum, ≥ 0), certificate columns,
  level_of (same bounds as levelOf), +1 for private picks with server-verified EXIF (≤ 5 / 7 days) inside
  create_pick, can_create_pick per ADR-019 §19.10 (private 5 at once + 10 new / 7 days; public from
  forester 7, keeper 15 / 7 days); v1-picks maps the new codes to 429; OpenAPI updated.
- Checks: `scripts/dev/local-db/run.sh` → 64 migrations, 20/20 SQL tests (new rls_rating.sql;
  rls_picks_adr018.sql moved from the daily rule to ADR-019); `deno test` → 588 passed / 0 failed;
  full `deno check` → 0 errors. Flutter untouched.
- Problems / residual risks: limits change on deploy; existing picks give no retroactive points.
- PR: #123
- Next: PROD-001b — v1-me certified level and picks permissions + OpenAPI

## 2026-11-25 08:35 UTC — scheduled run 5: PROD-001b (Claude)
- Open agent PRs: #123 — Tests (incl. migrations) and Security green; #122 docs only.
- Branch / SHA: claude/prod-001b-me-picks (from #123's branch) → PR #124
- Done: v1-me `picks { public_allowed, public_hint_label, private_allowed, private_hint_label }` decided by the
  same can_create_pick as creation; guests get the sign-in hint without a DB call; DB failure → picks null;
  level honours knowledge_certified_at; OpenAPI Me.picks.
- Checks: `deno test` → 592 passed / 0 failed (4 new); full `deno check` → 0 errors;
  `check-flutter-openapi-models.mjs` → 18 models valid.
- PR: #124 (merge after #123)
- Next: PROD-001c — Flutter form uses picks permissions and hints

## 2026-11-25 12:35 UTC — scheduled run 6: PROD-001c (Claude)
- Open agent PRs: #123 and #124 — all checks green (Deno, Flutter, migrations, Gitleaks).
- Branch / SHA: claude/prod-001c-flutter-picks (from #124) → PR #125
- Done: Me.picks; pick form disables «Усі» with the server hint and forces private; private-limit warning
  without blocking save; map FAB «Приватний тук-тук» when public picks are not allowed; profile refresh after save.
- Checks: `flutter analyze` → no issues; `flutter test` → 326 passed (4 new); OpenAPI model contract → valid.
- PR: #125 (merge after #124)
- Next: owner merges the PROD-001 series; meanwhile UI-002 (design tokens) or PERF-001 (static analysis).

## 2026-11-25 17:30 UTC — PROD-001 merged; docs conflicts resolved (Claude)
- Owner merged #123 (server), #124 (v1-me picks), #125 (Flutter). PROD-001 is done; PR #122 (spec + agent
  records) merged main and resolved BACKLOG/PROGRESS conflicts with Codex's OPS-001 records (both kept).
- PR #116 (agent state after run 2) is superseded by #120 and #122 — closed without merge.
- Residual: BACKEND_PLAN B3.7/B3.2 statuses and the pick form in the a11y stress test (follow-up).


## 2026-11-25 16:10 UTC — UI-001b: stress test of the main tabs (Claude)
- Branch: claude/ui-001b-stress-tabs (from main after PROD-001)
- Done: new `test/a11y/tabs_stress_test.dart` (Safety, Forecast area with result, Catalog with the AI banner
  in «not downloaded» state, species card, pick form with public picks not allowed) × the three stress cases.
  It found and the PR fixes: SOS circle text (FittedBox inside the fixed circle), forecast area tiles (grow
  with text, 68 px minimum), forecast header (scrolls within 55 % of the height), AI banner (210 px minimum,
  grows; overflowed by 37 px even on a 320×568 phone at normal text size), species-card photo badges (both
  shrink with ellipsis). Normal-size layout unchanged (tile 68 px, banner 210 px measured).
  BACKEND_PLAN B3.2/B3.7 marked done for PROD-001.
- Checks: new test without the fixes → 5 failures (overflows 8–394 px); with fixes → `flutter test` 341 passed;
  `flutter analyze` → no issues.
- Next: UI-002 (design tokens) or PERF-001 (static analysis).

## 2026-11-25 16:45 UTC — UI-002 part 1: color tokens (Claude)
- UI-001b merged as PR #127 (owner created the PR after GitHub returned 500 to the agent).
- Branch: claude/ui-002-design-tokens (from main)
- Done: `AppTheme.danger` (#C62828), `success` (#2E7D32), `warning` (#B45309); every literal copy of these
  and of the existing tokens (background, dark green, accent orange) in lib/ replaced by the token — 94
  places in 23 files, same values, so no visual change. New `test/design_tokens_test.dart` pins token values
  and fails on a new literal copy in lib/.
- Checks: `flutter analyze` → no issues; `flutter test` → 343 passed (2 new).
- Next: UI-002 part 2 (radii, heading styles, card decoration) or PERF-001.

## 2026-11-25 17:20 UTC — scheduled run: PERF-001 part 1 (Claude)
- Open agent PRs: #128 (UI-002 part 1) — CI running, nothing red.
- Branch: claude/perf-001-static (from main; independent of #128)
- Measured in widget tests (no device):
  - mini-map stickers: 0 map repaints in 60 animation frames → not a hotspot, guard test added;
  - capture thumbnails: 1280×720 frame decoded at full size = 3.69 MB each (×3) → 310×174 = 0.22 MB;
  - pick preview: decode width limited to the box (e.g. 1600×1200 = 7.7 MB → 1173×880 = 4.1 MB at dpr 3).
- Done: `core/image_decode.dart` (cover-safe decode width: short side of a 16:9 frame in either orientation
  still covers the box, never upscales); applied to capture thumbnails and the pick preview; tests in test/perf.
- Checks: `flutter analyze` → no issues; `flutter test` → 346 passed (5 new).
- Next: UI-002 part 2 after #128, or DOC-001.

## 2026-11-25 19:15 UTC — SEC-007 rating ledger concurrency (Codex)
- Baseline: `main` at `9d19985` after Claude UI-002 part 1; branch
  `codex/sec-007-rating-ledger-concurrency`, PR #130.
- Found: `rating_events_apply()` recomputed `users.rating` without a per-user lock. Two independent server
  transactions could both commit ledger events while the last stale user-row update lost one point.
- Regression first: commit `d3be70d`, run `45656240950`; all existing SQL/RLS tests passed and the new
  two-connection `Rating ledger concurrency` step failed on the unfixed trigger.
- Done: migration `20261125191233` locks the `public.users` row before reading the ledger, then recomputes
  the exact sum using a fresh READ COMMITTED snapshot; trigger-function ACLs remain revoked from API roles.
- Checks after fix: commit `bcbd721`, run `45682938812`; migrations, all SQL/RLS tests, the concurrency
  regression, Deno tests/type checks and Security passed. Flutter was unchanged; its CI job was still
  completing when documentation was written and will rerun on the final branch commit.
- Safety: no production query or manual deployment was performed. Merge applies one Supabase migration;
  owner review is required and the PR must not auto-merge.
- Next Codex priority: review the refreshed, green GitHub Actions Dependabot PRs (#3, #22, #23); IOS-001
  remains blocked by macOS and Apple configuration. Claude owns remaining UI-002 and product performance work;
  PERF-001 part 1 merged as PR #129.

## 2026-11-25 19:30 UTC — UI-002 part 2: heading styles (Claude)
- Owner merged #128 (color tokens) and #129 (PERF-001 part 1, after the PROGRESS.md conflict was resolved
  by merging main and keeping both entries).
- Branch: claude/ui-002b-radii-headings (from main) → PR #131
- Done: `AppTheme.appBarTitle` / `AppTheme.heading(size)`; 33 identical Merriweather calls in 22 files
  replaced; 17 special ones (shadow, other color, conditional size) left. Radii and card decoration left on
  purpose (see BACKLOG UI-002).
- Checks: `flutter analyze` → no issues; `flutter test` → 350 passed (2 new).
- Process: agent state now goes in a separate small PR (this one), so task PRs no longer conflict.
- Next: DOC-001 — reconcile NEXT_TASK, BACKEND_PLAN, AUTH_FLOW and DB_SCHEMA with the code.

## 2026-11-25 19:51 UTC — CI-003 artifact action round trip (Codex)
- Baseline: `main` at `13aa529`; branch `codex/ci-003-artifact-roundtrip`, PR #133.
- Found: Dependabot PR #22 did not execute `download-artifact@v8` because its download steps are limited to
  publish jobs, while PR #23 still exposes a stale pre-CI-002 PR ref. The first CI-003 runs also demonstrated
  GitHub Artifact API eventual consistency immediately after a finalized upload.
- Done: added a blocking generated-payload round trip using `upload-artifact@v7`,
  `download-artifact@v8`, immutable `artifact-id`, one bounded five-second retry and byte comparison with
  `cmp`; artifact retention is one day. Reconciled completed SEC-007, OPS-001, PERF-001 and CI-002 statuses.
- Checks: local workflow-permission tests 11/11 and repository guard passed; final push and pull-request runs
  both passed artifact round trip, Deno, Flutter, fresh migrations and Gitleaks.
- Safety: the job generates one text file, receives no secrets, checks out no repository code, calls no
  production service and performs no deployment.
- Rebase/merge status: merged current `main` at `54bbe1e`, retaining both the Claude UI-002 and Codex CI-003
  records. PRs #131 and #132 are merged; DOC-001 remains Claude-owned.
- Next: owner reviews/merges #133; then refresh Dependabot #3/#22/#23 against `main` and assess them separately.
