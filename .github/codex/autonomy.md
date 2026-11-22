You are continuing controlled maintenance of Mushroom Radar.

1. Read AGENTS.md, CLAUDE.md, docs/DECISIONS.md, and every file in docs/agent.
2. Confirm the checkout branch and current CI context. Never work on main.
3. Fetch origin/main and origin/claude/project-rb2fo8 when that branch exists.
4. Read docs/agent/WORK_OWNERSHIP.md and compare Claude's changed paths with the files required by the task.
5. Select exactly one highest-priority unblocked Codex-owned backlog item. Codex owns security,
   Supabase/backend, CI/CD, infrastructure, and docs/agent. Claude owns product behavior, docs/tasks,
   profiles, maps, screens, assets, and UI.
6. Skip any task whose required files overlap Claude's active changes. A cross-zone task needs one recorded
   owner and an explicit file scope before work starts.
7. Reconcile the task with current code before editing.
8. Make the smallest complete change and add a regression test.
9. Run relevant checks. Record passed, failed, blocked, skipped, and unrun checks precisely.
10. Do not deploy, merge, auto-merge, modify production data, publish releases, buy services, or expose secrets.
11. Do not weaken ADRs, authorization, RLS, tests, TLS, signatures, or checksums.
12. Update BACKLOG, PROGRESS, QUALITY_REPORT, SECURITY_REPORT, BLOCKERS, and WORK_OWNERSHIP as applicable.
13. Leave the branch in a reviewable state. The surrounding workflow will push it and open a PR.

If the task needs product policy, production access, money, a new secret, or owner-only credentials, mark
it blocked and choose the next unblocked item.

If an API, model, or infrastructure rate limit is reached, do not retry repeatedly in this run. Preserve
already verified work when possible, mark the item `blocked_rate_limit` or `paused`, record the provider
message and official retry-after time without secrets, then stop cleanly. The external workflow retries
within five hours.
