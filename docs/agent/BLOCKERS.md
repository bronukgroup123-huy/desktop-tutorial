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

## BLK-014 — B3.12 reports on picks: who confirms a report? (owner)
- Status: blocked (2026-11-28). ADR-018 §18.4 layer 3 says «скарга → повторна перевірка; підтверджена скарга −50
  автору», but the reviewer group that would re-check was abolished by ADR-019 §19.5. Nobody can confirm a report,
  so the −50 cannot be applied fairly, and an automatic −50 would let a few people punish anyone.
- Options:
  1. **Recommended:** reports only hide. N independent reports (e.g. 3 from different accounts, Лісовик+, not friends
     of each other) hide the public pick from the map at once (it stays private for the author, who is told why).
     The −50 is applied only when the owner confirms the report (SQL / later an admin screen); unconfirmed after
     30 days — the pick returns and nothing is deducted.
  2. Automatic −50 after N reports, no human — fastest, but abusable by a group.
  3. Leave B3.12 until there is a moderator (the «Поскаржитися» on answers/messages stays as now).
- Needed from the owner: pick an option (and N), and who moderates (only the owner for now?).

## BLK-015 — B9.6 «спори»: nothing to spend them on after the avatar constructor was removed (owner)
- Status: blocked (2026-11-28). ADR-021 §21.6 prices spores mostly in avatar details and avatar animations, but
  §21.7 (PO 2026-11-21) removed the constructor: avatars are 40 ready pictures unlocked by level only («Pro / спори —
  поки ні»). The only remaining sink is gift stickers, and their art (simple / animated / scene) does not exist yet.
  Rule «спершу ціни, потім нарахування» (PO 2026-11-17) means accruals should not start before something is buyable.
- Options:
  1. **Recommended:** spores buy gift stickers only (10 / 40 / 80) — start with a small set of static gift stickers
     (owner draws ~12, prompts can be prepared like the passport stickers), animated ones later; accruals start with
     the shop; avatar items removed from the price table.
  2. Sell extra avatars outside the level ladder (e.g. seasonal, 60–120) — keeps «level avatars are not for sale».
  3. Avatar frame effects / animations (sleep, dance, sneeze) on the ready pictures — needs animation work per avatar.
  4. Postpone B9.6 entirely; profile keeps «Подарунки — скоро».
- Needed from the owner: what spores buy at launch, and whether to prepare prompts for the gift sticker set.

## BLK-016 — B2.5 forest summary: show the 7-day count of verified picks? (owner)
- Status: open question (2026-11-28); the rest of B2.5 is ready. The plan row includes «кількість verified-тук-туків
  за 7 днів» for the tapped forest. That is the same «go here, everyone» signal the owner rejected for the heatmap
  (ADR-010 §10.7: crowds, lag, discourages people from adding points).
- Options:
  1. **Recommended:** drop the count; the summary shows forest type, age, area, source and the top 1–2 species of the
     forecast (no community data).
  2. Keep only a coarse word («були знахідки цього тижня» / nothing) with a minimum threshold.
  3. Keep the count as planned.
- Needed from the owner: pick an option. Until then B2.5 is not started (it would ship with or without the field).
