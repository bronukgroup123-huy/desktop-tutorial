# Quality baseline

Date: 2026-11-22
Baseline: c8f12f5e075bbc47ed78da17af1acaf87a1a3216

## Test inventory

- Deno test declarations: 666
- Flutter test declarations: 305 across 41 test files
- SQL/RLS scripts: 13
- Edge Function directories: 38
- SQL migrations: 61

Counts describe test assets. They do not imply execution or coverage percentage.

## Executed checks

| Check | Result | Evidence |
|---|---|---|
| Guardian service auth unit test | Pass, 4/4 | Missing, malformed, missing-server-key, and valid-token cases |
| Service auth type check | Pass | Deno check on the new local-only helper |
| Web Guardian unit tests | Pass, 16/16 | Vitest |
| Web Guardian production build | Pass | Next.js compiled, type checked, and generated 13 routes |
| Root npm test | Fail by repository configuration | Root script intentionally reports no test specified |
| Full Deno strict check | Blocked | deno.land CONNECT denied |
| Full Deno unit suite | Blocked | deno.land and jsr.io CONNECT denied |
| Flutter analyze | Blocked | Dart SDK artifact host denied |
| Flutter tests | Blocked | Dart SDK artifact host denied |
| Android release APK | Blocked | Flutter SDK unavailable |
| Fresh migrations and SQL/RLS tests | Blocked | Docker image storage exhaustion |
| iOS build | Not available | No iOS target or macOS environment |

## Verified baseline — 2026-11-22, Claude runtime, main 50f93ec

| Check | Command | Result |
|---|---|---|
| Flutter analyze | `cd flutter_client && flutter analyze` (Flutter 3.47.9) | Pass, no issues |
| Flutter tests | `flutter test` | Pass, 309 tests |
| Deno unit suite | `deno test --allow-all --import-map=scripts/agent/deno_import_map.json --node-modules-dir=none --no-check supabase/tests/` | Pass, 637 passed / 0 failed |
| Deno strict check, all deployed entrypoints | `deno check … supabase/functions/*/index.ts` | **Fail, 33 errors** (legacy only: guardian-demo-create 25, legacy Guardian notifications 7 + guardian-notify, legacy forecast 2) — advisory in CI |
| Fresh migrations | `scripts/dev/local-db/run.sh` (PostgreSQL 16 + PostGIS 3.4 + pg_cron, no Docker) | Pass, 61/61 |
| SQL/RLS tests | same script | Pass, 13/13 |
| GitHub Actions on main | Tests workflow, run 44974082299 | Success (incl. migrations job) |
| Android release APK | android.yml in CI | Not re-run locally (CI artifact «android-latest» exists) |
| iOS | — | Not available (no target, no macOS) |

After PR #109: 62 migrations, 14 SQL tests (new security_definer_privileges.sql), all pass.
After PR #111 (independent of #109): 62 migrations, 15 SQL tests (new retired_guardian_v0.sql); Deno
579 passed / 0 failed with the CI command; full deno check 0 errors and blocking in CI.

## SEC-003 verification — 2026-11-22, Codex runtime, branch `codex/sec-003-rate-limit-fail-closed`

| Check | Result |
|---|---|
| `deno test --allow-all --node-modules-dir=none --no-check supabase/tests/rate-limit.test.ts` | Pass, 7/7 |
| `deno check` for shared rate limiter, v1 HTTP layer, regions, catalog and regression test | Pass |
| `deno lint --rules-exclude=no-import-prefix` for all six changed TypeScript files | Pass |
| `deno check supabase/functions/picks/index.ts` | Blocked before checking by denied `jsr.io` access for the existing `djwt` dependency; CI remains authoritative |
| `git diff --check` | Pass |

The regression coverage includes PostgREST array results, 429 decisions, resolved and rejected RPC
failures, malformed counter data, absence of the non-atomic fallback, and retryable 503 responses.

## SEC-004 verification — 2026-11-22, Codex runtime, branch `codex/sec-004-edge-jwt-matrix`

| Check | Result |
|---|---|
| `node --test scripts/ci/check-edge-auth-matrix.test.mjs` | Pass, 4/4 negative/positive tests |
| `node scripts/ci/check-edge-auth-matrix.mjs` | Pass: 17 deployed functions, 7 explicit JWT bypasses |
| YAML parse for deploy, test and smoke workflows | Pass |
| Supabase CLI config load | Parsed function config; then stopped as expected because the local Supabase container is not running |
| Production gateway smoke | Not run; added to manual smoke workflow for post-merge/deploy verification (BLK-007) |
| `git diff --check` | Pass |

The CI guard fails for an unclassified directory, a stale matrix entry, an unsupported auth class, config
drift, or a user/service function with gateway JWT verification disabled. Existing Deno handler tests cover
missing/invalid user tokens, exact service-role checks and webhook-secret rejection; blocking CI reruns them.

## Coverage assessment

The repository has broad unit coverage for domain calculations, API handlers, Flutter repositories, routing, safety, map, forecast, catalog, recognition, profile, friends, and Guardian logic. Current gaps are more important than raw test counts:

- deployed gateway behavior cannot be verified before merge without a staging Supabase project
- UI rendering across text scale and compact screens is unverified
- Android release and iOS builds are unverified
- end-to-end auth, location permission, offline queue, and notification delivery need environment-backed tests

## Next quality gate

- SEC-004 must pass blocking CI and the post-deploy gateway smoke test.
- UI-001 adds compact-screen / large-text / reduced-motion widget tests.
- Record test counts, failures, skips and artifacts per run in PROGRESS.md; never report a partial run as green.
