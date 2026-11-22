# Blockers and owner dependencies

Updated 2026-11-22 (second pass). Items marked «owner» need the owner; the agent continues with other work.

## BLK-001 — GitHub API authentication in the Codex runtime
- Status: not blocking the Claude cycle. The Claude runtime reads PRs/CI and opens PRs through its GitHub
  connection. Codex still has an invalid GH_TOKEN (owner: replace with a fine-grained PAT if Codex should
  open PRs itself).

## BLK-002 / BLK-003 / BLK-004 — Deno hosts, Flutter SDK, disposable database
- Status: resolved in the Claude runtime. Deno runs with scripts/agent/deno_import_map.json (deno.land is
  blocked, jsr/npm are not); Flutter 3.47.9 runs; all migrations and SQL tests run on local PostgreSQL 16 +
  PostGIS + pg_cron (scripts/dev/local-db/run.sh). A new container restores tools with
  scripts/agent/bootstrap.sh (the Flutter step mirrors the original manual install and is not yet exercised
  by the script).

## BLK-005 — Codex scheduled workflow (owner, optional)
- Status: prepared_disabled. Needs OPENAI_API_KEY (billed separately from a ChatGPT subscription), repository
  variable CODEX_AUTONOMY_ENABLED=true and «Allow GitHub Actions to create and approve pull requests».
  Do not enable it while the Claude cycle runs, or give the two agents disjoint areas first.

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
