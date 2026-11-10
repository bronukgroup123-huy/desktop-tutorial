# Поточна задача: B3.0 + B3.1 — бекенд «Тук-тук» (ADR-002, ADR-018)

> Якщо користувач пише «виконуй» / «роби» / «почни» без деталей — **це та задача**.
> Виконай її повністю: код, міграція, тести, OpenAPI, коміт, пуш, PR у `main`.
> Питати нічого не потрібно: усі продуктові рішення вже прийняті й описані нижче.
> Якщо щось у коді суперечить цьому документу — правда в `docs/DECISIONS.md`.

## 0. Прочитай перед роботою (обов'язково)
1. `CLAUDE.md` — правила репозиторію.
2. `docs/DECISIONS.md` — **ADR-001** (гість), **ADR-002** (Signed Upload URL), **ADR-010/011/013**
   (хто і скільки публічних/приватних точок), **ADR-015 §15.2** (тільки Home Region),
   **ADR-018** (весь розділ — головне рішення цієї задачі).
3. `docs/BACKEND_PLAN.md` — розділ 2 «Правила API», Фаза 3: рядки **B3.0, B3.1, B3.2**.

## 1. Що робить користувач (контекст)
Натискає «Тук-тук» → камера застосунку (без галереї, одне фото) → вибирає вид зі списку
довідника (або «Не знаю») → необов'язковий опис → видимість `private` або `public`.
Застосунок: (1) просить у сервера посилання для завантаження фото, (2) завантажує фото
PUT-запитом, (3) створює точку. На телефоні працює локальна модель ШІ — її результат
приходить як **підказка** `ai_check` (не доказ). Ця задача — **лише бекенд** (Flutter не чіпати).

## 2. Що вже є в коді (не винаходь заново)
| Що | Де |
|---|---|
| Спільний HTTP-шар: `handle`, `ok`, `fail`, `HttpError`, `readJson`, `assertMethod`, `requireUser`, `assertRegistered`, `loadHomeRegionId`, `requireHomeRegion`, `enforceRateLimit` + `V1_RATE_LIMITS`, `serviceClient`, `supabaseTokenVerifier` | `supabase/functions/_shared/http.ts` |
| Приклад v1-функції: тонкий `index.ts` + логіка з інжектованими залежностями в `_shared/v1/*.ts` | `supabase/functions/v1-regions/index.ts`, `_shared/v1/regions.ts`, `_shared/v1/me.ts` |
| Мок supabase-js для тестів | `supabase/tests/v1/mock-db.ts`; приклади — `supabase/tests/v1/*.test.ts` |
| Старий `POST /picks` (base64, веб-прототип) з EXIF-перевіркою (`verifyExif`, `haversineKm`, `dmsToDecimal`, `stripExifFromJpeg`) | `supabase/functions/picks/index.ts` |
| Валідація і magic bytes | `supabase/functions/_shared/forecast/picks-validate.ts` (`detectImageFormat`) |
| Таблиця `mushroom_picks` (`geom`, `photo_url`, `mushroom_type`, `pick_type` з `friends`, `shared_with`, `verification_status` pending/verified/conditional/rejected) | `supabase/migrations/20260912000001_forecast_foundation.sql` |
| Bucket `mushroom-photos` (приватний, 5 МіБ, jpeg/png/webp) + політики «тільки своя папка» | `supabase/migrations/20260912000012_storage_picks.sql` |
| RLS читання точок (зараз чужі `public` видно **з точними координатами**) | `supabase/migrations/20261109120500_fix_private_picks_region_visibility.sql` |
| Гість — лише private (RESTRICTIVE-політики, `is_registered()`) | `supabase/migrations/20261109120300_guest_mode_and_region_change_source.sql` |
| Довідник видів `mushroom_catalog(id TEXT, name_ua, edibility, …)` | `supabase/migrations/20260912000004_mushroom_catalog.sql` |
| Стрічка `GET /picks` (scopes mine/friends/public/region) читає `geom` клієнтом користувача | `supabase/functions/_shared/forecast/picks-list.ts` |
| SQL/RLS-тести (запускаються в CI на чистій БД) | `supabase/tests/rls_block1.sql` (там є точка `friends` — онови) |

## 3. Що зробити

### 3.1 Міграція (новий файл `supabase/migrations/2026111100xxxx_tuk_tuk_adr018.sql`)
Версія — більша за останню наявну міграцію; ім'я унікальне.
- `pick_type`: лише `private` / `public`. Наявні `friends` → `private`; `shared_with` очистити.
  Онови CHECK. Політику `mushroom_picks_read` перепиши без `shared_with`.
- Нові колонки `mushroom_picks`:
  `client_id UUID` (унікально разом з `user_id`), `species_id TEXT NULL REFERENCES mushroom_catalog(id)`
  (NULL = «Не знаю»), `description TEXT NULL` (≤ 500 символів, CHECK),
  `ai_check JSONB NULL`, `twin_alert BOOLEAN NOT NULL DEFAULT false`,
  `display_geom GEOGRAPHY(Point,4326) NULL` (зсунута точка для чужих очей), `deleted_at TIMESTAMPTZ NULL`.
- CHECK: `pick_type = 'public'` ⇒ `species_id IS NOT NULL`.
- **Закрити витік точних координат (ADR-018 §18.5):** чужі `public` точки більше не читаються
  напряму через RLS (SELECT — тільки власні). Публічні точки інших віддаватимуться лише через
  Edge Function з service_role і тільки `display_geom`. Перевір `picks-list.ts`: scopes
  `public`/`region` мають віддавати координати з `display_geom`, а не `geom` (читай їх
  через `adminDb` з явним фільтром `pick_type = 'public' AND deleted_at IS NULL`, або видали
  scope `friends` і переведи решту — обери найпростіше, що проходить тести). Scope `friends` — видалити.
- Індекс на `(user_id, client_id)`; індекс для лімітів `(user_id, pick_type, created_at)`.
- Політику Storage для вставки у свою папку не послаблювати.

### 3.2 `POST v1-picks/upload-url` (B3.0)
Тіло: `{ client_id: uuid, content_type: "image/jpeg"|"image/png"|"image/webp", size_bytes: int }`.
- `requireUser`; Home Region обов'язковий (`requireHomeRegion`).
- `size_bytes` ≤ 5 242 880, інакше `400 photo_too_large`; інший тип → `400 invalid_photo_format`.
- Шлях `<user_id>/<client_id>.<jpg|png|webp>`; `createSignedUploadUrl(path, { upsert: true })`
  у bucket `mushroom-photos` (service_role). Повтор з тим самим `client_id` → новий валідний URL
  на **той самий** шлях.
- Відповідь `200 { data: { upload_url, path, token, expires_at } }`.
- Rate limit: додай `"v1-picks": 30` у `V1_RATE_LIMITS`.

### 3.3 `POST v1-picks` (B3.1)
Тіло: `{ client_id, path, lat, lng, captured_at (ISO), visibility: "private"|"public",
species_id: string|null, description?: string, ai_check?: { model_version, top: [{species_id, level}], match, twin_alert } }`.
Порядок перевірок і коди помилок:
1. `requireUser`; `visibility = public` і гість → `403 registration_required` (`assertRegistered`).
2. Валідація тіла → `422 validation_error` (з `message` українською).
3. `path` мусить починатися з `<user_id>/` → інакше `403 forbidden`.
4. Ідемпотентність: точка з тим самим `(user_id, client_id)` вже є → `200` з нею ж, без дубля.
5. Home Region: точка поза полігоном області користувача → `403 outside_home_region`.
   Використай `loadHomeRegionId` + наявний RPC `point_in_region(lat, lng, region_id)`
   (`supabase/migrations/20260912000011_point_in_region.sql`).
6. `species_id = null` і `public` → `422 species_required`; невідомий `species_id` → `422 unknown_species`.
7. Опис: обрізати пробіли, ≤ 500 символів, прибрати телефони, e-mail і посилання (замінити на «…»);
   винеси у чисту функцію `_shared/picks/text.ts` з тестами.
8. Ліміти (ADR-010/011/013, B3.2). Стан БД зараз: таблиць `entitlements` (Pro) і `rating_events`
   **ще немає**, є лише `users.rating INT`. Тому зроби SQL-функцію
   `can_create_pick(p_user_id uuid, p_visibility text)` → `(allowed bool, code text, message text)`
   (SECURITY DEFINER, EXECUTE лише service_role) з такими правилами **до появи Pro і рівнів**:
   - private: ≤ 5 за останні 24 год (не рахуючи `deleted_at`) → інакше `429 daily_limit_reached`;
   - public: `users.rating` < 201 (нижче «Лісовик», ADR-013 §13.1) → `403 level_required`
     з `message` «Публічні точки — з рівня Лісовик. Поки що зробіть приватний тук-тук.»;
     рейтинг ≥ 201 → ≤ 5 публічних за 24 год (free Лісовик) → інакше `429 daily_limit_reached`.
   - Додай у функцію коментар `-- TODO(B3.7, B6.3): Pro-ліміти й рівні за ADR-010/013`.
9. Файл: завантажити з Storage за `path`; немає → `422 photo_not_uploaded`. Перевірити розмір і
   magic bytes (`detectImageFormat`). EXIF: перенести логіку з `picks/index.ts` у
   `_shared/picks/exif.ts` (обидві функції — стара й нова — імпортують звідти). EXIF **не
   робить точку verified** (ADR-018: перевіряють люди); результат лише записати в `ai_check`/лог.
   EXIF вирізати перезаписом об'єкта (JPEG).
10. `display_geom` для `public`: стабільний зсув 300–500 м, детермінований від id точки
    (напр. SHA-256(id) → кут і відстань). Чиста функція `_shared/picks/fuzz.ts` + тести
    (стабільність, відстань у межах 300–500 м).
11. Вставка: `verification_status = 'pending'` завжди; `twin_alert = ai_check?.twin_alert === true`;
    `mushroom_type = species_id ?? 'unknown'` (сумісність зі старим кодом прогнозу).
12. Відповідь `201 { data: { id, visibility, status_label: "Перевіряється" | "Приватна точка",
    marker_color } }` — підписи й кольори з сервера (Thin Client).

Роутинг: одна функція `supabase/functions/v1-picks/index.ts`, шляхи `/v1-picks/upload-url` і
`/v1-picks`; логіка — `supabase/functions/_shared/v1/picks.ts` з інжектованими `db`, `storage`,
`verify`, `now` (як у `regions.ts`), щоб тестувати без мережі.

### 3.4 Не ламати
- Старий `POST /picks` (base64) працює далі для веб-прототипу, але пише лише `private`.
- `deploy.yml` деплоїть усі функції з `--no-verify-jwt` автоматично — нічого додавати не треба.

## 4. Тести (обов'язково, CI має бути зеленим)
- `supabase/tests/v1/picks.test.ts` — щонайменше: upload-url (розмір, тип, той самий шлях при повторі,
  401 без токена); create: гість + public → 403, «Не знаю» + public → 422, повтор `client_id` → 200
  без другої вставки, немає файлу → 422, чужий `path` → 403, поза областю → 403, ліміт → 429,
  verification завжди `pending`, `display_geom` тільки для public.
- `_shared/picks/text.ts`, `fuzz.ts`, `exif.ts` — юніт-тести.
- SQL: онови `supabase/tests/rls_block1.sql` (прибери `friends`) і додай
  `supabase/tests/rls_picks_adr018.sql`: сусід не читає чужу public точку напряму; CHECK
  public ⇒ species_id; гість не вставляє public.
- `openapi/v1.yaml` — описати обидва ендпоінти; лінт Redocly має пройти.

Перевірка локально (ті самі команди, що в `.github/workflows/test.yml`):
```
deno check supabase/functions/*/index.ts supabase/tests/ supabase/functions/_shared/
deno test --no-check --allow-net --allow-read --allow-env supabase/tests/ supabase/functions/_shared/
```

## 5. Заборонено
- base64-фото в новому API; розпізнавання ШІ на сервері (ADR-006); числові ймовірності у відповідях;
  точні координати чужих точок у будь-якій відповіді; секрети в коді; зміни в `docs/devops-exercises/`;
  зміни Flutter-клієнта в цій задачі.

## 6. Готово, коли
- [ ] Міграція + обидва ендпоінти + тести + OpenAPI.
- [ ] Усі тести CI зелені (Tests, Security).
- [ ] У `docs/BACKEND_PLAN.md` B3.0 і B3.1 позначені ✅ з коротким підсумком.
- [ ] Цей файл оновлено: розділ «Поточна задача» замінено на наступну (B3.3 `GET v1-picks/map`)
      або на «Немає активної задачі».
- [ ] PR у `main` українською: що зроблено, як перевірено, що лишилось (B3.2 повністю — після B3.7).
