# 🍄 Грибний Радар (Mushroom Radar)

Прогноз плодоношення грибів для України: Supabase (PostgreSQL + PostGIS +
Edge Functions на Deno) + Flutter/Next.js клієнти.

## Документація

Повна документація — у **[docs/README.md](docs/README.md)**:

- **[docs/API.md](docs/API.md)** — REST API: **v1-* для Flutter** (OpenAPI — [openapi/v1.yaml](openapi/v1.yaml)) + legacy-ендпоінти
- **[docs/DB_SCHEMA.md](docs/DB_SCHEMA.md)** — схема БД: 19 таблиць, RLS, ER-діаграма, RPC
- **[docs/AUTH_FLOW.md](docs/AUTH_FLOW.md)** — JWT, онбординг, Home Region (slug-only)

## Швидкий старт

```bash
supabase start                 # локальний стек
supabase db reset              # міграції
deno test supabase/tests/forecast/ --allow-net
```

## Структура

```
supabase/migrations/   SQL-міграції (48 файлів — джерело істини схеми БД)
supabase/functions/    Edge Functions: forecast, picks, regions, catalog, me + guardian-*
supabase/tests/        deno-тести + golden dataset (regression)
web-guardian/          Next.js клієнт (web)
flutter_client/        Flutter-клієнт
openapi/               OpenAPI 3.1 для v1-* (генерація Dart-клієнта)
legacy/                старий стек до Supabase — не використовується
docs/                  документація
```

## Deployment

Push у `main` → GitHub Actions `Deploy to Supabase`: тести → `supabase db push`
→ деплой Edge Functions. На кожен push — `Tests` і `Security` (Gitleaks). Деталі — [docs/README.md](docs/README.md#як-деплоїти).
