# Active work ownership

This file prevents Codex and Claude from editing the same files concurrently.

## Permanent zones

### Codex

- Branch prefix: `codex/*`
- Areas: security, Supabase and backend, database migrations and RLS, API
  authorization, CI/CD, release infrastructure, and `docs/agent/*`
- Primary paths: `supabase/**`, backend portions of `openapi/**`,
  `.github/workflows/**`, `.github/codex/**`, and `docs/agent/**`

### Claude

- Active branch: `claude/project-rb2fo8`
- Areas: product tasks and UI/UX, profiles, maps, screens, and product assets
- Primary paths: `docs/tasks/**`, `flutter_client/lib/features/**`, and
  product-facing assets

## Active claims

| Task | Owner | Branch | Intended files | Status |
|---|---|---|---|---|
| AUT-001 five-hour autonomous cycle | Codex | codex/autonomy-five-hour-cycle | .github/codex/autonomy.md, .github/workflows/codex-autonomy.yml, AGENTS.md, docs/agent/* | review |
| Product and UI work | Claude | claude/project-rb2fo8 | docs/tasks/*, profiles, maps, screens, UI assets | active |

## Cross-zone protocol

1. Assign exactly one owner before editing.
2. List intended paths in this table.
3. The other agent skips those paths until the PR is merged or the claim is released.
4. If a branch diff already touches a required file, choose another task.
5. Merge conflicts are resolved by the task owner after rebasing on current main.
