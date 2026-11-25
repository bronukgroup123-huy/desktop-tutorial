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

## SEC-006 verification — 2026-11-22, Codex runtime, branch `codex/sec-006-private-data-idor-tests`

| Check | Result |
|---|---|
| PostgreSQL 16 bootstrap + `20260912000012_storage_picks.sql` + `rls_storage_picks.sql` | Pass: owner isolation, foreign/server-only write denial and anon denial |
| Targeted picks/Guardian/friends/trophies Deno tests | Blocked before execution: configured `jsr.io` registry manifest could not be loaded in this runtime |
| Full `supabase db start` migration suite | Blocked locally: `public.ecr.aws` returned 403; the exact Docker Hub mirror exceeded the rootless VFS extraction quota |
| `git diff --check` | Pass |

The new SQL script is the missing storage-policy boundary test. The existing handler and RLS files cover the
other SEC-006 domains; blocking PR CI remains authoritative for the full 63-migration / 16-SQL-script run
and the complete Deno regression suite.

## AND-001 verification — 2026-11-22, Codex runtime, branch `codex/and-001-store-release-signing`

| Check | Result |
|---|---|
| `node --test scripts/ci/check-android-signing.test.mjs` | Pass, 6/6 |
| `node scripts/ci/check-android-signing.mjs` | Pass: test APK isolated; all four store secrets required |
| Existing Edge auth guard | Pass, 4/4 tests and 17-function matrix |
| YAML parse for `android.yml`, `android-store.yml`, `test.yml` | Pass |
| Bash syntax for every `run` block in the three workflows | Pass |
| `git diff --check` | Pass |
| Flutter/Gradle configuration and Android build | Blocked locally: the restored Flutter checkout lacks its Dart SDK and `storage.googleapis.com` returns 403; PR Android CI remains authoritative |

Negative tests prove that automatic store triggers, store secrets in the test workflow, a disabled Gradle
guard, empty signing inputs and partial Gradle signing configuration are rejected. The manual store workflow
uploads an AAB for owner review only; it never publishes to Google Play.

## QA-003 verification — 2026-11-22, Codex runtime, branch `codex/qa-003-openapi-model-contract`

| Check | Result |
|---|---|
| `node --test scripts/ci/check-flutter-openapi-models.test.mjs` | Pass, 5/5 positive and negative tests |
| `node scripts/ci/check-flutter-openapi-models.mjs` | Pass, 18 core model bindings checked |
| Existing Android signing guard | Pass, 6/6 tests and repository check |
| Existing Edge auth guard | Pass, 4/4 tests and 17-function matrix |
| PyYAML parse of `openapi/v1.yaml` and `test.yml` | Pass, OpenAPI 3.1.0 with 32 schemas; 3 workflow jobs |
| `git diff --check` | Pass |
| Flutter analyze/model tests | Not rerun locally: restored Flutter SDK lacks Dart artifacts; blocking PR CI remains authoritative |

The guard checks two high-value top-level invariants: every required OpenAPI field is consumed by its bound
Flutter model, and every top-level JSON key consumed by that model is documented. It deliberately does not
claim full nested type, enum or nullability equivalence. The initial red run exposed real analysis weather
contract drift before `openapi/v1.yaml` was aligned with the implemented server and Flutter client.

## CI-001 verification — 2026-11-22, Codex runtime, branch `codex/ci-001-workflow-permissions`

| Check | Result |
|---|---|
| `node --test scripts/ci/check-workflow-permissions.test.mjs` | Pass, 7/7 positive and negative tests |
| `node scripts/ci/check-workflow-permissions.mjs` | Pass: 17 explicit workflows, 4 reviewed write-scoped |
| PyYAML parse of deploy, smoke and test workflows | Pass |
| Bash syntax for all `run` blocks in those workflows | Pass, 26/26 blocks |
| Existing OpenAPI, Android signing and Edge auth guards | Pass, 5/5 + 6/6 + 4/4 |
| `git diff --check` | Pass |
| Production smoke/deploy | Not run; agent branches must not mutate or probe production |

The guard rejects missing top-level permissions, unreviewed write scopes, deploy/smoke repository writes,
unmasked dynamic credentials and production secrets inherited by third-party action steps. This verifies
repository configuration, not the unobservable repository-default permission setting or a live deployment.

## CI-002 verification — 2026-11-25, Codex runtime, branch `codex/ci-002-data-workflows`

| Check | Result |
|---|---|
| `node --test scripts/ci/check-workflow-permissions.test.mjs` | Pass, 11/11 combined CI-002 and OPS-001 positive/negative tests |
| `node scripts/ci/check-workflow-permissions.mjs` | Pass: 17 explicit workflows, 4 reviewed top-level write scopes |
| `actionlint` v1.7.12 | Pass, all repository workflows |
| Forest generator tests and type checks | Pass, 11/11 tests; `build_all.ts` and `build_region.ts` checked |
| Trails generator tests and type checks | Pass, 5/5 tests; `build_region.ts` and `regions_config.ts` checked |
| Forest-type Python compile check | Pass, `s2_leaf_type.py` and `zonal.py` |
| `git diff --check` | Pass |
| Scheduled/manual data builds and release publication | Not run; this branch must not publish or mutate production data |

The data workflows keep fast checks available to every PR, while secret-dependent, production-API and
large-download jobs are limited to schedules and manual runs. Release writes
are separated from the forests and forest-type build jobs, and Supabase credentials are no longer inherited
at workflow scope. Fast artifact smoke steps exercise artifact action upgrades without downloading the
Ukraine OSM extract.

## Coverage assessment

The repository has broad unit coverage for domain calculations, API handlers, Flutter repositories, routing, safety, map, forecast, catalog, recognition, profile, friends, and Guardian logic. Current gaps are more important than raw test counts:

- deployed gateway behavior cannot be verified before merge without a staging Supabase project
- UI rendering across text scale and compact screens is unverified
- Android release and iOS builds are unverified
- end-to-end auth, location permission, offline queue, and notification delivery need environment-backed tests

## Next quality gate

- PR #113 still needs the post-deploy gateway smoke test when staging is available.
- CI-001 must pass blocking PR CI; no production workflow is triggered by this branch.
- QA-003 is merged as PR #118 and its model guard is blocking.
- AND-001 is merged as PR #117; a real-key manual AAB build remains an owner step.
- UI-001 is merged as PR #115; device-level accessibility remains under BLK-010.
- Record test counts, failures, skips and artifacts per run in PROGRESS.md; never report a partial run as green.

## OPS-001 verification — 2026-11-24, Codex runtime

| Check | Result |
|---|---|
| `node --test scripts/ci/run-wave-alerts.test.mjs` | Pass, 8/8: headers, fail-closed config/key lookup, safe diagnostics, command-injection rejection and response validation |
| `node --test scripts/ci/check-workflow-permissions.test.mjs` | Pass, 8/8 |
| `node scripts/ci/check-workflow-permissions.mjs` | Pass: 17 explicit workflows, four reviewed write-scoped |
| Node syntax + workflow YAML parse | Pass |
| Guard against the pre-fix `main` workflow | Expected failure: guarded runner/project-ref requirements absent |
| `git diff --check` | Pass |
| Live scheduled invocation | Not run: it would call production and is outside an agent branch |

The PR CI must rerun the full Deno, Flutter and migration gates. After merge, the next scheduled or explicitly
owner-authorized manual run must confirm the live Edge Function returns a valid count payload.
