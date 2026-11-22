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

## Coverage assessment

The repository has broad unit coverage for domain calculations, API handlers, Flutter repositories, routing, safety, map, forecast, catalog, recognition, profile, friends, and Guardian logic. Current gaps are more important than raw test counts:

- deployed legacy Edge Functions are outside blocking type checks
- authorization tests are not organized as a complete endpoint matrix
- no current fresh-database result is available
- UI rendering across text scale and compact screens is unverified
- Android release and iOS builds are unverified
- end-to-end auth, location permission, offline queue, and notification delivery need environment-backed tests

## Next quality gate

Restore Deno and Flutter artifact access, then run the exact commands in test.yml and android.yml. Record test counts, failures, skips, and artifacts without summarizing a partial run as green.

