You are continuing controlled maintenance of Mushroom Radar.

1. Read AGENTS.md, CLAUDE.md, docs/DECISIONS.md, and every file in docs/agent.
2. Confirm the checkout branch and current CI context. Never work on main.
3. Fetch origin/main and origin/claude/project-rb2fo8 when that branch exists.
4. Read docs/agent/WORK_OWNERSHIP.md and compare the Claude branch paths with the
   files required by the proposed task.
5. Select exactly one highest-priority unblocked Codex-owned backlog item.
   Codex owns security, Supabase/backend, CI/CD, infrastructure, and docs/agent.
   Claude owns docs/tasks, product behavior, profiles, maps, screens, assets, and UI.
6. If any required file is changed on Claude's active branch, skip the task.
7. For a cross-zone task, proceed only when WORK_OWNERSHIP.md assigns it to Codex
   and lists its intended files.
8. Reconcile the task with current code before editing.
9. Make the smallest complete change and add a regression test.
10. Run relevant checks. Record passed, failed, blocked, skipped, and unrun checks precisely.
11. Do not deploy, merge, auto-merge, modify production data, publish releases, buy services, or expose secrets.
12. Do not weaken ADRs, authorization, RLS, tests, TLS, signatures, or checksums.
13. Update BACKLOG, PROGRESS, QUALITY_REPORT, SECURITY_REPORT, BLOCKERS, and
    WORK_OWNERSHIP as applicable.
14. Leave the branch in a reviewable state. The surrounding workflow will push it and open a PR.

If the task needs product policy, production access, money, a new secret, or owner-only credentials, mark it blocked and choose the next unblocked item.

If an API, model, or infrastructure rate limit is reached:

1. Do not retry repeatedly in this run.
2. Preserve already verified work and update the task status to blocked_rate_limit or paused when possible.
3. Record the provider message and retry-after time without exposing secrets.
4. End cleanly. The external workflow will retry within five hours.
