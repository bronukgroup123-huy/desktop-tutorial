# Blockers and owner dependencies

Updated 2026-11-22 (second pass). Items marked «owner» need the owner; the agent continues with other work.

## BLK-001 — GitHub API authentication in the Codex runtime
- Status: resolved in the 2026-11-24 interactive runtime. `gh auth status`, REST/GraphQL PR reads and Actions
  metadata reads succeed as `bronukgroup123-huy`. Recheck authentication in each fresh runtime; this does not
  authorize merges, production changes or direct pushes to `main`.

## BLK-002 / BLK-003 / BLK-004 — Deno hosts, Flutter SDK, disposable database
- Status: resolved in the Claude runtime. Deno runs with scripts/agent/deno_import_map.json (deno.land is
  blocked, jsr/npm are not); Flutter 3.47.9 runs; all migrations and SQL tests run on local PostgreSQL 16 +
  PostGIS + pg_cron (scripts/dev/local-db/run.sh). A new container restores tools with
  scripts/agent/bootstrap.sh. The restored Codex instance still has an incomplete Flutter cache because
  `storage.googleapis.com` is denied. Onboarding draft revision 5 adds that domain plus tested-version setup
  instructions; the owner must Review/Save and Publish it before reproducibility can be validated in a new
  task. Node/Git work is not blocked.

## BLK-005 — Codex API automation paused by owner
- Status: paused_owner_choice (2026-11-22). The owner will use Codex only in this interactive environment
  for now and will not use the Codex API.
- Effect: do not merge or activate `codex/aut-001-five-hour-cycle`, request an API key, or claim five-hour
  Codex continuation. Interactive work resumes only after the owner sends a new message such as «Продовжуй».
- Reopening: requires a future explicit owner decision plus budget/limit and first-run verification.

## BLK-006 — iOS release infrastructure (owner)
- Status: blocked. No iOS target, macOS runner, Apple signing or Apple Developer access.

## BLK-007 — no staging Supabase project (owner)
- Status: blocked. Security fixes are verified on a local fresh database and in CI, but deployed behavior
  (e.g. 401 on internal jobs) can only be checked after merge on production. A staging project with its own
  secrets would allow pre-merge verification.

## BLK-008 — merges and production deployment (owner)
- Status: by design. The agent never merges. Merging anything under supabase/** deploys to production via
  deploy.yml. PRs #108–115 and #117–119 are merged. PR #116 is the only open agent-authored PR, is docs-only,
  conflicts with `main`, and contains statuses superseded by those merges; do not merge it unchanged.

## BLK-009 — product/legal decisions before publication (owner)
- Open-Meteo commercial key, privacy policy and terms, Apple sign-in (BACKEND_PLAN §5.1).
- Retention of legacy Guardian v0 data tables after SEC-005 retires the endpoints.
- WEB-001 resolved 2026-11-26: owner removed Vercel; web-guardian deleted. Remaining owner action: Supabase Auth
  Site URL → `ua.mushroomradar.app://login-callback/` (dashboard; config.toml is not pushed).
- Privacy policy needs a public URL for Google Play (no web host now; GitHub Pages is a free option).

## BLK-010 — device-level verification (owner)
- Status: blocked. FPS, memory, battery, background location, push delivery and OAuth on real Android
  devices need the owner's devices or a device farm. The agent measures what is possible in tests.

## BLK-011 — Android store signing identity (owner)
- Status: blocked until publication preparation. The manual store workflow requires
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
  `ANDROID_KEY_PASSWORD`. The public repository test key must never be reused as the Google Play identity.

## BLK-012 — Claude scheduled cycle outage and policy confirmation (owner)
- 2026-11-22 12:35 → 2026-11-25 00:35 UTC: the Claude session worker kept restarting, so 15 scheduled runs
  queued and none executed. On 2026-11-25 the backlog was processed as one run (no catch-up burst).
- The backlog header (PR #120) now says work is manual/interactive; AUT-001 records that choice for Codex.
  The Claude cycle still follows the owner's master prompt of 2026-11-22 and AUTONOMY.md. Owner: if the Claude
  cycle should stop too, disable the scheduled task «Mushroom Radar — autonomous cycle» (or say so in a PR);
  the agent will then only work after owner messages.

## BLK-013 — B3.10 knowledge tests need a design session (owner) — RESOLVED 2026-11-26
- Resolved: designed with the owner, recorded as ADR-023; work proceeds module by module, each read by the owner.
- Owner (2026-11-26): B3.10 must be discussed and worked out in detail before implementation.
- Needed from the owner: modules and question sources, pass rules, retakes, what the certificate unlocks.
- The agent does not start B3.10 until then.
