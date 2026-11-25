# Prioritized engineering backlog

Statuses: ready · in_progress · in_review (PR open) · done (merged) · blocked_* · paused · blocked_rate_limit.
Order inside a priority is the recommended execution order. Work is manual/interactive: an agent starts
only after an owner message, uses a dedicated branch and PR, and never merges its own work.

**Default ownership confirmed by the owner on 2026-11-24 (boundary source: PR #116):**
- **Codex:** security, backend hardening, CI, operations and release infrastructure (`SEC-*`, `OPS-*`,
  `CI-*`, `AND-*`, `IOS-*`, `QA-002/003`).
- **Claude:** Flutter UI/UX, accessibility, performance, product features (including their migrations),
  web cleanup and product documentation (`UI-*`, `PERF-*`, `PROD-*`, `WEB-*`, `DOC-*`).

Do not take an item from the other zone without a direct owner instruction. PR #116 contains the original
split but also stale task statuses; use it to review boundaries, not as a merge-ready state update.

## P0 — security and correctness

### SEC-001 — protect internal Guardian jobs
- Status: done — PR #108 (merged 2026-11-22). Residual: staging 401 checks (no staging project, BLK-007).

### SEC-002 — SECURITY DEFINER functions unreachable by API roles
- Goal: anon/authenticated cannot execute any SECURITY DEFINER function in public; fixed search_path.
- Scope: migration 20261122100000, SQL regression security_definer_privileges.sql, local DB harness.
- Acceptance: 62 migrations apply; all SQL tests pass; the new test fails without the migration.
- Status: done — PR #109 (merged 2026-11-22).
- Residual: staging verification remains blocked by BLK-007.

### SEC-005 — retire legacy Guardian v0, demo and weather-proxy endpoints
- Goal: remove deployed surface that ADR-022 replaced and no client uses (AUD-SEC-005, AUD-SEC-006).
- Scope: deploy.yml (stop deploying, add to deletion loop: 14 guardian-* v0 owner endpoints, guardian-tick,
  guardian-notify, guardian-retry, guardian-demo-create, forecast-weather); migration unscheduling legacy
  cron jobs and the notify trigger; delete function sources and their tests; smoke-test.yml update.
  Keep legacy data tables (deletion/retention is an owner decision → note in BLOCKERS).
- Acceptance: fresh-DB migrations + SQL tests pass; Deno tests pass; deno check of all remaining entrypoints
  loses the legacy errors; no client reference to removed functions; smoke test no longer calls them.
- Tests: SQL assertion that the legacy cron jobs are absent; Deno suite; grep guard in CI optional.
- Status: done — PR #111 (merged 2026-11-22). Also retired the legacy `forecast` function
  (unused, public compute) and closed QA-002 in the same PR.
- Residual: legacy data retention is still an owner decision (BLK-009).

### SEC-003 — rate limiting must not fail open
- Goal: abuse protection survives RPC/database failures.
- Scope: supabase/functions/_shared/rate-limit.ts (legacy IP limiter) and v1 enforceRateLimit; tests.
- Acceptance: mutating/notification endpoints fail closed (503) when the limiter cannot decide; public reads
  follow a documented policy; no non-atomic fallback counter.
- Tests: RPC failure, storage failure, 429, concurrency where possible.
- Status: done — PR #112 (merged 2026-11-22).
- Residual: deployed 503 behavior remains unverified without staging (BLK-007).

### SEC-004 — Edge Function authentication matrix and default JWT verification
- Goal: every deployed function classified (public / user JWT / service role / webhook secret) and platform
  JWT verification enabled by default, with an explicit allowlist of public endpoints.
- Scope: supabase/config.toml per-function verify_jwt (or deploy flags), docs/agent/SECURITY_REPORT.md matrix,
  negative tests for missing/invalid/anonymous tokens.
- Depends on: SEC-005 (fewer functions to classify).
- Status: done — PR #113 (merged 2026-11-22).
- Residual: deployed gateway smoke remains blocked without staging (BLK-007).

### SEC-006 — private data and IDOR/BOLA negative tests
- Goal: prove that precise coordinates, private picks, hike tracks, friends and Guardian data never leak to
  other users through v1 endpoints or RLS.
- Scope: Deno handler tests with foreign IDs; SQL RLS tests for picks/hikes/friendships/trophies; storage
  object paths of private photos.
- Status: done — PR #114 (merged 2026-11-22). The existing endpoint and SQL suites cover foreign precise
  coordinates, private picks, hike/Guardian tracks, friendships and trophies; the PR added direct private
  photo storage RLS coverage.

### SEC-007 — serialize rating ledger updates (owner: Codex)
- Goal: keep `users.rating` equal to the `rating_events` sum when independent server sources award points
  concurrently.
- Evidence: the two-transaction regression added in commit `d3be70d` fails on the PROD-001 trigger even
  though both ledger rows commit; the last stale `UPDATE users` loses one point.
- Status: done — PR #130 merged 2026-11-25. Migration `20261125191233` locks the user's row before
  recomputing the sum; merge tests, Security and Supabase deployment passed on `13aa529`.

### QA-002 — all deployed Deno entrypoints in blocking type check
- Status: done — PR #111 (merged 2026-11-22; full `deno check` is blocking).

## P1 — product correctness

### OPS-001 — restore the scheduled wave-alert job (owner: Codex)
- Goal: daily wave notifications run reliably and fail with enough diagnostics to distinguish Management
  API/key lookup failures from an Edge Function response failure.
- Evidence: scheduled runs `44909047424`, `45027103716` and `45211395928` all failed in `Send wave alerts`
  with curl exit 22; the latest failure is on `main` at `b710d10e` (2026-11-23).
- Safety: investigate through workflow metadata and non-production/local tests first; do not probe or mutate
  production from an agent branch.
- Status: done — PR #121 merged 2026-11-25. Local regression checks pass; the next scheduled invocation
  remains the live confirmation because agent branches do not call production.

### PROD-001 — rating sources, levels and public-pick limits (B3.7 + B3.2) (owner: Claude)
- Goal: users.rating gets real sources so levels, public picks, avatars by level and wave alerts work.
- Scope: reconcile docs/tasks/NEXT_TASK.md with ADR-012/013/019 and ADR-021 §21.10 first (write the
  reconciliation into the PR), then migration (rating events, award functions, limits), v1-me/v1-picks,
  Flutter display, tests.
- Status: done — spec PR #122; PROD-001a #123, PROD-001b #124, PROD-001c #125 merged 2026-11-25.
  Rating has its first source (+1 for private picks with server-verified EXIF, ≤ 5 / 7 days), levels honour
  the knowledge certificate, ADR-019 §19.10 limits are enforced, v1-me exposes pick permissions and the
  Flutter form/map show them. BACKEND_PLAN B3.7/B3.2 statuses and the pick form stress test — UI-001b.
  Further rating sources (B3.10 knowledge tests, B3.11 feedback, B3.8 community confirmation) — later.

### QA-003 — Flutter OpenAPI model compatibility check
- Goal: models in flutter_client/lib/data/models match openapi/v1.yaml for v1 endpoints.
- Scope: blocking CI guard for required and undocumented top-level JSON keys in 18 core models; keep the
  analysis weather/refresh contract aligned with the implemented server response.
- Tests: parser/unit negative cases, repository contract check, OpenAPI and workflow YAML parsing.
- Status: done — PR #118 (merged 2026-11-22).
- Residual: this focused guard does not prove nested anonymous object types, enum compatibility or runtime
  decoding; existing Flutter model tests and full PR CI remain required.

## P1 — UI/UX, accessibility, performance

### UI-001 — accessibility and responsive baseline
- Goal: primary screens survive compact size (320×640), large text (×1.6–2.0) and reduced motion.
- Scope: widget tests per tab; fix overflows found (auth screen first, AUD-FL-001).
- Status: done — PR #115 (merged 2026-11-22).
- Part 2 (UI-001b): tabs — Safety, Forecast (area with result), Catalog (AI banner not downloaded), species
  card, pick form. Status: done — PR #127 (merged 2026-11-25).

### UI-002 — design tokens and shared components (owner: Claude)
- Goal: one source for colors, radii, typography and card styles (profile_hero.dart already defines the
  forest/parchment language) without changing approved looks.
- Part 1 (colors): semantic tokens `AppTheme.danger/success/warning`; 94 literal copies of token values in
  23 screens replaced; `test/design_tokens_test.dart` blocks new copies. Status: done — branch
  `claude/ui-002-design-tokens`. Merged as PR #128 (2026-11-25).
- Part 2: radii (12/14/16/20 used ~110 times), Merriweather heading styles (52 calls), shared card
  decoration. Status: ready.

### PERF-001 — measured hotspots (owner: Claude)
- Goal: measure rebuilds/frame time on map, forecast, catalog lists, profile animation; optimize only proven
  hotspots. Device measurements need the owner (BLK-010).
- Part 1 (static + widget-test measurements): camera photos decoded at full size in 58×58 capture
  thumbnails (3 × 3.7 MB for 720p) and in the 220 px pick preview (up to 1600 px) → decode to the box
  (`core/image_decode.dart`), thumbnail 0.22 MB. Checked and not a hotspot: animated stickers do not repaint
  the mini-map (Opacity layers, 0 map repaints / 60 frames — guard test); infinite animations stop on
  reduce-motion and inactive tabs (go_router TickerMode); history thumbnails are already 320 px.
  Status: done — PR #129 merged 2026-11-25.
- Remaining: frame timings on a real device (BLK-010).

## P1 — release

### CI-001 — explicit workflow permissions and production-secret scope
- Goal: GitHub workflows never inherit unknown token permissions, and production secrets reach only the
  shell steps that use them.
- Scope: explicit read-only permissions for deploy/smoke; step-scoped Supabase/DB/smoke credentials;
  masking for dynamically fetched anon/service-role/JWT values; blocking repository guard.
- Tests: repository inventory plus negative cases for missing permissions, unreviewed writes, production
  write access, unmasked dynamic credentials and job-level production secrets.
- Status: done — PR #119 merged 2026-11-22; `Tests`, `Security` and `Deploy to Supabase` passed on merge SHA
  `b710d10e`.
- Residual: repository-default permissions remain unobservable through the current GitHub API, but explicit
  workflow declarations no longer rely on that setting. Live production smoke remains intentionally outside
  agent branches.

### CI-002 — make data workflows safe and useful on dependency PRs (owner: Codex)
- Goal: secret-dependent data-generation jobs do not fail noisily on Dependabot PRs, while generator/unit
  checks remain blocking and real scheduled/manual generation still fails closed.
- Evidence: PR #3 (`actions/checkout@7`) fails `Forests data / Supabase public config` with exit 5; PR #23
  also fails that step and separately fails `Forest type / OSM labels` with curl exit 22 after producing no
  artifact. Dependabot PRs do not receive repository secrets, so the Management API fallback cannot be a
  required PR check. The OSM download failure needs separate reproducible diagnostics before a code change.
- Status: done — PR #126 merged 2026-11-25. Dependabot PRs now run generator validation and artifact smoke
  checks while heavy secret-dependent jobs remain limited to schedules/manual dispatch.

### CI-003 — validate artifact action majors before repository-wide upgrade (owner: Codex)
- Goal: exercise both upload and download, including payload integrity, before Dependabot PRs #22/#23 replace
  every artifact action reference with Node 24 majors.
- Evidence: PR #22 is green but its `download-artifact@v8` steps exist only in publish jobs skipped on PRs;
  PR #23 still points at a stale pre-CI-002 head with unrelated data-job failures.
- Status: in_review — PR #133, branch `codex/ci-003-artifact-roundtrip`. The blocking `Tests` workflow uses
  `upload-artifact@v7` and `download-artifact@v8` for a one-day smoke artifact and verifies the downloaded
  bytes with `cmp`. The first PR runs exposed eventual consistency immediately after upload for both name-
  and ID-based lookup, so the download is keyed by the immutable upload output `artifact-id` and gets one
  bounded retry after five seconds. After merge, refresh PRs #3/#22/#23 against current `main`.

### AND-001 — separate test APK from store release
- Goal: store artifacts never signed with the public test key.
- Status: done — PR #117 (merged 2026-11-22).
- Residual: the first store-signed AAB still requires owner-held signing credentials (BLK-011).

### IOS-001 — create and validate the iOS target (owner: Codex; owner dependencies remain)
- Status: blocked_macos_and_apple_configuration (source preparation possible: ios/ target, Info.plist texts)

## P2 — cleanup

### WEB-001 — remove link-based web-guardian pages (AUD-WEB-001) (owner: Claude)
- Status: blocked_owner_confirmation (confirm whether anything external still hosts web-guardian → BLK-009).

### DOC-001 — reconcile docs/tasks/NEXT_TASK.md and BACKEND_PLAN statuses with code (owner: Claude)
- Status: ready (broadened to include stale AUTH_FLOW and DB_SCHEMA claims).
- Current evidence: NEXT_TASK still prescribes PROD-001 automatically; BACKEND_PLAN, AUTH_FLOW and DB_SCHEMA
  describe retired Guardian v0/base64 flows or old migration/table counts. Reconcile against migrations,
  OpenAPI and current handlers before using them to drive code.

### AUT-001 — Codex scheduled workflow (codex-autonomy.yml)
- Status: paused_owner_choice — on 2026-11-22 the owner explicitly chose interactive Codex use only, with
  no Codex API. Do not merge/activate `codex/aut-001-five-hour-cycle`; see BLK-005.
