# Грибний Радар — План реалізації бекенду (v1.0)

**Статус:** робочий план бекенду під Flutter-клієнт.
**Основа:** Канонічний план v8.2, аудит репозиторію (листопад 2026), рекомендації щодо MVP.
**Принцип:** бекенд — джерело істини (No-Rewrite Contract). Клієнт лише рендерить.

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
| G14 🔴 | Немає таблиць: друзі, бали рейтингу, згоди (EULA), підписки, небезпечні зони | Блокує Тук-тук friends, рейтинг, онбординг, Pro, безпеку | Фази 1–6 |
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
| B1.6 🔴 | Гостьовий режим | **Рекомендація:** Supabase Anonymous Sign-In замість чисто локального режиму. Гість отримує JWT з `is_anonymous=true`; RLS забороняє йому `public` точки та SOS; при реєстрації — `linkIdentity`, дані зберігаються | Гість бачить карту і прогноз; спроба SOS/public → `403 registration_required` з `message` |

### Фаза 2 — Прогноз (бекенд до кінця тижня 2)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B2.1 🔴 | `v1-forecast`: прибрати `score`/`probability` з відповіді; RegionGuard з JWT (`home_region_id` профілю) | Для гостя — регіон з anonymous-профілю | Немає числових полів ймовірності; точка поза областю → `403 outside_home_region` |
| B2.2 🔴 | Людські підписи | `when_label`: «Зараз — 3 дні після дощу», «Через 2–4 дні»; `where_label`; `why_labels`: «Дощ 16 мм 3 дні тому», «Температура 13° — оптимально». Таблиця перекладів matcher-кодів у `_shared/forecast/labels.ts` | Snapshot-тест на golden dataset: усі label — українською, без англ. кодів |
| B2.3 🔴 | Блок погоди в відповіді `v1-forecast` | `weather: { temp_label, humidity_label, rain_label, icon }` з тих самих даних Open-Meteo | Один запит дає і погоду, і Top-1/Top-2 |
| B2.4 🔴 | Отруйні — ніколи | Фільтр за `mushroom_catalog.edibility IN ('edible','conditionally_edible')` у фінальному кроці engine + тест | Тест: правило з отруйним видом не потрапляє в top1/alternative |
| B2.5 🟡 | `POST v1-area-summary` (Bottom Sheet лісу, 5×5 км) | Тип лісу, вік, площа, кількість verified-тук-туків за 7 днів (без координат), Top-1/2 | Одна відповідь на тап по полігону ≤ 800 мс (p95) |
| B2.6 🟡 | Кеш погоди | Таблиця `weather_cache` (grid 0.1°, TTL 1 год) — менше викликів Open-Meteo | Повторний прогноз у тій самій клітинці не ходить в Open-Meteo |
| B2.7 ⚪ | `POST v1-forecast/batch` (кілька збережених точок, ранжування на сервері) | Замінює `scorePoint/rankPoints` з `landing.html` | Клієнт не ранжує точки |

### Фаза 3 — Тук-тук (бекенд до кінця тижня 3)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B3.1 🔴 | `POST v1-picks` | Поля `visibility` (`private`/`friends`/`public`), `client_id` (ідемпотентність, B-правило 7), `captured_at` (для офлайн-черги). Фото — **signed upload URL** (`POST v1-picks/upload-url` → PUT у Storage) замість base64 у JSON | Повтор із тим самим `client_id` → без дубля; фото 5 МБ не ламає офлайн-синхронізацію |
| B3.2 🔴 | Ліміти за рівнем | Мандрівник 5 / Слідопит 20 / Лісовик 50 public на добу; private — без ліміту. Перевірка в БД-функції | Перевищення → `429 daily_limit_reached` з `message` |
| B3.3 🔴 | `GET v1-picks/map?bbox=` | Точки для карти: свої (усі), друзів (`friends`), чужі `public`. Готові `marker_color` (сірий pending / зелений verified), `status_label` | Чужі private ніколи не віддаються (RLS-тест) |
| B3.4 🟡 | `PATCH / DELETE v1-picks/{id}` | Зміна видимості тільки автором; видалення = soft delete | RLS-тест: чужий pick не змінюється |
| B3.5 🟡 | Теплова карта `GET v1-heatmap?bbox=` | Агрегація verified public у сітку (H3 або квадрати 1 км); клітинка показується тільки при ≥ 5 точках (k-анонімність). Доступ: Лісовик — свій регіон, Майстер/Pro — вся Україна | Жодна клітинка не розкриває одну точку |
| B3.6 🔴 | Друзі | Таблиця `friendships` (запит → прийнято), `POST v1-friends/invite` (код/посилання), `GET v1-friends` | `friends`-точки бачать тільки прийняті друзі |
| B3.7 🔴 | Рейтинг | `rating_events` (ledger: +бали за verified, −20 rejected, −50 скарга); тригер оновлює `users.rating`; `level` + `level_label` у `GET /me` | Рейтинг завжди = сума ledger (SQL-тест) |
| B3.8 🟡 | Верифікація | `pending → verified/rejected`; автоверифікація Слідопита (3 підтверджені → наступні verified); `POST v1-picks/{id}/confirm` (інший користувач поруч ≤ 500 м) | State machine у БД-функції, тести переходів |
| B3.9 🟡 | Вплив на прогноз | Вже є `crowd.ts`: перевірити, що private-точки впливають анонімно, friends — ні, public verified — максимально | Тести `crowd.test.ts` розширено під 3 рівні |

### Фаза 4 — Безпека (бекенд до кінця тижня 4)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B4.1 🔴 | `docs/GUARDIAN_API.md` + OpenAPI для клієнтської частини Guardian | Створення сесії, продовження, закриття, SOS, трек, реєстрація FCM | Flutter-команда реалізує екран без читання коду функцій |
| B4.2 🔴 | `actions[]` і `status_label` у відповідях сесії | Правило 5 розділу 2 | Клієнт не містить таблиці переходів |
| B4.3 🔴 | **Шар мінної небезпеки** | Таблиця `hazard_zones` (полігон, тип, джерело, дата); імпорт відкритих даних (ДСНС / Національний орган з питань протимінної діяльності); `GET v1-hazards?bbox=`; попередження в `v1-forecast` і `v1-area-summary`; `POST v1-picks` у зоні → `422 hazard_zone` | Точка в небезпечній зоні: прогноз з червоним warning, тук-тук не створюється |
| B4.4 🟡 | Авто-перевірка «Все добре?» | Новий стан у state machine: нерухомість > N хв далеко від старту → push грибнику → без відповіді за M хв → alert Наглядачу | Тест `tick.test.ts` на новий сценарій |
| B4.5 🟡 | SOS-SMS без інтернету | Формат SMS із координатами + посилання; `guardian-webhook-sms` приймає вхідне SMS «SOS lat,lng» від грибника | Сценарій «тільки 2G» задокументовано і протестовано |
| B4.6 🟡 | Ретенція GPX | Cron: видаляти треки старші 7 днів (30 для Pro) | Тест на cron-функцію |
| B4.7 🔴 | Гостю — без SOS | `403 registration_required` (B1.6) | Тест |

### Фаза 5 — Довідник і Розпізнавання (бекенд до кінця тижня 5)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B5.0 🔴 | **Спайк BioCLIP 2** (до початку інтеграції) | Розмір ONNX (fp16/int8), час інференсу на бюджетному Android, top-1/top-3 точність на 132 видах з фото | Звіт `docs/AI_BENCHMARK.md`; рішення: on-device / сервер / легка модель |
| B5.1 🔴 | `GET v1-catalog/sync?since=` | Дельта-синхронізація для офлайн-SQLite: описи (з `mushroom_descriptions.js`, ключі нормалізовано до snake_case), атрибути, публічні CDN-URL фото | Перший sync < 3 МБ (без фото); повторний — тільки змінене |
| B5.2 🔴 | Двійники | Таблиця `species_twins` з `twins_200.csv` (вид, двійник, ознаки відмінності, небезпека); віддається в каталозі і в результаті розпізнавання | Для кожного отруйного двійника є картка відмінностей |
| B5.3 🔴 | Безпечна подача результату | `POST v1-recognize/feedback` + серверні правила подачі: якщо серед top-3 є отруйний → `danger_banner`; ніколи «їстівний» як висновок ШІ | Тест на правило банера |
| B5.4 🟡 | Ліміти розпізнавання | 10/день базово, без ліміту Pro — лічильник на сервері (навіть якщо інференс офлайн — синхронізується) | |
| B5.5 🟡 | Дистрибуція моделі | Storage bucket `models/` + `GET v1-models/manifest` (версія, sha256, розмір, URL) | Клієнт оновлює модель без релізу в Play |

### Фаза 6 — Профіль, GDPR, Pro (бекенд до кінця тижня 6)

| ID | Задача | Деталі | DoD |
|---|---|---|---|
| B6.1 🔴 | `GET v1-me/export` | JSON усіх даних користувача (профіль, точки, сесії, треки) | GDPR-експорт за ≤ 30 с |
| B6.2 🔴 | `DELETE v1-me` | Ghost User: public verified точки переписуються на системного `ghost`, решта видаляється; `auth.users` видаляється | SQL-тест: після видалення немає PII |
| B6.3 🟡 | Підписки | `entitlements` (user, plan: `pro_season`/`pro_year`/`family`, valid_until, source); вебхук перевірки покупок Google Play (напряму через Play Developer API або через RevenueCat); `is_pro` + `features[]` у `GET /me` | Клієнт перевіряє тільки `features[]`, не план |
| B6.4 🟡 | Сімейний Pro | Грибник + до 3 Наглядачів | |
| B6.5 ⚪ | Щоденник | `GET v1-diary` — походи (сесії) + точки по днях | |

### Фаза 7 — Перед релізом (тижні 7–8)

| ID | Задача | DoD |
|---|---|---|
| B7.1 🔴 | Strix (AI-пентест) на staging: IDOR, JWT, RLS-обходи; виправлення | Звіт + закриті critical/high |
| B7.2 🔴 | Rate limit на auth (≤ 5 спроб входу/хв), OTP, усі `v1-*` | Тести 429 |
| B7.3 🟡 | Sentry для Edge Functions + алерти в Telegram (сплеск 401/500) | Тестова помилка доходить до Telegram |
| B7.4 🟡 | Cloudflare WAF | Можливо тільки з **custom domain** Supabase (платна опція) — інакше WAF лише для веб-частини на Vercel. Рішення — див. питання 6.4 | |
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
| `hazard_zones` | 4 | polygon, kind, source, source_date, label | читання всім |
| `species_twins` | 5 | species_id, twin_id, difference_label, danger | читання всім |
| `recognition_usage` | 5 | user_id, day, count | свої |
| `entitlements` | 6 | user_id, plan, valid_until, source, raw_receipt | свої (читання) |
| `mushroom_picks` (+колонки) | 3 | client_id UNIQUE(user_id, client_id), captured_at, deleted_at | існуючі політики + тести |

---

## 5. Відкладено у v1.1+ (свідомо)

- Стрічка «Спільнота», коментарі, скарги (окрім ledger для штрафів).
- Чати (Supabase Realtime) і групові чати Лісовика.
- Рейтинг «Король лісу» як окремий екран (дані вже є з `rating_events`).
- Експертні прогнози Грибного Майстра.
- Реклама (UMP/Native Ads) — потрібен лише серверний прапор `ads_enabled` у `GET /me` (= `!is_pro`), його закладаємо в B6.3.
- Історична теплова карта (імпорт відкритих спостережень GBIF/iNaturalist) — кандидат на v1.1 як рішення холодного старту.
- Прогноз 7–10 днів (Pro).

---

## 6. Відкриті питання до власника продукту

1. **Гостьовий режим:** Anonymous Sign-In (рекомендовано, дані не губляться при реєстрації)
   чи суто локальний SQLite, як у плані v8.2?
2. **Фото тук-тука:** переходимо на signed upload URL (рекомендовано для офлайн-черги)
   чи лишаємо base64 у JSON?
3. **Мінна небезпека:** чи є домовленість/доступ до актуальних даних про забруднені
   території? Від цього залежить обсяг B4.3.
4. **Cloudflare WAF:** беремо Supabase custom domain (платно) чи обмежуємось захистом
   Supabase + WAF тільки для Vercel?
5. **Оплата:** напряму Google Play Billing чи RevenueCat (простіше, комісія)?
6. **BioCLIP 2:** якщо спайк B5.0 покаже, що модель завелика для офлайну, — серверне
   розпізнавання з офлайн-довідником як fallback прийнятне для релізу?

---

## 7. Порядок старту (наступні 5 робочих днів)

1. B0.1, B0.2, B0.4 — CI з тестами, Gitleaks, єдиний формат помилок.
2. B1.1, B1.2 — геометрія області та ліси під Home Region (розблоковує карту Flutter).
3. B1.3, B1.6 — онбординг через `next_step` і гостьовий режим.
4. B2.1, B2.2 — виправлення `v1-forecast` (без `score`, RegionGuard, людські підписи).
5. B0.5 — OpenAPI для всього, що вище, і генерація Dart-клієнта.
