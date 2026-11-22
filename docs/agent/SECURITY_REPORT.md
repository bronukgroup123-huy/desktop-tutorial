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

Current state: fixed in PR #109 (migration + regression test that fails CI for any future SECURITY DEFINER
function reachable by API roles or without search_path). Effective after merge and deployment.

## Confirmed high-risk weaknesses

- Legacy Guardian v0 endpoints (14), their cron processors and an unauthenticated demo endpoint are still
  deployed although ADR-022 replaced them and no client uses them (SEC-005).
- A public weather proxy accepts arbitrary coordinates without token or rate limit (SEC-005 retires it).

- IP rate limiting fails open and has a non-atomic fallback.
- Every deployed function uses --no-verify-jwt, so one omitted handler guard exposes the endpoint.
- Blocking Deno type checking covers selected entrypoints. The all-function check is advisory.
- Android release can use the repository's public test key. It is suitable for testing only.
- The legacy Guardian notification schema does not declare the alert_id it reads (removed with SEC-005).

## Edge Function authentication matrix (second pass, 2026-11-22)

| Class | Functions |
|---|---|
| User JWT via `requireUser` (v1 http layer) | v1-me, v1-picks, v1-regions, v1-forecast, v1-analysis, v1-forest-zones, v1-friends, v1-guardian, v1-air-alerts, v1-app-config, v1-wave-alerts |
| Service role (exact bearer) | v1-guardian-tick, guardian-tick, guardian-notify, guardian-retry |
| Webhook secret | v1-telegram-webhook |
| User JWT, legacy Guardian v0 (unused, ADR-022) | guardian-active, -cancel-close, -close, -exiting, -extend, -owner-gpx, -ping, -recover, -register-device, -revoke, -session-create, -sos, -sos-cancel |
| Legacy, partly public | me, picks (public read + JWT for own), regions, catalog (IP-limited public reads) |
| **Public, no auth** | forecast (IP-limited), **forecast-weather (no limit)**, **guardian-demo-create (writes rows)** |
| Not deployed | guardian-notify-test, test-telegram |

Platform JWT verification is off for all (`--no-verify-jwt`); SEC-004 makes it the default with an allowlist.

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

These controls were reviewed statically. Database policy behavior and deployed endpoint responses remain to be tested on a disposable environment.

## Required negative tests

- anonymous and authenticated roles cannot call administrative RPCs — covered by security_definer_privileges.sql (PR #109)
- a user cannot read another user's precise pick coordinates
- a non-Guardian cannot read route or last-location data
- blocked users disappear from search and profile access
- upload URLs cannot target another user's prefix or overwrite verified photos
- guests cannot create public picks, Guardian sessions, or SOS server events
- service jobs reject missing, anon, user, expired, and malformed bearer tokens

## Secret handling

No secret value was printed or copied. The repository contains a documented public test keystore. Real signing keys, service-role keys, webhook secrets, Firebase credentials, and OpenAI credentials must remain in secure CI or environment settings.
