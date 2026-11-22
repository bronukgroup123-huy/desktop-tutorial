# Prioritized engineering backlog

Statuses: ready · in_progress · in_review (PR open) · done (merged) · blocked_* · paused · blocked_rate_limit.
Order inside a priority is the execution order. The scheduled agent takes the first `ready` item
(docs/agent/AUTONOMY.md). Every item ends in its own branch and PR; nothing is merged by the agent.

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
- Status: in_progress — implementation and CI guards committed on
  `codex/sec-004-edge-jwt-matrix` at `cb96b1c`; PR creation pending BLK-001.

### SEC-006 — private data and IDOR/BOLA negative tests
- Goal: prove that precise coordinates, private picks, hike tracks, friends and Guardian data never leak to
  other users through v1 endpoints or RLS.
- Scope: Deno handler tests with foreign IDs; SQL RLS tests for picks/hikes/friendships/trophies; storage
  object paths of private photos.
- Status: ready

### QA-002 — all deployed Deno entrypoints in blocking type check
- Status: done — PR #111 (merged 2026-11-22; full `deno check` is blocking).

## P1 — product correctness

### PROD-001 — rating sources, levels and public-pick limits (B3.7 + B3.2)
- Goal: users.rating gets real sources so levels, public picks, avatars by level and wave alerts work.
- Scope: reconcile docs/tasks/NEXT_TASK.md with ADR-012/013/019 and ADR-021 §21.10 first (write the
  reconciliation into the PR), then migration (rating events, award functions, limits), v1-me/v1-picks,
  Flutter display, tests.
- Status: ready (large — split into PROD-001a server, PROD-001b client)

### QA-003 — Flutter OpenAPI model compatibility check
- Goal: models in flutter_client/lib/data/models match openapi/v1.yaml for v1 endpoints.
- Status: ready

## P1 — UI/UX, accessibility, performance

### UI-001 — accessibility and responsive baseline
- Goal: primary screens survive compact size (320×640), large text (×1.6–2.0) and reduced motion.
- Scope: widget tests per tab; fix overflows found (auth screen first, AUD-FL-001).
- Status: ready (Flutter runtime available)

### UI-002 — design tokens and shared components
- Goal: one source for colors, radii, typography and card styles (profile_hero.dart already defines the
  forest/parchment language) without changing approved looks.
- Status: ready (after UI-001)

### PERF-001 — measured hotspots
- Goal: measure rebuilds/frame time on map, forecast, catalog lists, profile animation; optimize only proven
  hotspots. Device measurements need the owner (BLK-010).
- Status: ready (static/profile-mode analysis only)

## P1 — release

### AND-001 — separate test APK from store release
- Goal: store artifacts never signed with the public test key.
- Status: ready

### IOS-001 — create and validate the iOS target
- Status: blocked_macos_and_apple_configuration (source preparation possible: ios/ target, Info.plist texts)

## P2 — cleanup

### WEB-001 — remove link-based web-guardian pages (AUD-WEB-001)
- Status: ready (confirm with owner whether anything external still hosts web-guardian → BLOCKERS)

### DOC-001 — reconcile docs/tasks/NEXT_TASK.md and BACKEND_PLAN statuses with code
- Status: ready (part of PROD-001)

### AUT-001 — Codex scheduled workflow (codex-autonomy.yml)
- Status: prepared_disabled. Not needed while the Claude scheduled cycle runs; enabling both at once risks
  concurrent edits. See BLOCKERS BLK-005.
