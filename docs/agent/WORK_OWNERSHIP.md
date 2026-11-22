# Agent work ownership

This file prevents overlapping autonomous edits. Each task has one owner before implementation.

## Codex

- Security audits and fixes.
- Supabase/PostgreSQL/RLS/Edge Function backend work.
- CI/CD, release infrastructure, repository guards and `docs/agent/*` state.
- Branches use `codex/*`; PRs target `main` without auto-merge.

## Claude

- Product behavior and `docs/tasks/*`.
- Flutter profiles, maps, screens, visual assets, UI/UX and accessibility.
- Branches use `claude/*`; PRs target `main` without auto-merge.

## Collision rule

Before editing, fetch the other agent's active branch and compare its changed paths with the intended task.
If files overlap, skip the task. Cross-zone work proceeds only after this file records one owner and the
planned files. Shared state updates in `docs/agent/*` belong to Codex; Claude may read them and should avoid
editing them while a Codex PR is open.

## Current assignments

| Task | Owner | Intended files |
|---|---|---|
| AUT-001 five-hour maintenance cycle | Codex | `.github/codex/autonomy.md`, `.github/workflows/codex-autonomy.yml`, CI guard, `docs/agent/*`, `AGENTS.md` |
| Product features and Flutter UI | Claude | `docs/tasks/*`, Flutter feature/screens/widgets, product assets |
