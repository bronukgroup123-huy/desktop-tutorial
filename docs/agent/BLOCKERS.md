# Blockers and owner dependencies

Updated 2026-11-22 (second pass). Items marked «owner» need the owner; the agent continues with other work.

## BLK-001 — GitHub API authentication in the Codex runtime
- Status: not blocking the Claude cycle. The Claude runtime reads PRs/CI and opens PRs through its GitHub
  connection. Codex can fetch and push through the platform HTTPS proxy, but GitHub GraphQL PR creation
  still returns `403 Forbidden`; pushed branches expose a compare URL. Owner action is optional: create the
  PR from that URL, or provide Codex an approved GitHub API integration if direct PR creation is required.

## BLK-002 / BLK-003 / BLK-004 — Deno hosts, Flutter SDK, disposable database
- Status: resolved in the Claude runtime. Deno runs with scripts/agent/deno_import_map.json (deno.land is
  blocked, jsr/npm are not); Flutter 3.47.9 runs; all migrations and SQL tests run on local PostgreSQL 16 +
  PostGIS + pg_cron (scripts/dev/local-db/run.sh). A new container restores tools with
  scripts/agent/bootstrap.sh. The restored Codex instance still has an incomplete Flutter cache because
  `storage.googleapis.com` is denied. Onboarding draft revision 5 adds that domain plus tested-version setup
  instructions; the owner must Review/Save and Publish it before reproducibility can be validated in a new
  task. Node/Git work is not blocked.

## BLK-005 — Codex scheduled workflow credentials, budget and first-run verification (owner)
- Status: authorized_in_review. The owner authorized five-hour autonomous retries. AUT-001 removes the old
  repository-variable gate, limits the schedule to 2026-11-22…2026-12-22, and gives Codex and Claude
  disjoint files through `WORK_OWNERSHIP.md` plus a blocking collision guard.
- Still required: an `OPENAI_API_KEY` with an owner-defined budget/provider limit and the repository setting
  that lets GitHub Actions create pull requests. Never paste the key into chat. The workflow receives no
  Supabase, deployment, store-signing or other production secrets.
- Verification pending: after merge, observe one manual or scheduled run creating a review-only `codex/*`
  PR. Until that succeeds, persistent autonomy is prepared but not proven.

## BLK-006 — iOS release infrastructure (owner)
- Status: blocked. No iOS target, macOS runner, Apple signing or Apple Developer access.

## BLK-007 — no staging Supabase project (owner)
- Status: blocked. Security fixes are verified on a local fresh database and in CI, but deployed behavior
  (e.g. 401 on internal jobs) can only be checked after merge on production. A staging project with its own
  secrets would allow pre-merge verification.

## BLK-008 — merges and production deployment (owner)
- Status: by design. The agent never merges. Merging anything under supabase/** deploys to production via
  deploy.yml. Recommended merge order: PR #109 (SEC-002) first, then agent PRs in BACKLOG order; the
  agent-state PR (docs only) can be merged any time.

## BLK-009 — product/legal decisions before publication (owner)
- Open-Meteo commercial key, privacy policy and terms, Apple sign-in (BACKEND_PLAN §5.1).
- Retention of legacy Guardian v0 data tables after SEC-005 retires the endpoints.
- Whether anything outside this repository still hosts web-guardian (WEB-001).

## BLK-010 — device-level verification (owner)
- Status: blocked. FPS, memory, battery, background location, push delivery and OAuth on real Android
  devices need the owner's devices or a device farm. The agent measures what is possible in tests.

## BLK-011 — Android store signing identity (owner)
- Status: blocked until publication preparation. The manual store workflow requires
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
  `ANDROID_KEY_PASSWORD`. The public repository test key must never be reused as the Google Play identity.
