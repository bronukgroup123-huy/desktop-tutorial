# API — Грибний Радар (Mushroom Radar)

Документація REST API для Flutter-команди. Базується на реальних обробниках
Edge Functions (`supabase/functions/*/index.ts`) та спільних модулях
(`supabase/functions/_shared/**`).

- **Base URL:** `https://<PROJECT_REF>.supabase.co/functions/v1`
- **Формат:** JSON (`Content-Type: application/json`)
- **CORS:** `OPTIONS` → `204`; вебклієнта немає, тож сайтам доступ не дозволено (WEB-001)
- **Схема БД:** [DB_SCHEMA.md](./DB_SCHEMA.md)
- **Авторизація:** [AUTH_FLOW.md](./AUTH_FLOW.md)

> ⚠️ **Заголовок `apikey`:** усі запити до Edge Functions потребують заголовок
> `apikey: <SUPABASE_ANON_KEY>`. Це публічний ключ проєкту (анон-рівень),
> не секрет — разом із `Authorization: Bearer $ACCESS_TOKEN` для JWT-ендпоінтів.

---

## Загальні правила

### Авторизація

| Рівень | Значення | Де застосовується |
|---|---|---|
| Публічний | без заголовка | `GET /regions`, `GET v1-regions/{slug}/geometry`, `GET v1-app-config`, `GET v1-air-alerts` |
| JWT обов'язковий (гість теж) | `Authorization: Bearer $ACCESS_TOKEN` | усі інші `v1-*` (`v1-me`, `v1-picks`, `v1-analysis`, …) |

Повна класифікація — `supabase/functions/auth-matrix.json`; що гостю заборонено — [AUTH_FLOW.md](./AUTH_FLOW.md) §3.
Контракт `v1-*` — [openapi/v1.yaml](../openapi/v1.yaml). Старий API вебверсії (`/picks`, `/me`, `/catalog`) прибрано
2026-11-26 (WEB-001); фото — лише Signed Upload URL через `v1-picks` (ADR-002).

Приклади нижче використовують плейсхолдер `$ACCESS_TOKEN` — **підставте свій
access_token** з Supabase Auth (див. [AUTH_FLOW.md](./AUTH_FLOW.md)).
Ніколи не комітьте справжні токени.

### Формат відповідей

- Успіх із даними: `{ "data": ... }` (+ поля `total`/`limit`/`offset` для списків)
- Створення — `201` (наприклад, `POST v1-picks`)

### Формат помилок

Єдиний формат помилки для **всіх** ендпоінтів (окремі ендпоінти можуть
опускати опційне `message`):

```json
{
  "error": "invalid_coordinates",
  "message": "lat/lng мають бути числами в межах [-90,90] / [-180,180]"
}
```

| Поле | Тип | Обов'язкове |
|---|---|---|
| `error` | string | так — машинний код (`snake_case`), не людський текст |
| `message` | string | ні — людиночитабельне уточнення, може бути відсутнє |

| HTTP | Коли | Типові коди |
|---|---|---|
| 400 | Невалідний запит | `invalid_json`, `invalid_coordinates`, `invalid_date`, `invalid_photo_format`, `photo_too_large`, `invalid_scope`, `invalid_period`, `invalid_pagination`, `limit_out_of_range`, `invalid_offset`, `invalid_mushroom_type`, `invalid_region_slug`, `missing_region_slug`, `invalid_season`, `invalid_edible`, `search_too_long`, `invalid_body`, `invalid_name` |
| 401 | Немає/битий JWT там, де він обов'язковий | `unauthorized` |
| 403 | RegionGuard: точка поза домашньою области | `outside_home_region` |
| 404 | Ресурс не знайдено | `region_not_found`, `me_not_found` |
| 405 | Неправильний HTTP-метод | `method_not_allowed` |
| 422 | Тіло запиту не проходить перевірку | `validation_error` (з `message`) |
| 500 | Внутрішня помилка | `internal_error`, `storage_error`, `db_error` |

> Деякі ендпоінти повертають `{ "error": ... }` **без** `message` — це відповідає контракту (`message` опційне).

### Rate limiting

Реалізовано за IP (`_shared/rate-limit.ts`, міграція `..._ip_rate_limit`): `regions` і всі `v1-*`. Перевищення → `429 rate_limited` + `Retry-After`.

---

## 0. Клієнтський API v1 (Flutter) — ВИКОРИСТОВУВАТИ ЦЕЙ

Повна специфіка — **[openapi/v1.yaml](../openapi/v1.yaml)** (OpenAPI 3.1, з неї генерується
Dart-клієнт). Розділ 1 нижче — `GET /regions` (список областей для онбордингу).

| Ендпоінт | Auth | Що робить |
|---|---|---|
| `GET /v1-me` | JWT | Профіль: ім'я, `handle` (нік), `avatar`, `level` (рівень і прогрес), `is_guest`, `onboarding.next_step` (`select_region` → `accept_terms` → `profile` → `done`), `region_change`, `handle_change`; `?check_handle=` — чи вільний нік; `?avatars=1` — вибір готового аватара (групи за рівнями, замки з причиною, `can_change`); `avatar` — готовий `{kind: preset, id}` (за замовчуванням `traveler_01`; конструктора немає, ADR-021 §21.7) |
| `PATCH /v1-me` | JWT | `{ name?, handle?, avatar? (`{kind: preset, id}` зі списку готових; невідомий `400 invalid_avatar`, не відкритий рівнем `403 avatar_locked`), home_region_slug?, accept_terms_version? }`; ім'я/нік/аватар — лише після Google / Apple (`403 registration_required`); `409 handle_taken`, `409 handle_change_too_soon`; зміна області — ADR-016 |
| `DELETE /v1-me` | JWT | Видалити акаунт назавжди (вимога Google Play) |
| `GET /v1-regions/{slug}/geometry?detail=` | публічний | Кордон області (маска «острова»): `bbox`, `center`, `zoom`, `geometry`; кеш + ETag |
| `GET /v1-forest-zones?bbox=&z=&limit=` | JWT | Ліси **тільки Home Region**: `{ data: FeatureCollection }` з `type_label`/`type_color` |
| `POST /v1-forecast` | JWT | Прогноз у межах Home Region; рівні з підписами, **без** `score`/`probability` |
| `POST /v1-picks/upload-url` | JWT | Тук-тук, крок 1: `{ client_id, content_type, size_bytes }` → `{ upload_url, path, token, expires_at }` (ADR-002) |
| `POST /v1-picks` | JWT | Тук-тук, крок 3: створити точку `private` / `public` (ADR-018) → `{ id, visibility, status_label, marker_color }` |
| `GET /v1-picks/map?bbox=&mine=` | JWT | Точки на карті області: публічні інших (зсунуте місце) + власні (точне); `mine=true` — ще й власні приватні |
| `GET /v1-picks/{id}` | JWT | Картка точки: фото (тимчасове посилання), назва, опис, дата, статус, застереження |
| `GET /v1-picks/species` | JWT | Список видів для вибору назви + `unknown_label` («Не знаю, що це») |
| `GET /v1-analysis` | JWT | Аналіз ділянки: доступні розміри (10×10 — `lock_label: "Доступно в Pro"`), збережена ділянка, ліміт на сьогодні |
| `POST /v1-analysis` | JWT | `{ lat, lng, size_km: 5 \| 10, date? }` → ліси в квадраті, погода, Top-1 / Top-2 рівнями (ADR-015) |
| `GET /v1-app-config` | публічний | Тексти «Безпеки»: банер ДСНС (ADR-003), «Заблукали?», «Отруєння», «Інші небезпеки», чек-лист, поради на час тривоги; змінюються без релізу (`feature_flags`), ETag |
| `GET /v1-air-alerts?region=<slug>` | публічний | Повітряна тривога (alerts.in.ua): один запит на всю Україну розкладається по областях, кеш 45 с спільний для всіх копій функції; `region` — лише своя область; `{ available, regions: [{ slug, scope, title }] }`; без ключа — `available: false` |

Спільні правила v1:
- Гість входить через `supabase.auth.signInAnonymously()` і має звичайний JWT (ADR-001).
- Помилки: `{ "error": "code", "message"?: "текст UA" }`. Нові коди: `home_region_required` (409),
  `outside_home_region` (403), `registration_required` (403), `region_change_not_allowed` (403),
  `terms_version_outdated` (409), `bbox_too_large` (400), `rate_limited` (429 + `Retry-After`).
- Усі v1-* мають rate limit за IP.
- Наглядач — лише `v1-guardian` (ADR-022); для гостя → `403 registration_required`.

### Тук-тук: `v1-picks` (B3.0 + B3.1, ADR-002, ADR-018)

Фото **ніколи** не передається як base64. Три кроки, спільний `client_id` (UUID від клієнта)
робить їх безпечними для повтору з офлайн-черги:

```bash
# 1. Посилання для завантаження
curl -X POST "$SUPABASE_URL/functions/v1/v1-picks/upload-url" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "client_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "content_type": "image/jpeg", "size_bytes": 1500000 }'
# → { "data": { "upload_url": "...", "path": "<user_id>/<client_id>.jpg", "token": "...", "expires_at": "..." } }

# 2. Файл — прямо в Storage (стрімінг з диска; без Authorization / apikey)
curl -X PUT "$UPLOAD_URL" -H "Content-Type: image/jpeg" --data-binary @photo.jpg

# 3. Точка
curl -X POST "$SUPABASE_URL/functions/v1/v1-picks" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    "path": "<path з кроку 1>",
    "lat": 50.4501, "lng": 30.5234,
    "captured_at": "2026-11-10T09:30:00Z",
    "visibility": "public",
    "species_id": "boletus_edulis",
    "description": "Під старими соснами після дощу",
    "ai_check": { "model_version": "bioclip2-int8-1",
                  "top": [{ "species_id": "boletus_edulis", "level": "high" }],
                  "match": true, "twin_alert": false }
  }'
# → 201 { "data": { "id": "...", "visibility": "public", "status_label": "Перевіряється", "marker_color": "#9e9e9e" } }
```

Правила `POST /v1-picks` (перевірки йдуть у цьому порядку):

| # | Перевірка | Помилка |
|---|---|---|
| 1 | Гість створює лише `private` | `403 registration_required` |
| 2 | Поля тіла | `422 validation_error` (+ `message`) |
| 3 | `path` — лише зі своєї теки | `403 forbidden` |
| 4 | Той самий `client_id` уже створив точку | `200` з тією самою точкою (не помилка) |
| 5 | Точка в межах Home Region | `403 outside_home_region` (`409 home_region_required`, якщо область не обрано) |
| 6 | `species_id: null` («Не знаю») — лише `private`; id має бути в довіднику | `422 species_required`, `422 unknown_species` |
| 7 | Опис: ≤ 500 символів; телефони, e-mail, посилання, @нікнейми → «…» | `422 validation_error` (задовгий) |
| 8 | Ліміти: 5 приватних / добу; публічні — з рівня «Лісовик» (рейтинг ≥ 201), 5 / добу | `429 daily_limit_reached`, `403 level_required` |
| 9 | Фото завантажено, ≤ 5 МіБ, справжній JPEG / PNG / WebP | `422 photo_not_uploaded`, `400 photo_too_large`, `400 invalid_photo_format` |

Що робить сервер із фото і місцем:
- перевіряє EXIF (GPS ≤ 1 км від заявлених координат, час ≤ 24 год від `captured_at`). Це лише
  підказка: результат зберігається в `ai_check.exif`, а точку він **не** підтверджує;
- вирізає EXIF / XMP / IPTC (орієнтація JPEG зберігається) і кладе очищену копію в теку
  `picks/<id>.<ext>`, куди клієнти писати не можуть; завантажену «чернетку» видаляє;
- нова публічна точка завжди `pending` («Перевіряється») — підтверджують люди (B3.8);
- для `public` рахує стабільно зсунуте місце (300–500 м). Точні координати не потрапляють у
  жодну відповідь для інших користувачів.

`ai_check` — підказка локального ШІ: рівні `high` / `medium` / `low`, **без відсотків**. Зайві
поля відкидаються. `twin_alert: true` позначає точку: автоматично вона не підтверджується.

Необов'язковий секрет функції `PICK_FUZZ_SECRET` — ключ для зсуву публічних точок; якщо його
немає, використовується ключ service_role. Зсув зберігається разом із точкою, тож зміна
секрету не рухає вже створені точки.

### Карта тук-туків: `GET v1-picks/map`, `GET v1-picks/{id}` (B3.3, ADR-018 §18.2, §18.5)

```bash
curl "$SUPABASE_URL/functions/v1/v1-picks/map?mine=true" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $ACCESS_TOKEN"
# → { "data": { "points": [ { "id", "lat", "lng", "is_exact", "is_mine", "visibility",
#        "species_id", "name_label", "status_label", "marker_color" } ], "truncated": false } }
```

- Чужі точки — лише публічні, не відхилені, у своїй області; `lat` / `lng` — **зсунуте місце**
  (`is_exact: false`). Власні — з точними координатами (`is_exact: true`).
- `bbox` для чужих точок фільтрує за зсунутим місцем — справжнє не можна «намацати» рамкою.
- До 500 точок; якщо їх більше — `truncated: true` (показано найновіші).
- Картка `GET v1-picks/{id}`: `description`, `date_label`, `photo_url` (посилання на 10 хв),
  `disclaimer_label`, `actions` (поки порожній: скарги — B3.12, зміна й видалення — B3.4).
  Чужа приватна, відхилена чи видалена точка → `404 pick_not_found`.

### Аналіз ділянки: `v1-analysis` (B2.9, ADR-015)

```bash
curl -X POST "$SUPABASE_URL/functions/v1/v1-analysis" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "lat": 50.4501, "lng": 30.5234, "size_km": 5 }'
```

Відповідь: `area` (центр, `size_label`, точні межі `bbox`), `forest` (`summary_label` і типи лісу
з площею), `top1` / `alternative` (рівні з підписами + `forest_label` — у якому лісі шукати),
`weather` (базова: температура, вологість, опади), `warnings`, `usage`.

| Правило | Помилка |
|---|---|
| Ділянка — тільки у своїй області (і в Pro) | `403 outside_home_region` |
| 10×10 км — лише Pro | `403 pro_required` (+ `message`) |
| Дата далі ніж +3 дні — лише Pro | `403 pro_required` |
| Безкоштовно — 5 аналізів на добу (київський час) | `429 analysis_limit_reached` + `Retry-After` |
| Некоректні поля | `422 validation_error` |

Pro ще не продається (B6.3), тож 10×10 зараз недоступна нікому; застосунок показує її із замком
за `sizes[].lock_label`. Якщо розрахунок упав, списаний аналіз повертається.

---

## 1. GET /regions (список областей)

Публічний довідник 27 регіонів України (24 області + АР Крим + Київ +
Севастополь) для випадаючого списку Home Region.
Без геометрії (`polygon` не віддається). Оновлення регіону профілю —
`PATCH v1-me { home_region_slug }`.

**Auth:** публічний.

```bash
curl "$SUPABASE_URL/functions/v1/regions"
```

### Response 200

```json
{
  "data": [
    {
      "id": 1,
      "name": "Київська",
      "slug": "kyivska",
      "koatuu": "3200000000",
      "katottg": "UA32000000000030281"
    },
    {
      "id": 26,
      "name": "Київ",
      "slug": "kyiv",
      "koatuu": null,
      "katottg": "UA80000000000093317"
    }
  ]
}
```

Поля `koatuu` та `katottg` — **nullable**: для міських регіонів
(Київ, Севастополь) `koatuu = null`. Кожен КАТОТТГ — рівно **19 символів**
(`UA` + 17 цифр); `koatuu` — 10 символів (або `null`).
Сортування — за `name` (ascending) для стабільного UI.
Помилки: `method_not_allowed` (**405**), `db_error` (**500**).

> **Правило для клієнта:** показуй `name`, відправляй на сервер **`slug`**
> (див. [AUTH_FLOW.md](./AUTH_FLOW.md#4-home-region)). Ніколи не хардкодь `id`.

---

## Посилання

- [docs/README.md](./README.md) — quick-start + regression testing
- [docs/DB_SCHEMA.md](./DB_SCHEMA.md) — схема БД, RLS, ER
- [docs/AUTH_FLOW.md](./AUTH_FLOW.md) — JWT, онбординг, Home Region
