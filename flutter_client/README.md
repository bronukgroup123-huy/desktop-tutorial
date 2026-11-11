# Грибний Радар — Flutter-клієнт

Тонкий клієнт до Supabase Edge Functions `v1-*` (контракт — [`openapi/v1.yaml`](../openapi/v1.yaml),
рішення — [`docs/DECISIONS.md`](../docs/DECISIONS.md)). Бізнес-логіки в клієнті немає:
онбординг (`onboarding.next_step`), підписи, кольори, межі області й ліси приходять із сервера.

## Запуск

```bash
cd flutter_client
cp .env.example .env            # вписати SUPABASE_URL і SUPABASE_PUBLISHABLE_KEY (публічні значення)
flutter pub get
flutter run --dart-define-from-file=.env
```

Генерація коду (`build_runner`) **не потрібна**: моделі й провайдери написані вручну.

## APK для телефону

Workflow `.github/workflows/android.yml` збирає release-APK:
- на кожен push / PR, що змінює `flutter_client/` → **Actions → Android APK → Artifacts → `mushroom-radar-apk`** (zip, зберігається 14 днів);
- на push у `main` → також **Releases → «android-latest»** → файл `mushroom-radar.apk` (завантаження одним тапом);
- вручну: **Actions → Android APK → Run workflow**.

Потрібні **GitHub Secrets** (Settings → Secrets and variables → Actions):

| Секрет | Значення |
|---|---|
| `SUPABASE_URL` | `https://<PROJECT_REF>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | publishable (anon) key з Supabase → Settings → API |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | *необов'язково*: постійний ключ підпису. Без нього APK підписується debug-ключем, і для встановлення нової збірки може знадобитися видалити попередню |

## Вхід через Google на телефоні

Застосунок відкриває вхід у зовнішньому браузері й повертається за deep link
`ua.mushroomradar.app://login-callback/` (`SupabaseConfig.authRedirectUrl`, intent-filter у
`AndroidManifest.xml`). Ця адреса **має бути** в Supabase → Authentication → URL Configuration →
**Redirect URLs** — інакше Supabase перекидає на **Site URL** (наприклад, `localhost`).

## Перевірки

```bash
flutter analyze
flutter test
```

Те саме запускає CI (`.github/workflows/test.yml`, job «Flutter client»).

## Що вміє карта

- **Ліси області** — тап по лісу відкриває прогноз.
- **Тук-туки** (ADR-018): публічні точки інших людей і власні; тап по точці — картка з фото.
  Чужі точки показано приблизно (300–500 м) — так їх віддає сервер.
- **«Тук-тук»**: місце з телефона → камера (один кадр, без галереї) → вид зі списку або
  «Не знаю, що це» → опис → «Лише я» / «Усі». Фото вантажиться за Signed Upload URL
  (`/v1-picks/upload-url` → `PUT` → `/v1-picks`). Чи можна публікувати — вирішує сервер.
- **«Приватні точки»** — показує власні приватні точки.
- **«Аналіз ділянки»** (ADR-015): дотик до карти обирає центр квадрата 5×5 км; розміри та їх
  доступність (10×10 — «Доступно в Pro») і ліміт на сьогодні приходять із `/v1-analysis`.

Камера — пакет `image_picker` (лише `ImageSource.camera`). Після зміни залежностей виконайте
`flutter pub get` і закомітьте оновлений `pubspec.lock`.

## Структура

```
lib/
  core/            конфіг (dart-define), тема, Toast
  data/
    api/           ApiClient (apikey + Bearer, { data }, ApiException)
    models/        Me, RegionSummary, RegionGeometry, ForestZone, Forecast, Pick, Analysis, GeoJSON-хелпери
    repositories/  Auth, Me, Regions, ForestZones, Forecast, Picks, Analysis
    providers.dart Riverpod-провайдери
  features/        екрани (auth, onboarding, splash, map, picks, analysis, …)
test/              юніт-тести шару даних і роутера, widget-тест входу
```
