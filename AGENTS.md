# Mushroom Radar agent guide

Before changing product code, read CLAUDE.md, docs/DECISIONS.md,
docs/BACKEND_PLAN.md, and the current files in docs/agent/.

- Treat accepted ADRs as product requirements.
- Keep Flutter a thin client. Enforce permissions and limits on the server.
- Preserve Anonymous Sign-In, signed photo uploads, local ONNX recognition,
  location privacy, and the ban on unofficial mine-risk geometry.
- Work on a dedicated branch. Never push directly to main.
- Complete one highest-priority unblocked backlog item per run.
- Add a regression test for bug and security fixes.
- Do not touch production data, deploy, merge, publish, buy services, or expose secrets.
- Record exact commands and outcomes in docs/agent/PROGRESS.md and
  docs/agent/QUALITY_REPORT.md.
- Reuse the existing checkout. Create a worktree only when the user explicitly asks.
