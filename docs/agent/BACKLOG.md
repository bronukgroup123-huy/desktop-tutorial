# Prioritized engineering backlog

## SEC-001 — protect internal Guardian jobs

- Priority: P0
- Goal: require service-role authorization for internal Guardian processors and remove the test Telegram endpoint from production deployment.
- Scope: Guardian tick, notify, retry, Telegram test endpoint, deployment loop, negative unit test.
- Acceptance criteria: missing or malformed bearer tokens are rejected, exact service-role token is accepted, the test endpoint is excluded and scheduled for deletion.
- Tests: targeted service-auth test, full Deno suite, staging HTTP 401 checks.
- Status: implemented, awaiting PR and complete CI.
- Commit: 072ed76185930c893e5a83ace8af68b58a9751a1
- PR: blocked until GitHub authentication is restored.
- Residual risks: production behavior is unchanged until reviewed and deployed. Full Deno suite and staging checks are pending.

## SEC-002 — harden administrative forest import RPC

- Priority: P0
- Goal: prevent API roles from invoking import_forest_zones_batch.
- Scope: one migration and one SQL privilege regression test.
- Acceptance criteria: empty fixed search path, schema-qualified objects, execute denied to PUBLIC, anon, and authenticated, execute granted to service_role.
- Tests: fresh migration run and has_function_privilege assertions.
- Status: ready
- PR: pending
- Residual risks: live database grants remain unknown until migration deployment is reviewed.

## SEC-003 — eliminate fail-open rate limiting

- Priority: P0
- Goal: preserve abuse protection when the counter RPC fails.
- Scope: shared IP limiter and failure-path tests.
- Acceptance criteria: mutating and notification endpoints fail closed, public read endpoints have a documented degradation policy, no non-atomic counter reset.
- Tests: RPC failure, storage failure, concurrency, and 429 response tests.
- Status: ready
- PR: pending
- Residual risks: database availability can affect public reads depending on the chosen policy.

## SEC-004 — Edge Function authentication matrix

- Priority: P0
- Goal: classify all 38 deployed function directories and make JWT verification the default.
- Scope: deployment allowlist, endpoint guards, webhook secrets, cron callers, authorization tests.
- Acceptance criteria: each endpoint is marked public, user JWT, service role, or webhook secret. Missing and wrong credentials have negative tests.
- Tests: Deno handler tests and staging requests.
- Status: ready
- PR: pending
- Residual risks: legacy consumers must be identified before platform verification is enabled.

## QA-001 — reproducible full baseline

- Priority: P0
- Goal: run Flutter, Deno, migrations, SQL/RLS, Android, and API checks.
- Scope: CI and environment setup only.
- Acceptance criteria: every required command has a current pass/fail result and logs identify real test counts.
- Tests: CI commands from test.yml and android.yml.
- Status: blocked_environment
- PR: pending
- Residual risks: local failures may differ from GitHub-hosted runners.

## AUT-001 — controlled scheduled continuation

- Priority: P0
- Goal: allow one bounded Codex run on a schedule and persist results through Git and PRs.
- Scope: disabled-by-default GitHub workflow, agent prompt, concurrency, timeout, budget and secret gate.
- Acceptance criteria: owner enables the repository variable, provides the API key and budget, a manual run opens one PR, and a subsequent run reads the persisted state.
- Tests: workflow syntax plus one owner-authorized manual run.
- Status: prepared_disabled
- PR: pending
- Residual risks: untested until credentials and budget are supplied.

## QA-002 — make all deployed Deno entrypoints blocking

- Priority: P1
- Goal: remove the continue-on-error gap for deployed Edge Functions.
- Scope: fix errors in bounded groups and update CI.
- Acceptance criteria: all deployed entrypoints pass blocking deno check.
- Tests: exact CI check.
- Status: ready
- PR: pending
- Residual risks: legacy errors may require several PRs.

## AND-001 — separate test APK from store release

- Priority: P1
- Goal: prevent store-labelled artifacts from using the public test key.
- Scope: Android workflow and release documentation.
- Acceptance criteria: testing APK remains available, store release fails without complete signing secrets, signing certificate fingerprint is recorded securely.
- Tests: CI with and without release signing inputs.
- Status: ready
- PR: pending
- Residual risks: owner must control the long-term signing key.

## IOS-001 — create and validate iOS target

- Priority: P1
- Goal: prepare iOS source, permissions, deep links, Firebase, and CI.
- Scope: Flutter iOS target and macOS workflow.
- Acceptance criteria: static analysis passes and an unsigned simulator build succeeds on macOS.
- Tests: flutter analyze, flutter test, and iOS simulator build.
- Status: blocked_macos_and_apple_configuration
- PR: pending
- Residual risks: device, push, OAuth, and store signing need owner accounts and Apple infrastructure.

## UI-001 — accessibility and responsive baseline

- Priority: P1
- Goal: verify all primary screens under compact size, large text, and reduced motion.
- Scope: widget and golden tests plus documented screenshots before visual changes.
- Acceptance criteria: no overflow in critical actions, semantic labels exist, motion respects system settings.
- Tests: widget tests at representative constraints and golden diffs.
- Status: blocked_flutter_runtime
- PR: pending
- Residual risks: device-specific rendering requires emulator or hardware validation.

