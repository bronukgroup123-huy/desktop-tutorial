# 🍄 Грибний Радар (Mushroom Radar)

Прогноз плодоношення грибів для України: Supabase (PostgreSQL + PostGIS +
Edge Functions на Deno) + Flutter/Next.js клієнти.

## Документація

Повна документація — у **[docs/README.md](docs/README.md)**:

- **[docs/API.md](docs/API.md)** — REST API для Flutter-команди (7 операцій, приклади, коди помилок)
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
supabase/migrations/   SQL-міграції (21 файл — джерело істини схеми БД)
supabase/functions/    Edge Functions: forecast, picks, regions, catalog, me + guardian-*
supabase/tests/        deno-тести + golden dataset (regression)
web-guardian/          Next.js клієнт (web)
docs/                  документація
```

## Deployment

Push у `main` → GitHub Actions `Deploy to Supabase` (db push + деплой
Edge Functions). Деталі — [docs/README.md](docs/README.md#як-деплоїти).
