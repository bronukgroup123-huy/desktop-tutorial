# Autonomous cycle — runbook

Owner absence: 2026-11-22 → about 2026-12-22. The owner asked for controlled autonomous work
(master prompt of 2026-11-22). This file is what every scheduled run executes. State lives in Git
(this directory on branch `claude/agent-state`, task branches, PRs), never only in session memory.

## Mechanism

- Executor: the Claude Code cloud session that set this up. A scheduled task delivers the message
«Автономний цикл: виконай docs/agent/AUTONOMY.md» into that session every 4 hours
(scheduled task id: see «Schedule» below). A message that arrives while a run is still working waits
for it to finish, so Claude runs never overlap.
- If the container was replaced, tools are restored by `scripts/agent/bootstrap.sh` (Deno, Flutter
  3.47.9, PostGIS + pg_cron). Scratchpad paths are not durable.
- The Codex workflow `.github/workflows/codex-autonomy.yml` owns security/backend/CI work and uses the
  collision rules in `WORK_OWNERSHIP.md`. Claude owns product/UI work. Treat `docs/agent/*` as read-only
  for Claude; keep Claude's task state in `docs/tasks/*`, its task branches, PRs and scheduled session.

## Schedule

- Scheduled task: «Mushroom Radar — autonomous cycle», every 4 hours (id recorded in PROGRESS.md).
- End: the first run on or after 2026-12-22 writes the final report (PROGRESS.md «Final report») and
  disables the scheduled task. The owner can stop it any time from the scheduled tasks list.

## One run

1. **Date check.** On or after 2026-12-22 → final report, disable the schedule, stop.
2. **Tools.** Use existing Flutter/Deno if present, otherwise `scripts/agent/bootstrap.sh`, then
   `export PATH` from its output.
3. **Sync.** `git fetch origin`. Read `docs/agent/*` from `origin/main` for shared constraints, but do not
   edit it. Read product state from `docs/tasks/*`, the scheduled session and open `claude/*` PRs.
4. **Open agent PRs first.** List open PRs with head `claude/*`. For each: merged → mark the item done;
   CI red → fixing it is this run's task; review comments → address them. Do not open a new PR while one
   of ours is red.
5. **Pick one task.** Select the highest-priority product/UI item from `docs/tasks/*` whose dependencies are
   met and that needs no owner decision, secret, money or production access. Skip security/backend/CI items
   in `docs/agent/BACKLOG.md` and every area touched by open `codex/*` PRs.
6. **Branch.** `claude/<id>-<slug>` from `origin/main`. If it depends on an unmerged PR of ours, branch from
   that PR's branch and say so in the PR body.
7. **Implement** the smallest complete change. Bug and security fixes get a regression test that fails
   before the fix. No mass rewrites, no cosmetic churn, no new dependencies without need.
8. **Verify** what the change touches and record exact results:
   - Flutter: `cd flutter_client && flutter analyze && flutter test`
   - Deno: `deno test --allow-all --import-map=scripts/agent/deno_import_map.json --node-modules-dir=none --no-check supabase/tests/`
     and `deno check --import-map=scripts/agent/deno_import_map.json --node-modules-dir=none <changed entrypoints>`;
     afterwards `git checkout deno.lock`
   - Database: `scripts/dev/local-db/run.sh` (all migrations + SQL tests on a fresh local DB)
   - UI changes: rendered screenshots from a widget test (fonts loaded) before/after
9. **Commit, push, PR.** Commit trailer as in CLAUDE.md conventions; PR into `main`, never auto-merge.
   PR body (Ukrainian): problem, change, checks, deployment impact (merging `supabase/**` deploys to
   production via deploy.yml). Public repository: no exploitation details for unmerged security fixes.
10. **Record state** in `docs/tasks/*`, the task PR and scheduled session. Do not edit `docs/agent/*`; report
    a newly discovered backend/security blocker in the task PR for the next Codex run. Push the task branch.
11. **Stop.** One task per run. If the task is too big, split it in BACKLOG and finish the first part.

## Limits and failures

- Rate limit or exhausted usage: keep verified work committed, mark the item `blocked_rate_limit` or
  `paused` with time and message (no secrets), stop. The next scheduled run retries. Never loop retries.
- More than 10 open agent PRs: do not open new ones; fix CI, address reviews, or extend an open PR of the
  same area instead.
- Never: push to `main`, force-push someone else's branch, merge, deploy, touch production data, change
  secrets or settings, publish to stores, buy services, weaken ADRs/RLS/tests to get green CI.

## Product-run record template

Use this in the task PR or the relevant `docs/tasks/*` record:

```text
## YYYY-MM-DD HH:MM UTC — <task id>
- Branch / SHA: <branch> @ <sha>
- Done: …
- Checks: <command> → <result> (counts)
- Problems / residual risks: …
- PR: #<n>
- Next: <task id> — <goal>
- Blockers: …
```
