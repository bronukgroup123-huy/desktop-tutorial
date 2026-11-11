# Поточна задача: B3.3 — карта тук-туків (`GET v1-picks/map`, `GET v1-picks/{id}`) (ADR-018)

> Якщо користувач пише «виконуй» / «роби» / «почни» без деталей — **це та задача**.
> Виконай її повністю: код, тести, OpenAPI, коміт, пуш, PR у `main`.
> Питати нічого не потрібно: усі продуктові рішення вже прийняті й описані нижче.
> Якщо щось у коді суперечить цьому документу — правда в `docs/DECISIONS.md`.

Попередня задача (B3.0 + B3.1, створення тук-тука) виконана 2026-11-11 —
підсумок у `docs/BACKEND_PLAN.md`, розділ 8.

## 0. Прочитай перед роботою (обов'язково)
1. `CLAUDE.md` — правила репозиторію.
2. `docs/DECISIONS.md` — **ADR-018** §18.2 (карта), §18.5 (місце публічної точки), §18.4
   (статуси перевірки); **ADR-015 §15.2** (тільки Home Region); **ADR-001** (гість).
3. `docs/BACKEND_PLAN.md` — розділ 2 «Правила API», рядок **B3.3**, розділ 8 (що вже зроблено).

## 1. Що робить користувач (контекст)
Відкриває карту своєї області й одразу бачить публічні точки інших: сірі — «Перевіряється»,
зелені — «Підтверджено». Перемикач «Приватні точки» додає власні приватні. Тап по точці
відкриває картку: фото, назва виду, опис, дата, статус, кнопка «Поскаржитися» і
застереження «Фото користувача — не порада їсти гриб». Ця задача — **лише бекенд**.

## 2. Що вже є в коді (не винаходь заново)
| Що | Де |
|---|---|
| Функція `v1-picks`: маршрутизація (`parsePicksRoute`), `POST /upload-url`, `POST /` | `supabase/functions/v1-picks/index.ts`, `_shared/v1/picks.ts` |
| Підписи й кольори статусів (`pickPresentation`) | `_shared/v1/picks.ts` |
| Спільний HTTP-шар (`requireUser`, `loadHomeRegionId`, `requireHomeRegion`, `enforceRateLimit`, `ok`, `HttpError`) | `_shared/http.ts` |
| Колонки `mushroom_picks`: `geom` (точне місце), `display_geom` (зсув 300–500 м, у `public` завжди є), `species_id`, `description`, `verification_status`, `twin_alert`, `captured_at`, `deleted_at`, `photo_url` | міграція `20261111000000_tuk_tuk_adr018.sql`, `docs/DB_SCHEMA.md` |
| RLS: клієнт читає **лише власні** точки; чужі — тільки через service_role | та сама міграція |
| Розбір `geography` з PostgREST (EWKB-hex) — `parseEwkbPoint` | `_shared/forecast/picks-list.ts` |
| Перевірка bbox у межах області (зразок) | `_shared/v1/forest-zones.ts`, RPC `get_forest_zones_geojson_region` |
| Підписані посилання на фото (`createSignedUrls`, TTL 600 с) | `_shared/forecast/picks-list.ts` |
| Мок supabase-js і приклади тестів | `supabase/tests/v1/mock-db.ts`, `supabase/tests/v1/picks.test.ts` |

## 3. Що зробити

### 3.1 Міграція: RPC для карти (новий файл, версія більша за `20261111000000`)
`get_picks_map(p_user_id uuid, p_region_id int, p_min_lng, p_min_lat, p_max_lng, p_max_lat,
p_include_mine boolean, p_limit int)` → рядки точок. `SECURITY DEFINER`, `search_path = ''`,
EXECUTE лише `service_role` (зразок — `create_pick`).
- Чужі точки: `pick_type = 'public'`, `deleted_at IS NULL`, `verification_status <> 'rejected'`,
  точка в області `p_region_id`. Повертати **тільки** координати `display_geom`.
- **Фільтр bbox для чужих точок — за `display_geom`, не за `geom`.** Інакше, звужуючи bbox,
  можна «намацати» справжнє місце точки.
- Власні точки (`user_id = p_user_id`): публічні — завжди; приватні — лише якщо
  `p_include_mine`. Для власних повертати точні координати (`geom`) і `is_exact = true`.
- Числові `lat` / `lng` рахувати в SQL (`ST_Y`, `ST_X`), щоб не розбирати EWKB у коді.
- `p_limit + 1` рядків, щоб обробник знав, чи є ще точки. Просторовий індекс (GiST) на
  `display_geom` для публічних невидалених точок.

### 3.2 `GET v1-picks/map?bbox=minLng,minLat,maxLng,maxLat&mine=true|false`
- `requireUser` (гість теж); Home Region обов'язковий; rate limit `v1-picks`.
- `bbox` необов'язковий (без нього — вся область); некоректний → `400 invalid_bbox`;
  bbox поза областю → `403 outside_home_region`; більший за область → `400 bbox_too_large`
  (ті самі правила, що в `v1-forest-zones`).
- Відповідь `200 { data: { points: [...], truncated: bool } }`, точка:
  `{ id, lat, lng, is_exact, is_mine, visibility, species_id, name_label, status_label,
  marker_color }`. Ліміт — 500 точок.
- `name_label` — назва виду з довідника (`mushroom_catalog.name_ua`) або «Не знаю, що це».
- Жодних числових ймовірностей і жодних точних координат чужих точок.

### 3.3 `GET v1-picks/{id}` (картка точки)
- Свою точку бачить автор (будь-яку невидалену). Чужу — лише `public`, не `rejected`, не
  видалену, **в області користувача**; інакше `404 pick_not_found` (не `403`, щоб не
  підтверджувати існування чужих приватних точок).
- Відповідь: `{ id, lat, lng, is_exact, is_mine, visibility, species_id, name_label,
  description, captured_at, created_at, status_label, marker_color, photo_url (signed, 600 с),
  disclaimer_label: "Фото користувача — не порада їсти гриб", actions: [...] }`.
  `actions`: для чужої точки `["report"]`, для своєї `["edit", "delete"]` (самі дії — B3.4, B3.12).
- Імені автора та його id у відповіді немає.

### 3.4 Не ламати
- `POST v1-picks` і `POST v1-picks/upload-url` — без змін; старі `GET/POST /picks` — без змін.

## 4. Тести (обов'язково, CI має бути зеленим)
- `supabase/tests/v1/picks-map.test.ts`: 401; без області → 409; некоректний / завеликий /
  чужий bbox; у відповіді для чужих точок немає полів із точними координатами;
  `mine=true` додає власні приватні; `truncated`; картка: чужа приватна → 404, чужа rejected
  → 404, своя приватна → 200 з точними координатами, підписи й кольори з сервера.
- SQL `supabase/tests/rls_picks_map.sql`: чужі приватні не повертаються; чужа публічна
  повертається з `display_geom` (координати ≠ `geom`); фільтр bbox працює за `display_geom`
  (bbox навколо точного місця, що не містить зсунутого, точку **не** повертає); `rejected` і
  видалені не повертаються; RPC недоступний ролі `authenticated`.
- `openapi/v1.yaml` — обидва ендпоінти; лінт Redocly має пройти.

Перевірка локально (ті самі команди, що в `.github/workflows/test.yml`):
```
deno check supabase/functions/*/index.ts supabase/tests/ supabase/functions/_shared/
deno test --no-check --allow-net --allow-read --allow-env supabase/tests/ supabase/functions/_shared/
```

## 5. Заборонено
- Точні координати чужих точок у будь-якій відповіді (і фільтр за ними, що їх розкриває);
  ім'я чи id автора в картці чужої точки; числові ймовірності; base64-фото; секрети в коді;
  зміни в `docs/devops-exercises/`; зміни Flutter-клієнта в цій задачі.

## 6. Готово, коли
- [ ] Міграція (RPC + індекс) + обидва ендпоінти + тести + OpenAPI.
- [ ] Усі тести CI зелені (Tests, Security).
- [ ] У `docs/BACKEND_PLAN.md` B3.3 позначено ✅ з коротким підсумком; `docs/API.md` оновлено.
- [ ] Цей файл оновлено: наступна задача (B3.4 `PATCH / DELETE v1-picks/{id}`) або
      «Немає активної задачі».
- [ ] PR у `main` українською: що зроблено, як перевірено, що лишилось.
