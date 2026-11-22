# 30-day engineering roadmap

This roadmap is risk-driven. Each run selects one unblocked item from BACKLOG.md, uses a dedicated branch, opens a PR without auto-merge, and records exact evidence.

## Phase 1 — control and baseline, days 1–4

- Complete Edge Function authorization inventory.
- Make full Deno checks reproducible.
- Run Flutter analyze and tests on pinned Flutter 3.47.9.
- Run all migrations and SQL/RLS tests on a fresh disposable database.
- Establish the disabled-by-default scheduled Codex workflow and test one manual run after the owner supplies a budget and secret.
- Confirm branch protection and required checks for main.

Exit criteria: baseline commands are reproducible, blockers are explicit, and every deployed endpoint has an authentication classification.

## Phase 2 — security and correctness, days 5–13

- Close unauthenticated service and webhook paths.
- Harden SECURITY DEFINER functions and role grants.
- Add negative IDOR/BOLA tests for picks, friends, Guardian routes, profiles, and private coordinates.
- Replace fail-open rate limiting for mutating operations.
- Expand blocking type checks to every deployed Edge Function.
- Verify storage policies, signed upload ownership, replay behavior, and deletion paths.

Exit criteria: no unresolved confirmed critical finding, security tests run on a fresh database, and production changes remain behind reviewed PRs.

## Phase 3 — Flutter reliability and UI quality, days 14–22

- Validate auth, onboarding, profile, map, forecast, recognition, analysis, picks, friends, and Guardian flows.
- Audit provider lifecycles, cancellation, polling, timers, and background location.
- Add compact-screen, large-text, reduced-motion, offline, loading, empty, and error-state tests.
- Consolidate design tokens only where current screens demonstrably diverge.
- Measure image, map, list, ONNX, memory, and rebuild hotspots before optimization.

Exit criteria: critical user journeys have regression coverage and UI changes have rendered evidence.

## Phase 4 — release readiness, days 23–30

- Require real signing inputs for store Android artifacts.
- Validate debug and release Android builds and Play requirements.
- Generate and review iOS target, permissions, deep links, entitlements, Firebase, and macOS CI.
- Run end-to-end regression and publish a final residual-risk report.

Exit criteria: Android release candidate is reproducible, iOS preparation is explicit, and remaining owner actions are documented.

## Control rules

- Never merge automatically.
- Never run migrations against production from an agent branch.
- Never publish to stores or buy services.
- Stop on rate limits and record paused or blocked_rate_limit.
- One scheduled job at a time through GitHub Actions concurrency.
- Secrets are supplied only through repository or environment settings.

