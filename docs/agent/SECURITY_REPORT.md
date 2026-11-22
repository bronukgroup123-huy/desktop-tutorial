# Security baseline

Date: 2026-11-22 (updated by the second pass)
Scope: repository source, CI configuration and a fresh local database with all migrations. No production
probing or secret inspection was performed. The repository is public: this report names components and
fixes, not exploitation steps.

## Confirmed critical findings

### Internal Guardian processors were callable without service authorization

The deployment disables platform JWT verification for all Edge Functions. Three internal processors created a service-role database client before authenticating the caller. The Telegram test endpoint also accepted any GET. SEC-001 adds a shared exact service-role bearer check, rejects missing configuration, and removes the test endpoint from deployment.

Current state: merged in PR #108; takes effect after deployment. Staging verification pending (no staging project).

### SECURITY DEFINER functions executable by API roles

Verified on a fresh database: the global PUBLIC EXECUTE default left eight SECURITY DEFINER functions
executable by anon and authenticated, including the administrative forest import (no fixed search path) and
four PostGIS lookups that bypass Edge Function rate limits.

Current state: fixed and merged in PR #109 (migration + regression test that fails CI for any future
SECURITY DEFINER function reachable by API roles or without search_path). Staging verification remains
blocked by BLK-007.

## Confirmed high-risk weaknesses

- Legacy Guardian v0, demo, weather proxy and legacy forecast sources were retired in merged PR #111.
  Legacy data tables remain until the owner decides their retention policy (BLK-009).
- IP rate limiting failed open and used a non-atomic fallback. Fixed in merged PR #112: the fallback is
  removed, RPC results are validated, and public reads and mutations return retryable 503 when the counter
  cannot decide. Deployed behavior remains unverified without staging.
- The global `--no-verify-jwt` deployment policy was removed in merged PR #113. A machine-readable matrix
  makes platform JWT verification the default; CI rejects any new or renamed function until it is
  classified. Deployed smoke tests remain pending without staging.
- Full Deno type checking is blocking after merged PR #111.
- Android release can use the repository's public test key. It is suitable for testing only.

## Edge Function authentication matrix (second pass, 2026-11-22)

| Class | Functions |
|---|---|
| Platform JWT + user/session verification | me, v1-analysis, v1-forecast, v1-forest-zones, v1-friends, v1-guardian, v1-me, v1-picks |
| Platform JWT + exact service-role bearer | v1-guardian-tick, v1-wave-alerts |
| Public, no bearer required | catalog, regions, v1-air-alerts, v1-app-config, v1-regions |
| Mixed public read + handler auth for mutation | picks |
| Webhook secret (gateway JWT bypass) | v1-telegram-webhook |
| Not deployed / retired | Guardian v0 functions, guardian demo, legacy forecast/weather proxy, guardian-notify-test, test-telegram |

Supabase Anonymous Sign-In produces a valid user JWT, so guest flows continue through `user_jwt` endpoints.
Handler-level `assertRegistered` remains responsible for operations forbidden to guests by ADR-001.

## Database privileges (verified on a fresh database)

- No table or view in `public` is reachable by API roles without RLS; all views use security_invoker.
- After PR #109 no SECURITY DEFINER function is executable by anon/authenticated.
- Two SECURITY INVOKER helpers (get_gdd_state, upsert_gdd_state) remain executable by anon; RLS allows read
  only, writes fail. Low risk; clean up with SEC-005 if unused.

## Privacy controls observed

- Public mushroom picks use server-derived display geometry while owners receive exact coordinates.
- Signed upload paths are bound to the authenticated user and the server rewrites final images after metadata validation.
- Guardian route details check owner or accepted Guardian membership.
- Friend profile responses intentionally omit coordinates, phone, email, points, and region.
- Local recognition is designed to keep recognition photos on-device.

The repository's existing Deno and SQL suites exercise foreign pick IDs, precise-coordinate isolation,
private picks, Guardian tracks, friendships and trophies. SEC-006 adds the previously missing direct storage
RLS test for two authenticated users, anon and the server-only final-photo prefix. Deployed endpoint
responses remain unverified without staging.

## Required negative tests

- anonymous and authenticated roles cannot call administrative RPCs — covered by security_definer_privileges.sql (PR #109)
- a user cannot read another user's precise pick coordinates — covered by `rls_picks_map.sql`,
  `rls_picks_adr018.sql` and `v1/picks-map.test.ts`
- a non-Guardian cannot read route or last-location data — covered by `rls_guardian_in_app.sql` and
  `v1/guardian.test.ts`
- blocked users disappear from search and profile access — covered by `rls_friends.sql` and
  `v1/friends.test.ts`
- upload URLs cannot target another user's prefix or overwrite verified photos — handler coverage in
  `v1/picks.test.ts`; direct storage RLS coverage added by `rls_storage_picks.sql` in SEC-006
- guests cannot create public picks, Guardian sessions, or SOS server events
- service jobs reject missing, anon, user, expired, and malformed bearer tokens

## Secret handling

No secret value was printed or copied. The repository contains a documented public test keystore. Real signing keys, service-role keys, webhook secrets, Firebase credentials, and OpenAI credentials must remain in secure CI or environment settings.
