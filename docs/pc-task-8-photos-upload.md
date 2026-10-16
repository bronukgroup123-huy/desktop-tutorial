# PC-TASK #8 — Фото довідника → Supabase Storage CDN

## Мета
Завантажити 560 webp-фото (89 MB) з 4 папок у корені репозиторію у публічний Supabase Storage bucket `mushroom-catalog-photos` і перезаписати URL у `mushroom_catalog.js` на CDN-адреси.

Після цього довідник (tab-recognize) на `desktop-tutorial-eta-tan.vercel.app/landing.html` показуватиме фото грибів.

## Необхідне
- Доступ до Supabase Dashboard → Settings → API → `SUPABASE_SERVICE_ROLE_KEY`
- Node.js v24+
- Інтернет (для upload 89 MB)

## Кроки (виконати на ПК)

```bash
cd /workspaces/desktop-tutorial
git pull origin main
```

### 1. Змінні середовища
```bash
export SUPABASE_URL="https://wrukmuxdbkbmkygfasai.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<скопіювати з Dashboard → API>"
```

### 2. Бульк-уpload фото (≈5–10 хв)
```bash
node scripts/upload_catalog_photos.mjs
```
Скрипт ідемпотентний (`upsert: true`) — можна перезапускати.
Ключ `SUPABASE_SERVICE_ROLE_KEY` не виводиться у логи.

### 3. Перезапис URL у каталізі (≈1 хв)
```bash
node scripts/rewrite_catalog_photo_urls.mjs
```
Виводить статистику (замінено / пропущено / помилки) та приклади перших 3 заміни.

### 4. Коміт + push
```bash
git add web-guardian/public/mushroom_catalog.js
git commit -m "feat(catalog): photos from Supabase Storage CDN"
git push origin main
```

### 5. Vercel автодеплой
Vercel автоматично перерозгорне `web-guardian` (~2 хв).

### 6. Перевірка
Відкрити `https://desktop-tutorial-eta-tan.vercel.app/landing.html`
→ таб "Розпізнати" → довідник → фото з'являються під кожним видом.

## Rollback
```bash
git revert <commit з rewrite_catalog_photo_urls.mjs>
git push origin main
```
Міграцію bucket не відкатувати (create-only, `ON CONFLICT DO NOTHING`).

## Коміти у цьому PR
1. `supabase/migrations/20260912000020_catalog_photos_bucket.sql` — публічний bucket (CI застосує)
2. `scripts/upload_catalog_photos.mjs` — скрипт upload
3. `scripts/rewrite_catalog_photo_urls.mjs` — скрипт перезапису URL
4. `docs/pc-task-8-photos-upload.md` — інструкція

**Upload і rewrite НЕ виконуються тут** — потребують `SUPABASE_SERVICE_ROLE_KEY` на ПК. CI застосує тільки міграцію (створення bucket).
