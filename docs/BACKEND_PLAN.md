# Грибний Радар — План реалізації бекенду (v1.7)

**Статус:** робочий план бекенду під Flutter-клієнт.
**Основа:** Канонічний план v8.2, аудит репозиторію (листопад 2026), рекомендації щодо MVP,
**рішення Product Owner від 2026-11-09 — [DECISIONS.md](./DECISIONS.md) (ADR-001…015)**.
**Принцип:** бекенд — джерело істини (No-Rewrite Contract). Клієнт лише рендерить.

### Що змінилось у v1.1–v1.7

| ADR | Рішення | Вплив на план |
|---|---|---|
| 001 | Гість = Supabase Anonymous Sign-In; SQLite — лише кеш/черга | B1.6 переписано, + CAPTCHA, cron-очищення |
| 002 | Фото — Signed Upload URL, без base64 | B3.1 розбито на upload-url + create |
| 003 | Мінна небезпека — тільки статичний банер ДСНС | B4.3 спрощено; `hazard_zones` видалено |
| 004 | Без custom domain Supabase; Cloudflare лише для Vercel | B7.4 уточнено |
| 005 | Оплата — RevenueCat | B6.3 — вебхук RevenueCat |
| 006 | ШІ тільки локально (ONNX ~300 МБ), без сервера | B5.0, B5.3–B5.5 переписано |
| 007 | Розпізнавання без лімітів | B5.4 скасовано; `recognition_usage` не створюється |
| 008 | Одна модель, Pro без AI-переваг | B5.5 — один manifest для всіх; склад Pro у B6.3 |
| 009 | Фото для навчання — тільки opt-in | Нова задача B5.6, таблиця `training_samples`, bucket `training_data` |
| 010 | Матриця Безкоштовно / Pro (публічні точки й теплова — з Лісовика або Pro; без сімейного тарифу) | B2.8, B3.2, B3.5, B4.6, B4.8, B6.3; B6.4 видалено |
| 011 | Приватні точки: 5/добу безкоштовно, Pro — безліміт | B3.2 |
| 012 | Бали за тести знань | Нова задача B3.10; таблиці `quiz_*` |
| 013 | 6 рівнів + сертифікат знань (Грибознавець, «Досвідчений…», Хранитель лісу) | B3.2, B3.7 |
| 014 | Чесний відгук «Знайшли?» | Нова задача B3.11 |
| 015 | Машинний прогноз: 1 ділянка 5×5 (free) / до 3 ділянок 5×5 або 10×10 (Pro), ліміти 5 / 10 на ділянку; **полігони й ділянки — тільки Home Region**, «Вся Україна» в Pro — лише перегляд | B1.2, B1.8, B2.9–B2.11; B2.7 замінено |

---

## 0. Як читати цей документ

- Розділ 1 — що вже є і де розриви (аудит коду, не документації).
- Розділ 2 — правила API, які обов'язкові для кожного нового ендпоінта.
- Розділ 3 — фази робіт, синхронізовані з тижнями Flutter. Кожна задача має ID
  (`B1.3`), файли, критерій готовності (DoD).
- Розділ 4 — нові таблиці.
- Розділ 5 — що свідомо відкладено у v1.1+.
- Розділ 6 — відкриті питання до власника продукту.

Позначки: 🔴 блокує Flutter / безпеку, 🟡 потрібно до релізу, ⚪ можна пізніше.

---

## 1. Поточний стан (аудит коду)

### 1.1 Що готово і переходить без змін

| Блок | Де | Стан |
|---|---|---|
| Схема БД, RLS, PostGIS | `supabase/migrations/` (37 файлів) | ✅ |
| Ліси: 20 807 полігонів + RPC `get_forest_zones_geojson` | `20261021120*` | ✅ |
| ForecastEngine (46 параметрів/вид, хвилі, GDD, crowd, калібрування) | `_shared/forecast/` | ✅, покрито тестами + golden dataset |
| Guardian: state machine, geofence, SOS, rescue, GPX, cron tick, Push/SMS/Telegram | `_shared/guardian/`, `guardian-*` | ✅ |
| Auth + профіль: `GET/PATCH /me`, `GET /regions` (slug-only) | `me/`, `regions/` | ✅ |
| `POST /picks` з EXIF-перевіркою (1 км / 24 год) і вирізанням EXIF | `picks/index.ts` | ✅ (документація помилково пише «TODO») |
| Каталог 326 видів, фото в Storage | `catalog/`, bucket `mushroom-catalog-photos` | ✅ |
| Rate limit (IP) для `forecast`, `catalog`, `regions`, `picks` | `_shared/rate-limit.ts`, міграція `..._ip_rate_limit` | ✅ |

### 1.2 Знайдені розриви

| # | Проблема | Наслідок | Задача |
|---|---|---|---|
| G1 🔴 | `POST /picks` завжди пише `pick_type: "private"` — немає вибору приватності | Тук-тук не може стати friends/public | B3.1 |
| G2 🔴 | `v1-forecast` віддає числовий `score` (0.83) | Порушує заборону «ніяких відсотків» | B2.1 |
| G3 🔴 | `v1-forecast` має `homeRegionId: null` — RegionGuard вимкнено | Прогноз для будь-якої точки України | B2.1 |
| G4 🟡 | `v1-forecast`: `when_label = "Хвиля: autumn"` (англ. код у тексті), `why_labels` = технічні рядки (`"temp 13 within fruiting range"`) | Не відповідає Response Shaping | B2.2 |
| G5 🟡 | `v1-*` повертають помилки як `{error: true, message}`, решта API — `{error: "code", message?}` | Два формати помилок у клієнті | B0.4 |
| G6 🟡 | `v1-forecast`, `v1-forest-zones` без rate limit | Відкриті для зловживань (service_role всередині) | B0.4 |
| G7 🔴 | Немає ендпоінта геометрії області | Flutter не може намалювати маску «острова» без hardcode geojson | B1.1 |
| G8 🟡 | `deploy.yml` НЕ робить `supabase db push` (документація каже, що робить) | Міграції накочуються вручну | B0.1 |
| G9 🟡 | У CI не запускаються `deno test` | Регресії не ловляться | B0.1 |
| G10 🟡 | Немає Dependabot / Gitleaks (обіцяно в Security Roadmap, Етап 1) | | B0.2 |
| G11 🟡 | `smoke-test.yml` містить пароль тестового користувача відкритим текстом | Секрет у репо | B0.2 |
| G12 ⚪ | Легасі-стек: `db/migrations/`, `compose.yaml`, `api/` (FastAPI), `web/`, `init-scripts/` — паралельна схема без зв'язку з Supabase | Плутанина «яка схема справжня» | B0.3 |
| G13 🟡 | Документація відстає: 24 vs 37 міграцій, немає `v1-*`, EXIF/rate-limit позначені як TODO | Flutter-команда працює з неактуальним контрактом | B0.5 |
| G14 🔴 | Немає таблиць: друзі, бали рейтингу, згоди (EULA), підписки | Блокує Тук-тук friends, рейтинг, онбординг, Pro | Фази 1–6 |
| G15 🟡 | Немає OpenAPI-специфікації (план v8.2 вважає її готовою) | Немає генерації Dart-клієнта | B0.5 |

---

## 2. Правила API (контракт для всіх нових ендпоінтів)

1. **Іменування:** нові клієнтські ендпоінти — `v1-<resource>` (Edge Function). Старі
   `forecast`, `picks`, `me`, … лишаються для веб-прототипу; Flutter переходить на `v1-*`
   поступово. Ламати старі контракти заборонено.
2. **Формат успіху:** `{ "data": ... }`; списки — `+ total, limit, offset` або `next_cursor`.
3. **Формат помилки:** `{ "error": "snake_case_code", "message"?: "людський текст UA" }`.
   Спільний хелпер у `_shared/http.ts` (B0.4).
4. **Response Shaping:** усе, що бачить користувач, сервер віддає готовим:
   `*_label` (UA), `*_color` (hex), `*_icon` (ключ іконки). Жодних чисел-ймовірностей,
   жодних enum-кодів, з яких клієнт мав би будувати текст. Мова — `Accept-Language`
   (`uk` за замовчуванням, `en` — заготовка).
5. **Стани:** кожен об'єкт зі state machine повертає `status`, `status_label` і
   `actions: ["extend", "close", ...]` — список дозволених дій. Клієнт показує тільки їх.
6. **Авторизація:** JWT Supabase (`Authorization: Bearer`) + `apikey`. Публічні ендпоінти —
   тільки читання довідників і прогнозу. Усе, що пише, — JWT.
7. **Ідемпотентність:** запити, які можуть прийти з офлайн-черги, приймають
   `client_id` (UUID, генерує клієнт). Повтор із тим самим `client_id` → `200` з
   тим самим об'єктом, а не дубль.
8. **Rate limit:** кожен `v1-*` проходить через `_shared/rate-limit.ts`. `429 rate_limited` +
   `Retry-After`.
9. **Home Region:** будь-які геодані фільтруються областю користувача (або bbox ⊂ області).
   Регіон з JWT-профілю, не з тіла запиту.
10. **Безпека SQL:** тільки RPC / query builder supabase-js. Ніяких рядкових SQL з даними
    користувача. Нові таблиці — `ENABLE + FORCE RLS` у тій самій міграції.
11. **Тести:** кожен ендпоінт — deno-тест (валідація, 401/403/429, happy path) у
    `supabase/tests/`. Кожна таблиця з RLS — SQL-тест у `supabase/tests/*.sql`.

---

## 3. Фази

Тижні відповідають roadmap Flutter (Частина 5 плану v8.2). Бекенд іде на ~1 тиждень
**попереду** клієнта: Flutter-екран тижня N спирається на ендпоінти, закриті у тиждень N−1.

### Фаза 0 — Гігієна та CI (тиждень 0, паралельно з початком Flutter)

| ID | Задача | Файли | DoD |
|---|---|---|---|
| B0.1 🔴 | CI: job `test` (`deno test supabase/tests/ --allow-net --allow-read`) на кожен PR; `deploy` — `supabase db push` перед деплоєм функцій, тільки після зеленого `test` | `.github/workflows/test.yml`, `deploy.yml` | PR з падаючим тестом не мержиться; міграція з `main` з'являється в БД без ручних дій |
| B0.2 🔴 | Dependabot (npm, pub, github-actions); Gitleaks у CI; пароль smoke-тесту → `secrets.SMOKE_TEST_PASSWORD` | `.github/dependabot.yml`, `.github/workflows/security.yml`, `smoke-test.yml` | Gitleaks зелений на всій історії або з задокументованим allowlist |
| B0.3 🟡 | Легасі (`db/`, `api/`, `web/`, `compose.yaml`, `init-scripts/`) перенести в `legacy/` з README «не використовується» | — | У корені лишається тільки актуальний стек |
| B0.4 🔴 | `_shared/http.ts`: `ok()`, `fail(code, status, message?)`, `withRateLimit()`, `withAuth()`; перевести на нього `v1-forecast`, `v1-forest-zones` | `_shared/http.ts`, `v1-*` | Обидва `v1-*` повертають `{error:"code"}` і мають rate limit; тести на 429 |
| B0.5 🟡 | `openapi/v1.yaml` (OpenAPI 3.1) — тільки `v1-*` + `me`, `regions`, `picks`, `catalog`; оновити `docs/API.md`, `DB_SCHEMA.md`, `README.md` (37 міграцій, EXIF/rate limit реалізовано) | `openapi/v1.yaml`, `docs/*` | `openapi_generator` у Flutter генерує клієнт без ручних правок; лінт специфікації в CI |
| B0.6 🟡 | Staging-проєкт Supabase (окремий `PROJECT_ID`), деплой гілки `staging` | `deploy.yml` | Flutter debug-збірка дивиться на staging |

### Фаза 1 — Онбординг і Карта (бекенд до кінця тижня 1)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B1.1 🔴 | `GET v1-regions/{slug}/geometry` | Спрощений кордон області (`ST_SimplifyPreserveTopology`, ~50–150 КБ), bbox, центр, рекомендований zoom. Кеш `Cache-Control: max-age=86400` + `ETag` | Flutter малює маску без локального geojson; 27 областей < 200 КБ кожна |
| B1.2 🔴 | `v1-forest-zones`: перевірка bbox ⊂ Home Region (для авторизованих), спрощення геометрії за zoom (`?z=`), поле `type_label` / `type_color` для кольорового кодування типів лісу | Без JWT — тільки bbox розміром ≤ області | На zoom 9 відповідь ≤ 1 МБ; кольори приходять з сервера |
| B1.3 🔴 | Згода EULA/Privacy | Таблиця `user_consents`; `PATCH /me` приймає `accept_terms_version`; `GET /me` віддає `onboarding: { region_done, terms_done, next_step }` | Клієнт не вирішує, який екран онбордингу показати — читає `next_step` |
| B1.4 🔴 | Вхід по телефону | Supabase Phone Auth + **Send SMS Hook** → TurboSMS (вже є токен для Guardian). Rate limit OTP | OTP приходить на український номер; ≤ 5 спроб/год на номер |
| B1.5 🟡 | Apple Sign In | Налаштування провайдера в Supabase + bundle id | Вхід працює на TestFlight-збірці |
| B1.6 🔴 | Гостьовий режим (**ADR-001**) | Увімкнути Anonymous Sign-Ins + CAPTCHA (Turnstile). Гість має JWT з `is_anonymous=true` і реальний UUID; RLS-хелпер `is_registered()` забороняє `public`/`friends` точки, сесії Наглядача, SOS, друзів. Реєстрація — `linkIdentity`, UUID не змінюється. `GET /me` → `is_guest`. Cron: видалення анонімних акаунтів без активності > 90 днів | Гість бачить карту, прогноз, створює private-точки; SOS/public → `403 registration_required`; після linkIdentity усі точки гостя на місці (тест) |
| B1.8 🟡 | Режим перегляду «Вся Україна», Pro (**ADR-015 §15.2**) | `GET v1-regions/geometry?all=true&level=low` — сильно спрощені кордони всіх областей одним файлом (≤ 300 КБ, кеш), тільки `features.map_all_ukraine`. У цьому режимі немає полігонів лісів і вибору точок. `v1-forest-zones` віддає полігони **тільки в межах Home Region** для всіх (`403 outside_home_region`, `400 bbox_too_large`) | Жодного запиту полігонів поза Home Region (тест); зміна Home Region → полігони нової області тим самим запитом |

### Фаза 2 — Прогноз (бекенд до кінця тижня 2)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B2.1 🔴 | `v1-forecast`: прибрати `score`/`probability` з відповіді; RegionGuard з JWT (`home_region_id` профілю) | Для гостя — регіон з anonymous-профілю | Немає числових полів ймовірності; точка поза областю → `403 outside_home_region` |
| B2.2 🔴 | Людські підписи | `when_label`: «Зараз — 3 дні після дощу», «Через 2–4 дні»; `where_label`; `why_labels`: «Дощ 16 мм 3 дні тому», «Температура 13° — оптимально». Таблиця перекладів matcher-кодів у `_shared/forecast/labels.ts` | Snapshot-тест на golden dataset: усі label — українською, без англ. кодів |
| B2.3 🔴 | Блок погоди в відповіді `v1-forecast` | `weather: { temp_label, humidity_label, rain_label, icon }` з тих самих даних Open-Meteo | Один запит дає і погоду, і Top-1/Top-2 |
| B2.4 🔴 | Отруйні — ніколи | Фільтр за `mushroom_catalog.edibility IN ('edible','conditionally_edible')` у фінальному кроці engine + тест | Тест: правило з отруйним видом не потрапляє в top1/alternative |
| B2.5 🟡 | `POST v1-area-summary` (Bottom Sheet лісу, 5×5 км) | Тип лісу, вік, площа, кількість verified-тук-туків за 7 днів (без координат), Top-1/2 | Одна відповідь на тап по полігону ≤ 800 мс (p95) |
| B2.6 🟡 | Кеш погоди | Таблиця `weather_cache` (grid 0.1°, TTL 1 год) — менше викликів Open-Meteo | Повторний прогноз у тій самій клітинці не ходить в Open-Meteo |
| B2.8 🟡 | Горизонт прогнозу (**ADR-010**) | `v1-forecast` приймає `date` до +3 днів безкоштовно, до +16 (межа Open-Meteo) з `features.forecast_extended`; понад +7 днів — `reliability_label: "Орієнтовний прогноз"` | Free з датою +5 → `403 pro_required`; Pro з +12 → 200 |
| ~~B2.7~~ | ~~`POST v1-forecast/batch`~~ | **Замінено B2.10** (порівняння ділянок, ADR-015) | — |
| B2.9 🔴 | Машинний прогноз — аналіз ділянки (**ADR-015**) | `POST v1-analysis { lat, lng, size_km, date, area_id? }` → Top-1/Top-2 з рівнями (без відсотків), тип і вік лісу в квадраті, базова погода (free) / розширена (Pro). Таблиці `analysis_areas` (слоти 1 free / 3 Pro, `size_km` 5 free / 5–10 Pro), `analysis_usage`. Ліміти: free 5/добу, Pro 10/добу на ділянку → `429 analysis_limit_reached`. RegionGuard: **тільки Home Region для всіх** | Free 6-й аналіз → 429; free 10×10 → `403 pro_required`; Pro ділянка в іншій області → `403 outside_home_region`; у відповіді немає числових ймовірностей |
| B2.10 🟡 | Порівняння ділянок, Pro (**ADR-015**) | `POST v1-analysis/compare { area_ids[2..3], date }` → ранжування на сервері + `summary_label` («Ділянка Б найкраща на вихідні: …»); списує по 1 аналізу з кожної ділянки | Ранжування тільки на сервері; ліміт рахується по кожній ділянці (тест) |
| B2.11 🟡 | Розширена погода і карти аналізу, Pro (**ADR-015**) | Сітка Open-Meteo 3×3 (5×5 км) / 5×5 (10×10 км) через `weather_cache`: опади 30 днів, вологість і температура ґрунту, GDD, тренд тиску → готові `*_label` + дані для графіків; шари «опади», «вологість ґрунту», «тип/вік лісу» як GeoJSON-сітка з `color` | Один аналіз = не більше одного запиту до Open-Meteo (тест на кеш) |

### Фаза 3 — Тук-тук (бекенд до кінця тижня 3)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B3.0 🔴 | `POST v1-picks/upload-url` (**ADR-002**) | `{ client_id, content_type, size_bytes }` → `{ upload_url, path, expires_at }` через `createSignedUploadUrl`; шлях `<user_id>/<client_id>.<ext>`; ліміт 5 МБ, JPEG/PNG/WebP. Політика Storage: INSERT тільки у власну папку. Cron: видалення «сиріт» (файл без pick > 24 год) | Клієнт завантажує файл PUT-запитом зі стрімінгом з диска; повторний виклик з тим самим `client_id` повертає валідний URL на той самий шлях |
| B3.1 🔴 | `POST v1-picks` (**ADR-002**) | `{ client_id, path, lat, lng, captured_at, visibility, mushroom_type, ... }` — **без base64**. Сервер читає файл зі Storage, перевіряє magic bytes / розмір / EXIF (GPS ≤ 1 км, час ≤ 24 год від `captured_at`), вирізає EXIF перезаписом об'єкта. Перенести EXIF-логіку з `picks/index.ts` у `_shared/picks/exif.ts` | Повтор із тим самим `client_id` → `200` без дубля; запит без файлу у Storage → `422 photo_not_uploaded`; старий `POST /picks` (base64) працює для веб-прототипу |
| B3.2 🔴 | Ліміти публічних точок (**ADR-010**) | Безкоштовно: Мандрівник/Слідопит — `public` заборонено (`403 level_required`), Лісовик — 5/добу. Pro: за рівнями ADR-013 (Мандрівник 5 / Слідопит 20 / Грибознавець 20 / Лісовик 50 / Хранитель 100 / Майстер ∞); free Хранитель — 10/добу. Private (**ADR-011**): безкоштовно — 5/добу з будь-якого рівня (і для гостя), Pro — без ліміту. `friends` — без ліміту. Перевірка в БД-функції `can_publish_pick(user_id)` | Free-Слідопит → 403; free-Лісовик 6-та точка → `429 daily_limit_reached`; Pro-Мандрівник 5 точок → ок |
| B3.3 🔴 | `GET v1-picks/map?bbox=` | Точки для карти: свої (усі), друзів (`friends`), чужі `public`. Готові `marker_color` (сірий pending / зелений verified), `status_label` | Чужі private ніколи не віддаються (RLS-тест) |
| B3.4 🟡 | `PATCH / DELETE v1-picks/{id}` | Зміна видимості тільки автором; видалення = soft delete | RLS-тест: чужий pick не змінюється |
| B3.5 🟡 | Теплова карта `GET v1-heatmap?bbox=` | Агрегація verified public у сітку (H3 або квадрати 1 км); клітинка показується тільки при ≥ 5 точках (k-анонімність). Доступ (**ADR-010**): безкоштовно — **тільки з рівня Лісовик**: Home Region, останні 3 дні (нижче Лісовика → `403 level_required`); Pro / Майстер — вся Україна + `?period=` 3d / 7d / 30d. Без доступу → `403 pro_required` | Жодна клітинка не розкриває одну точку; тест на 403 для period/bbox поза правами |
| B3.6 🔴 | Друзі | Таблиця `friendships` (запит → прийнято), `POST v1-friends/invite` (код/посилання), `GET v1-friends` | `friends`-точки бачать тільки прийняті друзі |
| B3.7 🔴 | Рейтинг і рівні (**ADR-012, ADR-013**) | `rating_events` (ledger: +бали за verified, 8 джерел активності з добовими лімітами, тести; −20 rejected, −50 скарга); тригер оновлює `users.rating`. `users.knowledge_certified_at`, `curriculum_version`. Конфіг `rating_levels` (6 рівнів, `certified_label`). `compute_level()`; `GET /me` → `level_code`, `level_label`, `is_certified`, `next_level_label`, `next_level_hint` | Рейтинг = сума ledger (SQL-тест); 120 балів без тестів → Слідопит, з усіма тестами → Грибознавець; Лісовик + тести → «Досвідчений лісовик»; 1001 бал без тестів → не Майстер |
| B3.11 🟡 | Відгук «Знайшли?» (**ADR-014**) | `POST v1-trips/{id}/outcome` (або за `forecast_view_id`): `found` / `not_found` / `other`; таблиця `forecast_views`; перевірка контексту походу і відстані ≤ 5 км; відкладене нарахування +2 через 24 год (cron); `users.feedback_trust`; запис у `calibration_log`. `GET v1-diary/forecast-accuracy` → «Прогноз для вас збувся N з M» | Відгук без походу → `422 no_trip_context`; другий відгук за добу — без балів; суперечливий відгук знижує довіру (тест) |
| B3.8 🟡 | Верифікація | `pending → verified/rejected`; автоверифікація Слідопита (3 підтверджені → наступні verified); `POST v1-picks/{id}/confirm` (інший користувач поруч ≤ 500 м) | State machine у БД-функції, тести переходів |
| B3.9 🟡 | Вплив на прогноз | Вже є `crowd.ts`: перевірити, що private-точки впливають анонімно, friends — ні, public verified — максимально | Тести `crowd.test.ts` розширено під 3 рівні |
| B3.10 🟡 | Тести знань (**ADR-012**) | Таблиці `quiz_modules`, `quiz_questions` (текст, варіанти, правильна відповідь, фото з довідника, пояснення), `quiz_attempts`. `GET v1-quizzes` (модулі, прогрес, `points_label`), `POST v1-quizzes/{id}/start` → питання **без відповідей** + `attempt_id`, `POST v1-quizzes/attempts/{id}/submit` → результат, пояснення, бали (через `rating_events`, один раз на модуль, поріг 80%). `GET v1-quizzes/{id}/practice` — офлайн-набір для тренування без балів. Скрипт генерації чернеток питань з `mushroom_catalog` + `species_twins` → рев'ю міколога | Відповіді не потрапляють у клієнт до submit (тест); повторне проходження не дає балів (тест); сума балів за тести ≤ 120 (тест); фото-питання — тільки для 132 видів з фото; проходження всіх модулів виставляє `knowledge_certified_at` |

### Фаза 4 — Безпека (бекенд до кінця тижня 4)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B4.1 🔴 | `docs/GUARDIAN_API.md` + OpenAPI для клієнтської частини Guardian | Створення сесії, продовження, закриття, SOS, трек, реєстрація FCM | Flutter-команда реалізує екран без читання коду функцій |
| B4.2 🔴 | `actions[]` і `status_label` у відповідях сесії | Правило 5 розділу 2 | Клієнт не містить таблиці переходів |
| B4.3 🟡 | Банер мінної небезпеки (**ADR-003**) | **Без полігонів і шарів.** `GET v1-app-config` → `safety_notices: [{ id, title, body, link_label, link_url, severity }]` (зберігається в `feature_flags.value`). Посилання — тільки офіційні ресурси ДСНС | Текст банера змінюється без релізу застосунку; у БД і API немає жодних геоданих про небезпечні зони |
| B4.4 🟡 | Авто-перевірка «Все добре?» | Новий стан у state machine: нерухомість > N хв далеко від старту → push грибнику → без відповіді за M хв → alert Наглядачу | Тест `tick.test.ts` на новий сценарій |
| B4.5 🟡 | SOS-SMS без інтернету | Формат SMS із координатами + посилання; `guardian-webhook-sms` приймає вхідне SMS «SOS lat,lng» від грибника | Сценарій «тільки 2G» задокументовано і протестовано |
| B4.6 🟡 | GPX — тільки Pro (**ADR-010**) | `guardian-owner-gpx` / `guardian-session-gpx` для грибника вимагають `features.gpx_tracks`, інакше `403 pro_required`. Живий трек для Наглядача під час сесії лишається безкоштовним. Ретенція: архів Pro — 30 днів; треки безкоштовних — видалення після закриття сесії + 24 год (cron) | Тести: free → 403 на GPX; Наглядач бачить трек free-грибника; cron видаляє прострочені |
| B4.8 🔴 | Ліміт Наглядачів (**ADR-010**) | Сесія: 1 Наглядач безкоштовно, до 3 — з `features.guardians_3`. Перевірка в `guardian-session-create` | Спроба додати 2-го без Pro → `403 pro_required` |
| B4.7 🔴 | Гостю — без SOS | `403 registration_required` (B1.6) | Тест |

### Фаза 5 — Довідник і Розпізнавання (бекенд до кінця тижня 5)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
> **ADR-006:** розпізнавання тільки локальне (квантований ONNX BioCLIP 2, ~300 МБ).
> Бекенд не отримує фото для розпізнавання і не має ендпоінтів `v1-recognize/*`.
> Роль бекенду — постачати **дані** для офлайну: модель, каталог, двійників, тексти безпеки.

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B5.0 🔴 | **Валідація моделі на пристрої** (до інтеграції, спільно з Flutter) | Квантований ONNX (int8): розмір, пікова пам'ять, час інференсу на 3 фото на цільових телефонах, top-1/top-3 точність на 132 видах з фото; маппінг класів моделі → `mushroom_catalog.id`. Перевірити ліміти розміру asset pack у Play Asset Delivery | Звіт `docs/AI_BENCHMARK.md`; затверджено мінімальні вимоги до пристрою; таблиця `model_labels` (клас моделі → id виду) |
| B5.1 🔴 | `GET v1-catalog/sync?since=` | Дельта-синхронізація для офлайн-SQLite: описи (з `mushroom_descriptions.js`, ключі нормалізовано до snake_case), атрибути, фільтри, публічні CDN-URL фото, **`danger_level`, `danger_banner_label`, `twins[]`**, глобальні тексти дисклеймера | Перший sync < 3 МБ (без фото); повторний — тільки змінене; довідник 326 видів працює повністю офлайн |
| B5.2 🔴 | Двійники | Таблиця `species_twins` з `twins_200.csv` (вид, двійник, ознаки відмінності, небезпека) → у `v1-catalog/sync` | Для кожного отруйного двійника є картка відмінностей |
| B5.3 🔴 | Правила безпечної подачі (дані, не логіка) | Свідомий виняток Thin Client (ADR-006): клієнт показує червоний банер, якщо серед top-3 є вид з `danger_level ≥ poisonous`. Сервер постачає лише поля і тексти. Специфікація правила — у `docs/API.md` | Тест бекенду: кожен `poisonous`/`deadly_poisonous` вид має `danger_banner_label`; жоден текст не містить «їстівний» як висновок ШІ |
| ~~B5.4~~ | ~~Ліміт розпізнавань~~ | **Скасовано ADR-007:** розпізнавання безлімітне і безкоштовне | — |
| B5.5 🟡 | Дистрибуція моделі | Основний шлях — Play Asset Delivery (поза бекендом). Запасний — Storage bucket `models/` + `GET v1-models/manifest` (**одна модель для всіх, ADR-008**) (`version`, `sha256`, `size_bytes`, `url`, `min_app_version`) для завантаження через `dio`/`flutter_downloader` з докачуванням | Модель оновлюється без релізу; контрольна сума перевіряється перед використанням. Оцінено вартість egress Supabase (~300 МБ × кількість завантажень) |
| B5.6 🟡 | Фото для навчання ШІ, opt-in (**ADR-009**) | Приватний bucket `training_data` (читання тільки service_role). `POST v1-training/upload-url` → PUT у Storage (`<model_version>/<uuid>.jpg`, ≤ 2 МБ, ≤ 1024 px) → `POST v1-training/submit { path, model_version, predictions[], user_label?, month }`: сервер перевіряє magic bytes, вирізає EXIF, пише `training_samples`. Rate limit (напр. 30/день) у таблиці лімітів, не пов'язаній із записами датасету. Cron: видалення непідтверджених файлів > 24 год. **Ніяких ML-пайплайнів** | У `training_samples` і шляхах Storage немає `user_id`, координат і точного часу (SQL-тест); файл без EXIF (тест); без натискання кнопки клієнт не робить жодного запиту (вимога до Flutter, перевіряється в рев'ю) |

### Фаза 6 — Профіль, GDPR, Pro (бекенд до кінця тижня 6)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B6.1 🔴 | `GET v1-me/export` | JSON усіх даних користувача (профіль, точки, сесії, треки) | GDPR-експорт за ≤ 30 с |
| B6.2 🔴 | `DELETE v1-me` | Ghost User: public verified точки переписуються на системного `ghost`, решта видаляється; `auth.users` видаляється | SQL-тест: після видалення немає PII |
| B6.3 🟡 | Підписки через RevenueCat (**ADR-005**) | Склад Pro — матриця **ADR-010** (без AI-переваг, ADR-008); ключі `features[]` — ADR-010 §10.3. Майстер отримує Pro через `entitlements.source='rating'`, знижка Лісовика 20% — промо-офер RevenueCat. `app_user_id` = Supabase UUID. Edge Function `v1-revenuecat-webhook`: секрет у Vault, перевірка заголовка `Authorization`, ідемпотентність за `event.id` (`billing_events`), оновлення `entitlements` (plan: `pro_season`/`pro_year`, `valid_until`, `source=revenuecat`). `GET /me` → `is_pro`, `features[]`, `ads_enabled` | Тестові події RevenueCat (INITIAL_PURCHASE, RENEWAL, EXPIRATION, CANCELLATION) коректно змінюють доступ; повтор події не дублює запис; клієнт перевіряє тільки `features[]` |
| B6.5 ⚪ | Щоденник | `GET v1-diary` — походи (сесії) + точки по днях | |

### Фаза 7 — Перед релізом (тижні 7–8)

| ID | Задача | DoD |
|---|---|---|
| B7.1 🔴 | Strix (AI-пентест) на staging: IDOR, JWT, RLS-обходи; виправлення | Звіт + закриті critical/high |
| B7.2 🔴 | Rate limit на auth (≤ 5 спроб входу/хв), OTP, усі `v1-*` | Тести 429 |
| B7.3 🟡 | Sentry для Edge Functions + алерти в Telegram (сплеск 401/500) | Тестова помилка доходить до Telegram |
| B7.4 🟡 | Периметр (**ADR-004**) | Supabase — вбудований захист + наш rate limit на всіх `v1-*` + CAPTCHA для анонімного входу/OTP. Безкоштовний Cloudflare — тільки перед Vercel (PWA Наглядача): WAF managed rules, bot fight mode. CSP і HSTS у `vercel.json` / `next.config.mjs` | PWA за Cloudflare; CSP без `unsafe-inline` для скриптів; кожен `v1-*` має тест на 429 |
| B7.5 🟡 | Бекапи: PITR / щоденний dump, перевірене відновлення на staging | Відновлення пройшло |
| B7.6 🟡 | Навантажувальний тест `v1-forecast`, `v1-forest-zones` (k6), 200 RPS | p95 < 1 с |
| B7.7 🟡 | Golden dataset: план збору 100+ записів після бети (петля «Знайшли? Так/Ні» — `POST v1-trips/{id}/outcome` → `calibration_log`) | Ендпоінт працює, дані йдуть у калібрування |

---

## 4. Нові таблиці (зведено)

| Таблиця | Фаза | Ключові поля | RLS |
|---|---|---|---|
| `user_consents` | 1 | user_id, doc (`eula`/`privacy`), version, accepted_at | свої |
| `weather_cache` | 2 | cell_id, date, payload, fetched_at | service_role |
| `friendships` | 3 | requester_id, addressee_id, status, created_at | учасники |
| `rating_events` | 3 | user_id, delta, reason, pick_id, created_at | читання — свої; запис — service_role |
| `pick_confirmations` | 3 | pick_id, confirmer_id, distance_m | учасники |
| `species_twins` | 5 | species_id, twin_id, difference_label, danger | читання всім |
| `model_labels` | 5 | model_version, class_index, species_id | читання всім |
| `training_samples` | 5 | id, storage_path, model_version, predictions JSONB, user_label, month, created_at — **без user_id/координат** | service_role (запис через Edge Function) |
| `entitlements` | 6 | user_id, plan, valid_until, source (`revenuecat`) | свої (читання) |
| `billing_events` | 6 | event_id PK, type, user_id, payload, received_at | service_role |
| `mushroom_picks` (+колонки) | 3 | client_id UNIQUE(user_id, client_id), captured_at, deleted_at | існуючі політики + тести |

Скасовано рішеннями PO: `hazard_zones` (ADR-003), `recognition_usage` (ADR-007).

---

## 5. Відкладено у v1.1+ (свідомо)

- Стрічка «Спільнота», коментарі, скарги (окрім ledger для штрафів).
- Чати (Supabase Realtime) і групові чати Лісовика.
- Рейтинг «Король лісу» як окремий екран (дані вже є з `rating_events`).
- Експертні прогнози Грибного Майстра.
- Реклама (UMP/Native Ads) — потрібен лише серверний прапор `ads_enabled` у `GET /me` (= `!is_pro`), його закладаємо в B6.3.
- Історична теплова карта (імпорт відкритих спостережень GBIF/iNaturalist) — кандидат на v1.1 як рішення холодного старту.

---

## 6. Відкриті питання до власника продукту

Затверджено: матриця Безкоштовно/Pro (ADR-010, 011), тести і всі 8 джерел балів (ADR-012),
система з 6 рівнів із сертифікатом знань (ADR-013), чесний відгук «Знайшли?» (ADR-014),
машинний прогноз (ADR-015).

Назви, пороги та привілеї нових рівнів підтверджено — [ADR-013 §13.5](./DECISIONS.md#135-привілеї-та-ліміти-рівнів-підтверджено-po-2026-11-09):
назви нових рівнів («Грибознавець», «Хранитель лісу»), пороги (Хранитель 501–1000,
Майстер 1001+ і обов'язковий сертифікат), привілеї та ліміти нових рівнів.

---

## 7. Робочий блок 1 (≈ 5 робочих днів)

**Мета блоку:** розблокувати Flutter-тиждень 1 (онбординг + карта) і поставити захисну
сітку (CI, тести, секрети), щоб усі наступні зміни бекенду йшли безпечно.
Кожна задача — окремий коміт у гілці `claude/project-rb2fo8`, з тестами.

| # | Задача | Що саме робимо | Результат для Flutter / проєкту |
|---|---|---|---|
| 1 | **B0.1 CI з тестами** | `.github/workflows/test.yml`: `deno lint`, `deno check`, `deno test` для `supabase/tests/**` і `supabase/functions/*_test.ts` на кожен push/PR. `deploy.yml`: деплой лише після зелених тестів + крок `supabase db push` | Регресії ловляться до деплою; міграції накочуються автоматично |
| 2 | **B0.2 Безпека репозиторію** | `.github/dependabot.yml` (npm, `web-guardian`, pub `flutter_client`, github-actions); `security.yml` з Gitleaks; пароль зі `smoke-test.yml` → секрет `SMOKE_TEST_PASSWORD` | Етап 1 Security Roadmap виконано |
| 3 | **B0.4 Єдиний HTTP-шар** | `_shared/http.ts`: `ok()`, `fail(code, status, message)`, `withRateLimit()`, `requireUser()` (JWT → user + `home_region_id` + `is_anonymous`). Перевести `v1-forecast`, `v1-forest-zones`; ліміти в `IP_RATE_LIMITS` | Один формат помилок `{error, message}`; rate limit на всіх `v1-*` |
| 4 | **B1.1 Кордон області** | Міграція: RPC `get_region_geometry(slug, tolerance)` → спрощений GeoJSON + bbox + центр + zoom. Edge Function `v1-regions` (`/geometry`), `Cache-Control` + `ETag` | Маска «острова» без локального geojson у застосунку |
| 5 | **B1.2 Ліси тільки Home Region** | `v1-forest-zones` вимагає JWT (гість теж має JWT — ADR-001); полігони лише для `home_region_id` користувача; `403 outside_home_region`, `400 bbox_too_large`; поле `type_label` / `type_color` | Карта отримує ліси лише своєї області з кольорами з сервера |
| 6 | **B1.6 Гостьовий режим** | `config.toml`: `enable_anonymous_sign_ins = true`; міграція: SQL-хелпер `is_registered()`; RLS — анонім не створює `public`/`friends` точки; `guardian-session-create` / `guardian-sos` → `403 registration_required`; `GET /me` → `is_guest` | Кнопка «Гість» працює з реальним UUID; реєстрація без втрати даних |
| 7 | **B1.3 Онбординг з сервера** | Міграція `user_consents`; `PATCH /me` приймає `accept_terms_version`; `GET /me` → `onboarding: { region_done, terms_done, next_step }` | Застосунок не вирішує сам, який екран онбордингу показати |
| 8 | **B2.1 Швидкий фікс прогнозу** | `v1-forecast`: прибрати `score` і `probability` з відповіді; RegionGuard за `home_region_id` з JWT | Виконано заборону «ніяких відсотків»; прогноз тільки у своїй області |
| 9 | **B0.5 Документація контракту** | `openapi/v1.yaml` для ендпоінтів блоку; оновити `docs/API.md` (v1-*, EXIF і rate limit реалізовано, 37 міграцій) | Dart-клієнт генерується з OpenAPI |

**Не входить у блок:** людські підписи прогнозу (B2.2), тук-туки, рейтинг, тести знань —
наступні блоки. Перенесення легасі (B0.3) — лише після підтвердження PO.

**Потрібно від PO (Supabase / GitHub, Claude цього зробити не може):**
1. GitHub Secrets: `SUPABASE_DB_PASSWORD` (для `db push`), `SMOKE_TEST_PASSWORD`.
2. Supabase Dashboard → Authentication → увімкнути **Anonymous Sign-Ins**
   (`config.toml` діє тільки для локального стека).
3. Рішення: переносимо `db/`, `api/`, `web/`, `compose.yaml`, `init-scripts/` у `legacy/`?

**Обмеження перевірки:** Deno-тести і лінт запускаються локально та в CI. Міграції
перевіряються на локальному Supabase (Docker), якщо він підніметься в середовищі; інакше —
SQL-тестами в CI після `db push` на staging.
