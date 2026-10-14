# API — Грибний Радар (Mushroom Radar)

Документація REST API для Flutter-команди. Базується на реальних обробниках
Edge Functions (`supabase/functions/*/index.ts`) та спільних модулях
(`supabase/functions/_shared/**`).

- **Base URL:** `https://<PROJECT_REF>.supabase.co/functions/v1`
- **Формат:** JSON (`Content-Type: application/json`)
- **CORS:** усі ендпоінти відповідають на `OPTIONS` → `204`
- **Схема БД:** [DB_SCHEMA.md](./DB_SCHEMA.md)
- **Авторизація:** [AUTH_FLOW.md](./AUTH_FLOW.md)

---

## Загальні правила

### Авторизація

| Рівень | Значення | Де застосовується |
|---|---|---|
| Публічний | без заголовка | `POST /forecast`, `GET /regions`, `GET /catalog` |
| Опційний JWT | `Authorization: Bearer $ACCESS_TOKEN` | `GET /picks` (для `scope=mine/friends`) |
| JWT обов'язковий | `Authorization: Bearer $ACCESS_TOKEN` | `POST /picks`, `GET /me`, `PATCH /me` |

Приклади нижче використовують плейсхолдер `$ACCESS_TOKEN` — **підставте свій
access_token** з Supabase Auth (див. [AUTH_FLOW.md](./AUTH_FLOW.md)).
Ніколи не комітьте справжні токени.

### Формат відповідей

- Успіх із даними: `{ "data": ... }` (+ поля `total`/`limit`/`offset` для списків)
- `POST /forecast` — **виняток**: повертає сирий `ForecastResult` без обгортки `{ data }`
- `POST /picks` — `201` із `{ data: { id, verificationStatus } }`

### Формат помилок

```json
{
  "error": "invalid_coordinates",
  "message": "lat/lng мають бути числами в межах [-90,90] / [-180,180]"
}
```

| HTTP | Коли | Типові коди |
|---|---|---|
| 400 | Невалідний запит | `invalid_json`, `invalid_coordinates`, `invalid_date`, `invalid_input`, `invalid_photo_format`, `photo_too_large`, `invalid_scope`, `invalid_period`, `invalid_pagination`, `limit_out_of_range`, `invalid_offset`, `invalid_mushroom_type`, `invalid_region_slug`, `missing_region_slug`, `invalid_season`, `invalid_edible`, `search_too_long`, `invalid_body`, `invalid_name` |
| 401 | Немає/битий JWT там, де він обов'язковий | `unauthorized` |
| 403 | RegionGuard: точка поза домашньою области | `outside_home_region` |
| 404 | Ресурс не знайдено | `region_not_found`, `me_not_found` |
| 405 | Неправильний HTTP-метод | `method_not_allowed` |
| 422 | Schema-помилка тіла `/picks` | `invalid_input` |
| 500 | Внутрішня помилка | `internal_error`, `storage_error`, `db_error` |

### Rate limiting

Наразі **не реалізовано** на рівні Edge Functions (`TODO/V2` — див.
[docs/README.md](./README.md#todo--v2)). Базовий захист — Supabase платформи.

---

## 1. POST /forecast

Прогноз плодоношення для точки: RegionGuard → погода (Open-Meteo) →
скорінг `expert_rules` → топ-1 + альтернатива. Живе оголошення контракту —
`supabase/functions/forecast/index.ts`.

**Auth:** публічний.

### Request

| Поле | Тип | Обов'язкове | Опис |
|---|---|---|---|
| `lat` | number | так | Широта, `[-90, 90]` |
| `lng` | number | так | Довгота, `[-180, 180]` |
| `date` | string (ISO) | ні | Дата прогнозу; за замовчуванням — зараз |
| `forestType` | string \| null | ні | Тип лісу (`pine`, `birch`, `deciduous`, …); `null` = невідомо |
| `forestConfirmed` | boolean | ні | Чи підтвердив користувач тип лісу на місці |
| `homeRegionId` | number \| null | ні | ID домашньої області (RegionGuard); `null` = пропустити перевірку |

```bash
curl -X POST "$SUPABASE_URL/functions/v1/forecast" \
  -H "Content-Type: application/json" \
  -d '{
    "lat": 50.45,
    "lng": 30.52,
    "date": "2026-10-12",
    "forestType": "pine",
    "forestConfirmed": true,
    "homeRegionId": 1
  }'
```

### Response 200

```json
{
  "regionName": "Київська",
  "date": "2026-10-12",
  "forest": "pine (підтверджено), 50 років",
  "top1": {
    "mushroom_type": "boletus_edulis",
    "name_ua": "Білий гриб",
    "score": 0.83,
    "probability": "high",
    "matched": ["temp 13 within fruiting range", "in peak temp [12,18]"],
    "missed": [],
    "wave": "autumn",
    "where": "Південні схили + старі сосни"
  },
  "alternative": {
    "mushroom_type": "russula_vesca",
    "name_ua": "Сироїжка",
    "score": 0.71,
    "probability": "medium",
    "matched": ["temp 13 within fruiting range"],
    "missed": [],
    "wave": "autumn",
    "where": null
  },
  "warnings": []
}
```

> ⚠️ Це **єдиний ендпоінт без обгортки `{ data }`** — відповідь є сирим
> `ForecastResult`. Поле `noDataReason` відсутнє в успішній відповіді
> (з'являється лише у fallback-випадках).

Рівні `probability`: `peak` ≥ 0.90 → `high` ≥ 0.70 → `medium` ≥ 0.50 →
`low` ≥ 0.30 → `no_data` < 0.30.

### Помилки

```json
{ "error": "invalid_coordinates", "message": "lat/lng мають бути числами в межах [-90,90] / [-180,180]" }
```
```json
{ "error": "outside_home_region", "message": "Ви поза вашою областю. Прогноз обмежено." }
```

`outside_home_region` → **403**. Fallback (погода недоступна / жоден вид не
пройшов фільтр) → **200** з `noDataReason` і можливим базовим `top1`.

---

## 2. POST /picks

Створити знахідку («тук-тук»): валідація → завантаження фото в Storage
(bucket `mushroom-photos`) → вставка в `mushroom_picks` → **201**.

**Auth:** JWT обов'язковий (`requireMushroomPicker`).

### Request

| Поле | Тип | Обов'язкове | Опис |
|---|---|---|---|
| `lat` | number | так | `[-90, 90]` |
| `lng` | number | так | `[-180, 180]` |
| `photoBase64` | string | так | Base64 БЕЗ data-url префікса; 100..8 000 000 символів; JPEG/PNG/WebP (перевірка magic bytes); декодований розмір ≤ 5 MiB |
| `mushroomType` | string | так | Канонічний id каталогу (наприклад `boletus_edulis`), 1..64 символи |
| `isIndicator` | boolean | ні (def `false`) | Індикаторний вид |
| `isNegativeReport` | boolean | ні (def `false`) | Негативний звіт («нічого немає») |
| `gpsAccuracy` | number ≥ 0 | ні | Точність GPS (метри) |
| `forestType` | string ≤ 64 | ні | Тип лісу |

```bash
curl -X POST "$SUPABASE_URL/functions/v1/picks" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "lat": 50.45,
    "lng": 30.52,
    "gpsAccuracy": 12.5,
    "photoBase64": "/9j/4AAQSkZJRgABAQ...",
    "mushroomType": "boletus_edulis",
    "forestType": "pine",
    "isIndicator": false,
    "isNegativeReport": false
  }'
```

### Response 201

```json
{
  "data": {
    "id": "3f8a1c2e-1111-4222-8333-abcdef012345",
    "verificationStatus": "pending"
  }
}
```

Фото зберігається приватним (`photo_url` = шлях у bucket, не публічний URL).
Публічні URL't отримуються лише через `GET /picks` (signed URLs, TTL 600 с).

### Помилки

```json
{ "error": "invalid_input", "message": "photoBase64: String must contain at least 100 character(s)" }
```
```json
{ "error": "photo_too_large", "message": "max 5 MiB" }
```
```json
{ "error": "invalid_photo_format", "message": "photo must be JPEG, PNG or WebP" }
```
```json
{ "error": "storage_error" }
```

`invalid_input` → **422**; решта фото-помилок → **400**; `storage_error`/`db_error` → **500**.
При провалі вставки фото видаляється (rollback).

---

## 3. GET /picks

Стрічка трофеїв з пагінацією та скоупами видимості. RLS накладається клієнтом
користувача; enrichment (імена, регіони, signed URLs) — через service_role.

**Auth:** опційний JWT. Для `scope=mine` / `scope=friends` — обов'язковий (інакше `401`).

### Query

| Параметр | Значення | За замовчуванням | Опис |
|---|---|---|---|
| `scope` | `mine` \| `friends` \| `public` \| `region` | `public` | `mine` — свої; `friends` — `pick_type=friends`; `public` — `pick_type=public`; `region` — автори з домашньої області |
| `period` | `24h` \| `3d` \| `week` \| `all` | `week` | Фільтр за `created_at` |
| `limit` | int 1..50 | 20 | Розмір сторінки |
| `offset` | int ≥ 0 | 0 | Зсув |
| `mushroom_type` | `^[a-z][a-z0-9_]{0,63}$` | — | Фільтр за видом |
| `region_slug` | `^[a-z0-9][a-z0-9-]{0,63}$` | — | Обов'язковий для `scope=region` |

```bash
curl "$SUPABASE_URL/functions/v1/picks?scope=public&period=week&limit=20&offset=0" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

### Response 200

```json
{
  "data": [
    {
      "id": "3f8a1c2e-1111-4222-8333-abcdef012345",
      "user_id": "auth0uid-0001-4c1a-9b2e-0f1e2d3c4b5a",
      "user_name": "Грибник",
      "region_name": "Київська",
      "mushroom_type": "boletus_edulis",
      "name_ua": "Білий гриб",
      "photo_url": "https://<PROJECT_REF>.supabase.co/storage/v1/object/sign/mushroom-photos/<user_id>/<pick_id>.jpg?token=...",
      "lat": 50.45,
      "lng": 30.52,
      "forest_type": "pine",
      "verification_status": "pending",
      "weight": 1.0,
      "is_indicator": false,
      "is_negative": false,
      "created_at": "2026-10-12T08:41:00.000Z"
    }
  ],
  "total": 1,
  "limit": 20,
  "offset": 0
}
```

`photo_url` — signed URL з TTL 600 с; після закінчення робіть повторний
`GET /picks`. Якщо підпис не вдався — `photo_url: null`.

### Помилки

`invalid_scope`, `invalid_period`, `invalid_pagination`, `limit_out_of_range`,
`invalid_offset`, `invalid_mushroom_type`, `invalid_region_slug`,
`missing_region_slug` → **400**; `unauthorized` (mine/friends без JWT) → **401**;
`region_not_found` → **404**; `db_error` → **500**.

---

## 4. GET /regions

Публічний довідник 27 областей України для випадаючого списку Home Region.
Без геометрії (`polygon` не віддається). Оновлення регіону профілю —
див. [PATCH /me](#7-patch-me).

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
      "koatuu": "UA8000000000",
      "katottg": "UA80020000000066663"
    },
    {
      "id": 13,
      "name": "Львівська",
      "slug": "lvivska",
      "koatuu": "UA4614000000",
      "katottg": "UA46120000000015887"
    }
  ]
}
```

Сортування — за `name` (ascending). Помилки: `method_not_allowed` (**405**),
`db_error` (**500**).

> **Правило для клієнта:** показуй `name`, відправляй на сервер **`slug`**
> (див. [AUTH_FLOW.md](./AUTH_FLOW.md#home-region)). Ніколи не хардкодь `id`.

---

## 5. GET /catalog

Довідник 326 видів грибів (`mushroom_catalog`) з фільтрами та пагінацією.

**Auth:** публічний.

### Query

| Параметр | Значення | За замовчуванням | Опис |
|---|---|---|---|
| `forest` | `pine,oak` (через кому) | — | Перетин з `attrs.tree` |
| `season` | `spring` \| `summer` \| `autumn` \| `winter` | — | `attrs.season` містить значення |
| `edible` | `true` \| `false` | — | `true` = edible + conditionally_edible |
| `search` | string ≤ 100 | — | ILIKE по `name_ua` / `name_lat` |
| `limit` | int 1..100 | 50 | Розмір сторінки |
| `offset` | int ≥ 0 | 0 | Зсув |

```bash
curl "$SUPABASE_URL/functions/v1/catalog?forest=pine,spruce&season=autumn&edible=true&search=білий&limit=50&offset=0"
```

### Response 200

```json
{
  "data": [
    {
      "id": "boletus_edulis",
      "nameUa": "Білий гриб",
      "nameLat": "Boletus edulis",
      "edibility": "edible",
      "edibilityLabel": "Їстівний",
      "redListed": false,
      "rarity": "",
      "hasPhoto": true,
      "top20": true,
      "popular": false,
      "aiRecognition": true,
      "features": "",
      "months": [6, 7, 8, 9, 10, 11],
      "attrs": {
        "color": [],
        "stem": [],
        "tree": ["pine", "spruce", "oak", "birch", "deciduous", "coniferous"],
        "season": ["summer", "autumn"]
      },
      "photos": [{ "url": "https://<PROJECT_REF>.supabase.co/storage/v1/object/public/mushroom-photos/boletus/1.webp" }],
      "peakMonths": [9, 10],
      "zones": ["kyivska", "lvivska", "vinnytska"]
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

Помилки: `invalid_season`, `invalid_edible`, `search_too_long`,
`invalid_pagination`, `limit_out_of_range`, `invalid_offset` → **400**;
`method_not_allowed` → **405**; `db_error` → **500**.

---

## 6. GET /me

Профіль поточного користувача (онбординг-стан). service_role читає `users`
з явним `.eq('id', userId)`.

**Auth:** JWT обов'язковий.

```bash
curl "$SUPABASE_URL/functions/v1/me" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

### Response 200

```json
{
  "data": {
    "id": "auth0uid-0001-4c1a-9b2e-0f1e2d3c4b5a",
    "name": "Грибник",
    "rating": 0,
    "total_verified_picks": 0,
    "home_region": {
      "id": 1,
      "slug": "kyivska",
      "name": "Київська"
    },
    "created_at": "2026-10-12T08:00:00.000Z"
  }
}
```

`home_region: null` — онбординг не завершено (обирай область через `PATCH /me`).

### Помилки

`me_not_found` → **404** (користувач є в Auth, але немає рядка в `users` —
дивись [AUTH_FLOW.md](./AUTH_FLOW.md)); `unauthorized` → **401**;
`method_not_allowed` → **405**; `db_error` → **500**.

---

## 7. PATCH /me

Онбординг та профіль: часткове оновлення `name` та/або `home_region_slug`.
Потрібне хоча б одне поле; невідомі поля ігноруються. Відповідь — той самий
формат, що `GET /me`.

**Auth:** JWT обов'язковий.

### Request

| Поле | Тип | Валідація |
|---|---|---|
| `name` | string | 1..50 символів після trim |
| `home_region_slug` | string | `^[a-z0-9][a-z0-9_-]{1,31}$` (2..32, lowercase) |

```bash
curl -X PATCH "$SUPABASE_URL/functions/v1/me" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Грибник",
    "home_region_slug": "kyivska"
  }'
```

### Response 200

```json
{
  "data": {
    "id": "auth0uid-0001-4c1a-9b2e-0f1e2d3c4b5a",
    "name": "Грибник",
    "rating": 0,
    "total_verified_picks": 0,
    "home_region": {
      "id": 1,
      "slug": "kyivska",
      "name": "Київська"
    },
    "created_at": "2026-10-12T08:00:00.000Z"
  }
}
```

### Помилки

```json
{ "error": "invalid_region_slug" }
```
```json
{ "error": "region_not_found" }
```

`invalid_json`, `invalid_body` (порожнє тіло / не об'єкт), `invalid_name`,
`invalid_region_slug` → **400**; `region_not_found` (slug не існує) → **404**;
`me_not_found` → **404**; `unauthorized` → **401**; `db_error` → **500**.

> Slug → id резолвиться через RPC `find_region_by_slug` (migration
> `20260912000015`). Обмеження «1 зміна регіону / 30 днів» —
> **TODO/V2**, див. [AUTH_FLOW.md](./AUTH_FLOW.md#home-region).

---

## 8. forecast-weather (службовий)

Погода + хвиля для точки (group 8.2). Використовується клієнтом для
діагностики таUI «поточні умови»; основний прогноз йде через `POST /forecast`.

**Auth:** публічний. Graceful degradation — завжди `200` (при збої Open-Meteo
повертає `source: "unavailable"`).

```bash
curl -X POST "$SUPABASE_URL/functions/v1/forecast-weather" \
  -H "Content-Type: application/json" \
  -d '{ "lat": 50.45, "lng": 30.52, "date": "2026-10-12" }'
```

### Response 200

```json
{
  "data": {
    "weather": {
      "tempAvg7d": 13.0,
      "tempAvg14d": 13.0,
      "tempAvg20d": 13.0,
      "tempMin": 9,
      "tempMax": 17,
      "humidity": 70,
      "rain1d": 3,
      "rain2d": 6,
      "rain3d": 16,
      "rain7d": 20,
      "rain14d": 30,
      "rain30d": 50,
      "droughtDays": 0,
      "daysAfterRain": 2,
      "pressure": 1013,
      "pressureTrend": "stable",
      "soilState": "normal",
      "gdd": 240,
      "fetchedAt": "2026-10-12T06:00:00.000Z",
      "source": "open-meteo"
    },
    "wave": "autumn",
    "date": "2026-10-12"
  }
}
```

---

## Guardian endpoints (інтерфейс Наглядача)

Окремий контур безпеки: **не Supabase-JWT**, а власний токен Наглядача
(`X-Guardian-Token`, видається через `guardian-register-*`). ~25 функцій
(`guardian-session-*`, `guardian-ping`, `guardian-sos`, `guardian-tick`,
`guardian-notify`, `guardian-webhook-sms`, …).

Повна документація контуру — **TODO/V2** (окремий документ
`docs/GUARDIAN_API.md`). Для Flutter-команди актуальні лише:
`POST /guardian-register-device` (FCM-токен грибника) та
`POST /guardian-register-guardian-device` (Web Push Наглядача) — обидва
вимагають відповідного контексту сесії; решта — внутрішні.

Ключові відповіді помилок: `unauthorized` / `invalid_token` → **401**,
`not_found` → **404**, `invalid_transition` → **409**, `rate_limited` → **429**.

---

## Посилання

- [docs/README.md](./README.md) — quick-start + regression testing
- [docs/DB_SCHEMA.md](./DB_SCHEMA.md) — схема БД, RLS, ER
- [docs/AUTH_FLOW.md](./AUTH_FLOW.md) — JWT, онбординг, Home Region
