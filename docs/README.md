# Грибний Радар — docs

Документація проєкту для всіх команд. **Правило:** жодних справжніх токенів,
ключів чи паролів у документах — лише плейсхолдери (`$ACCESS_TOKEN`,
`$SUPABASE_URL`, `<PROJECT_REF>`).

## Зміст

| Документ | Що всередині |
|---|---|
| [API.md](./API.md) | **v1-* для Flutter** + legacy-ендпоінти, приклади, коди помилок, curl |
| [../openapi/v1.yaml](../openapi/v1.yaml) | OpenAPI 3.1 для v1-* — генерація Dart-клієнта |
| [DB_SCHEMA.md](./DB_SCHEMA.md) | 19 таблиць, колонки, RLS-політики, ER-діаграма, RPC-функції |
| [AUTH_FLOW.md](./AUTH_FLOW.md) | Supabase Auth → JWT, онбординг, Home Region (slug-only), дозволи |
| [DECISIONS.md](./DECISIONS.md) | Архітектурні рішення Product Owner (ADR-001…017) — обов'язкові для всіх команд |
| [BACKEND_PLAN.md](./BACKEND_PLAN.md) | План реалізації бекенду під Flutter: аудит, фази B0–B7, нові таблиці |

Службові звіти (історія виправлень): `8.7_gdd_fix.md`,
`8.7b_peak_bonus_fix.md`, `catalog_canonicalization_report.md`.

---

## Quick-start

### Що це

ForecastEngine прогнозує плодоношення грибів за точкою (lat/lng), датою,
типом лісу та погодою (Open-Meteo). Scoring — за правилами `expert_rules`
(20 видів ТОП-20). Контур «Наглядач» слідкує за сесіями грибників.

### Структура репо

```
supabase/
  migrations/     SQL-міграції (48 файлів — джерело істини схеми БД)
  functions/      Edge Functions (Deno)
    _shared/      спільні модулі: http-шар v1, forecast engine, picks, auth, errors
    v1-*/         клієнтський API v1 (Flutter) — див. docs/API.md, розділ 0
    regions/      список областей для онбордингу (старий API вебверсії прибрано, WEB-001)
  tests/
    forecast/     unit + endpoint тести (deno test)
    fixtures/     golden-dataset.json + rules-subset.json (regression)
    *.sql         SQL-тести (RLS, безпека)
data/catalog/     вихідні дані довідника (mushroom_catalog.js, mushroom_descriptions.js, mushroomIcons.js)
docs/             ця документація
```

### Як запускати локально

```bash
# Edge Functions
supabase start                       # локальний стек (API, DB, Auth, Storage)
supabase functions serve forecast    # окрема функція
supabase functions serve             # усі функції

# Міграції
supabase db reset                    # застосувати міграції з нуля
supabase migration new <name>        # нова міграція
```

### Як тестувати

```bash
# Усі unit/endpoint тести
deno test supabase/tests/forecast/ --allow-net

# Regression на Golden Dataset (окремо — потребує --allow-read)
deno test supabase/tests/forecast/regression.test.ts --allow-net --allow-read

# Конкретний файл
deno test supabase/tests/forecast/engine.test.ts --allow-net
```

### Як деплоїти

Push у `main` → GitHub Actions `Deploy to Supabase` (`db push` + деплой
Edge Functions). Workflow тригериться лише на `supabase/migrations/**` та
`supabase/functions/**` — коміти тільки з тестами/документацією CI не
запускають (це нормально). Health-check — `gh run list --limit 3`.

---

## Regression testing (Golden Dataset)

Regression-набір для ForecastEngine (план v6.0 §18.3): реальні сценарії
походів → прогноз → метрики якості.

### Що всередина

- `supabase/tests/fixtures/golden-dataset.json` — 4 записи:
  - `rec-001` — Київ, жовтень, сосняк → `boletus_edulis` (autumn)
  - `rec-002` — Львівська, серпень, березняк → `cantharellus_cibarius` (summer2)
  - `rec-003` — Київ, листопад, листковий ліс → `flammulina_velutipes` (late)
  - `rec-004` — Київ, квітень → поза сезоном, `top1 = null` (fallback-шлях)
  
  Кожен запис містить `weather_payload` — снапшот відповіді Open-Meteo
  (без живих запитів під час тесту).
- `supabase/tests/fixtures/rules-subset.json` — 9 правил `expert_rules`
  (7 цільових + 2 fallback: `lycoperdon_perlatum`, `agaricus_campestris`),
  параметри verbatim з seed-міграції `20260912000002`.

### Як запускати

```bash
deno test supabase/tests/forecast/regression.test.ts --allow-net --allow-read
```

Без `--allow-read` regression-тести логують попередження й пропускаються
(щоб повний набір `deno test supabase/tests/forecast/ --allow-net`
залишався зеленим без додаткових дозволів).

### Метрики

| Метрика | Порог | Значення зараз |
|---|---|---|
| Precision = TP/(TP+FP) | ≥ 0.5 | 1.00 (TP=3, FP=0) |
| Recall = TP/(TP+FN) | ≥ 0.3 | 1.00 (TP=3, FN=0) |
| Top1 (slug match) | 100% | 3/3 |

«Прогноз дано» = `top1 !== null && !noDataReason` (fallback із `noDataReason`
не вважається прогнозом). Додатково асертується `top1.wave === expected.top1_wave`
(захист від регресій `detectWave`) та сезон через рік для
`flammulina_velutipes` (11-15 → in-season, 04-20 → not).

### Як розширювати (після бета-тесту)

1. Додати запис у `golden-dataset.json`: `id`, `description`, `input`,
   `weather_payload`, `weather_summary`, `expected`
   (`top1_slug`, `top1_wave`, `actual_found`).
2. Якщо потрібен новий вид — додати правило в `rules-subset.json`
   (колонки = `expert_rules`, значення з продакшн-БД).
3. Запустити (див. вище); при падінні top1 — підкрутити `weather_payload`
   (temp/humidity/rain) і зафіксувати, який саме сценарій ламається.
4. Мінімум — 2 записи; бажано покривати кожну хвилю (spring/summer2/autumn/late)
   і негативні кейси (поза сезоном, поза регіоном).

---

## Migration history

Нумерація міграцій — `YYYYMMDDHHMMSS_<slug>.sql`, застосовуються лексикографічно
(`supabase db push`). Застосовані версії — `supabase_migrations.schema_migrations`.

| Версія | Що | Примітка |
|---|---|---|
| `20260910000000`, `20260910000001` | regions, users | |
| `20260911000001`–`000007` | Guardian foundation, cron, notifications, SOS, ревоки | |
| `20260912000001`–`000002` | forecast foundation + seed expert_rules | |
| `202609120000003` | — (**пропущено**) | номер не використовувався |
| `202609120000004`–`000015` | catalog, forecast fixes, RPC, storage, seeds | |
| `20260912000016` | — (**пропущено свідомо**) | аудит B ухвалив рішення одразу `000017` |
| `20260912000017` | security hardening (audit B) | REVOKE + FORCE RLS + WITH CHECK |
| `20260912000018` | formalize `rls_auto_enable` (audit E) | функція + event trigger `ensure_rls` були створені вручну в Dashboard 2026-09-11 — тепер у міграціях |

Правила для нових міграцій:
- Наступний номер — пізніший за останню міграцію в `supabase/migrations/` (формат `YYYYMMDDHHMMSS`).
- Тримати gaps відображеними в цій таблиці (не «пере нумеровувати»).
- Жодного DDL через Dashboard — усе через міграції (урок audit E).

---

## Безпека (коротко)

- Хто що може викликати — `supabase/functions/auth-matrix.json` (SEC-004): публічні `regions`, `catalog`,
  `v1-regions`, `v1-app-config`, `v1-air-alerts`; решта `v1-*` — JWT (гість теж, ADR-001); розклад і вебхук —
  service_role / секрет. Деталі — [AUTH_FLOW.md](./AUTH_FLOW.md).
- Наглядач — `v1-guardian` серед друзів, JWT (ADR-022); старий `X-Guardian-Token` прибрано (SEC-005).
- RLS — на 38 з 42 таблиць (свіжа БД з міграцій, 2026-11-25). 4 службові (`forest_polygons`, `guardian_tick_log`,
  `user_push_tokens`, `guardian_push_tokens`) закриті для ролей API через REVOKE; RLS на них міграції не
  вмикають (лише FORCE) — розбіжність записано як SEC-008. SECURITY DEFINER-функції недоступні ролям API
  (SEC-002, `supabase/tests/security_definer_privileges.sql`). Звіт — `docs/agent/SECURITY_REPORT.md`.
- Home Region — тільки через `slug`, ніколи не хардкодь `regions.id`.
- Нумерація міграцій: дата + час (`YYYYMMDDHHMMSS`), наступна — пізніша за останню в `supabase/migrations/`.

---

## TODO / V2

| Де | Що |
|---|---|
| [AUTH_FLOW.md](./AUTH_FLOW.md#4-home-region) | Зміна Home Region у Pro — після entitlements (B6.3); правило й журнал `region_change_log` уже працюють |
| Golden Dataset | Наповнення реальними даними бета-тесту (ціль 100+ записів) |
