# Mushroom Radar agent guide

Before changing product code, read CLAUDE.md, docs/DECISIONS.md,
docs/BACKEND_PLAN.md, and the current files in docs/agent/.

- Treat accepted ADRs as product requirements.
- Keep Flutter a thin client. Enforce permissions and limits on the server.
- Preserve Anonymous Sign-In, signed photo uploads, local ONNX recognition,
  location privacy, and the ban on unofficial mine-risk geometry.
- Work on a dedicated branch. Never push directly to main.
- Complete one highest-priority unblocked backlog item per run. Open product-plan tasks with their owner zone
  (Claude / Codex / owner) are listed in docs/BACKEND_PLAN.md §0 and mirrored in docs/agent/BACKLOG.md.
- Add a regression test for bug and security fixes.
- Do not touch production data, deploy, merge, publish, buy services, or expose secrets.
- Record exact commands and outcomes in docs/agent/PROGRESS.md and
  docs/agent/QUALITY_REPORT.md.
- Reuse the existing checkout. Create a worktree only when the user explicitly asks.

## Autonomous cycle (2026-11-22 → 2026-12-22)

- The scheduled cycle is run by Claude Code; follow docs/agent/AUTONOMY.md.
- State is kept on branch claude/agent-state (docs/agent/*); task work goes to claude/<id> branches, one PR
  per task, never auto-merged.
- Only one agent edits a given area at a time. If the Codex workflow is enabled, skip files touched by
  open claude/* PRs (and vice versa).
- The repository is public: security write-ups name components and fixes, not exploitation steps.
