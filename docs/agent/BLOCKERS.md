# Blockers and owner dependencies

## BLK-001 — GitHub API authentication

- Status: blocked
- Evidence: gh auth status reports that GH_TOKEN is invalid. Unauthenticated GitHub API requests return 403.
- Impact: branch protection, open PR state, CI status, and PR creation cannot be confirmed through the API.
- Owner action: restore a scoped GitHub connection with repository read/write and pull-request creation. Do not paste tokens into chat.
- Safe continuation: local branches, commits, tests, and read-only Git fetches remain available.

## BLK-002 — Deno dependency hosts

- Status: blocked
- Evidence: imports from deno.land and jsr.io fail with a denied CONNECT tunnel even after an escalated retry.
- Impact: full Deno type checking and unit suite cannot run.
- Owner action: publish the saved cloud network settings or allow deno.land, jsr.io, and esm.sh.
- Safe continuation: tests with only local imports can run.

## BLK-003 — Flutter SDK bootstrap

- Status: blocked
- Evidence: Flutter 3.47.9 source was cloned, but its pinned Dart SDK download from storage.googleapis.com returns 403.
- Impact: Flutter analyze, tests, golden rendering, Android build, and emulator checks cannot run locally.
- Owner action: allow the official Flutter artifact host or provide a cloud image with Flutter 3.47.9 preinstalled.

## BLK-004 — disposable Supabase database

- Status: blocked
- Evidence: the Supabase PostgreSQL image exhausted the Docker daemon's storage during extraction in this cloud runtime.
- Impact: fresh migrations and 13 SQL/RLS test scripts remain unverified locally.
- Owner action: use a runner with sufficient Docker storage. Production must not be used for destructive verification.

## BLK-005 — scheduled agent credentials and budget

- Status: waiting_owner
- Evidence: codex-autonomy.yml is disabled unless repository variable CODEX_AUTONOMY_ENABLED equals true. It requires OPENAI_API_KEY.
- Impact: autonomous continuation is prepared but not active or tested.
- Owner action: set an explicit budget, add the secret securely, enable the variable, and authorize one manual workflow run.
- Safety: the workflow has concurrency 1, a 55-minute timeout, opens PRs without auto-merge, and receives no production secrets.

## BLK-006 — iOS release infrastructure

- Status: blocked
- Evidence: no iOS target, macOS runner validation, Apple signing assets, bundle registration, or Apple Developer access is available.
- Impact: iOS readiness cannot be claimed.
- Owner action: provide Apple identifiers and signing through secure CI settings after the source target is prepared.

