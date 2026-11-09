# legacy/ — не використовується

Ранній стек проєкту, до переходу на Supabase. **Не деплоїться, не тестується і не
підтримується.** Збережено лише для історії.

| Що | Було |
|---|---|
| `db/migrations/` | Схема v1.1 для «голого» PostgreSQL (паралельна до Supabase) |
| `api/` | Dockerfile для Python API (FastAPI) — коду API в репозиторії немає |
| `web/` | Dockerfile веб-клієнта |
| `init-scripts/` | Ініціалізація PostgreSQL для Docker |
| `compose.yaml` | Docker Compose: db + api + web |

**Джерело істини зараз:**
- схема БД — `supabase/migrations/`;
- бекенд — `supabase/functions/` (Edge Functions);
- веб-клієнт Наглядача — `web-guardian/`;
- мобільний клієнт — `flutter_client/`.

Рішення про перенесення — `docs/BACKEND_PLAN.md`, задача B0.3 (підтверджено PO 2026-11-09).
Нові зміни в цій папці не вносимо; якщо щось звідси знадобиться — переносимо в актуальний
стек через міграцію / Edge Function.
