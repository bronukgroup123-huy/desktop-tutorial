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

## Перевірки

```bash
flutter analyze
flutter test
```

Те саме запускає CI (`.github/workflows/test.yml`, job «Flutter client»).

## Структура

```
lib/
  core/            конфіг (dart-define), тема, Toast
  data/
    api/           ApiClient (apikey + Bearer, { data }, ApiException)
    models/        Me, RegionSummary, RegionGeometry, ForestZone, Forecast, GeoJSON-хелпери
    repositories/  Auth, Me, Regions, ForestZones, Forecast
    providers.dart Riverpod-провайдери
  features/        екрани (auth, onboarding, splash, map, …)
test/              юніт-тести шару даних і роутера, widget-тест входу
```
