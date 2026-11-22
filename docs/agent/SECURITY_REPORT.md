# Security baseline

Date: 2026-11-22
Scope: repository source and CI configuration only. No production probing or secret inspection was performed.

## Confirmed critical findings

### Internal Guardian processors were callable without service authorization

The deployment disables platform JWT verification for all Edge Functions. Three internal processors created a service-role database client before authenticating the caller. The Telegram test endpoint also accepted any GET. SEC-001 adds a shared exact service-role bearer check, rejects missing configuration, and removes the test endpoint from deployment.

Current state: fixed in commit 072ed76185930c893e5a83ace8af68b58a9751a1, awaiting complete CI, PR review, and deployment.

### Administrative forest import RPC lacks privilege hardening

The source migration creates a SECURITY DEFINER import function without a fixed search path or revoked default execute privilege.

Current state: open as SEC-002. Production presence and grants are unverified.

## Confirmed high-risk weaknesses

- IP rate limiting fails open and has a non-atomic fallback.
- Every deployed function uses --no-verify-jwt, so one omitted handler guard exposes the endpoint.
- Blocking Deno type checking covers selected entrypoints. The all-function check is advisory.
- Android release can use the repository's public test key. It is suitable for testing only.
- The legacy Guardian notification schema does not declare the alert_id it reads.

## Privacy controls observed

- Public mushroom picks use server-derived display geometry while owners receive exact coordinates.
- Signed upload paths are bound to the authenticated user and the server rewrites final images after metadata validation.
- Guardian route details check owner or accepted Guardian membership.
- Friend profile responses intentionally omit coordinates, phone, email, points, and region.
- Local recognition is designed to keep recognition photos on-device.

These controls were reviewed statically. Database policy behavior and deployed endpoint responses remain to be tested on a disposable environment.

## Required negative tests

- anonymous and authenticated roles cannot call administrative RPCs
- a user cannot read another user's precise pick coordinates
- a non-Guardian cannot read route or last-location data
- blocked users disappear from search and profile access
- upload URLs cannot target another user's prefix or overwrite verified photos
- guests cannot create public picks, Guardian sessions, or SOS server events
- service jobs reject missing, anon, user, expired, and malformed bearer tokens

## Secret handling

No secret value was printed or copied. The repository contains a documented public test keystore. Real signing keys, service-role keys, webhook secrets, Firebase credentials, and OpenAI credentials must remain in secure CI or environment settings.
