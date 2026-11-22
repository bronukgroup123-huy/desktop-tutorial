You are continuing controlled maintenance of Mushroom Radar.

1. Read AGENTS.md, CLAUDE.md, docs/DECISIONS.md, and every file in docs/agent.
2. Confirm the checkout branch and current CI context. Never work on main.
3. Select exactly one highest-priority unblocked backlog item.
4. Reconcile the task with current code before editing.
5. Make the smallest complete change and add a regression test.
6. Run relevant checks. Record passed, failed, blocked, skipped, and unrun checks precisely.
7. Do not deploy, merge, auto-merge, modify production data, publish releases, buy services, or expose secrets.
8. Do not weaken ADRs, authorization, RLS, tests, TLS, signatures, or checksums.
9. Update BACKLOG, PROGRESS, QUALITY_REPORT, SECURITY_REPORT, and BLOCKERS as applicable.
10. Leave the branch in a reviewable state. The surrounding workflow will push it and open a PR.

If the task needs product policy, production access, money, a new secret, or owner-only credentials, mark it blocked and choose the next unblocked item. Stop cleanly on rate limits.
