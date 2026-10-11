# Канонізація каталогу — звіт

**Дата:** 2026-10-11
**Статус:** ✅ Завершено (E.4 верифіковано 8/8, D.4 — 4/4)

## Що зроблено

- 326 видів нормалізовано (`-` → `_` в `id`)
- Таблиця `mushroom_catalog` створена, seed 326 рядків
- `regions.slug` — колонка створена (дані перенесено в Групу 9.1)
- `mushroom_catalog.peak_months` — заповнено для 9 top20 видів
- `expert_rules.mushroom_type` — hyphens → underscores + `_spp` → конкретний вид
- `expert_rules.peak_waves` / `peak_months` — синхронізовано з каталогу (`months_to_waves()`)
- FK `expert_rules → mushroom_catalog` — активний
- CHECK-тригер — забороняє отруйні / ЧК / неїстівні

## Канон

**`mushroom_catalog.json`** — джерело правди для видів, їхніх піків і зон.

§9 плану v6.0 — **superseded** (узгоджувався з каталогом на Кроках A–D).

## Міграції

| Файл | Що |
|---|---|
| `20260912000004_mushroom_catalog.sql` | таблиця каталогу + `regions.slug` |
| `20260912000005_mushroom_catalog_seed.sql` | seed 326 рядків |
| `20260912000006_catalog_peak_months.sql` | peak_months для 9 top20 |
| `20260912000007_forecast_fix_naming.sql` | expert_rules naming → каталог |
| `20260912000008_expert_rules_sync_waves.sql` | sync peak_waves з каталогу |
| `20260912000009_expert_rules_constraints.sql` | FK + CHECK-тригер |

## Перевірки (SQL Editor)

| Перевірка | Результат |
|---|---|
| Каталог | 326 ✅ |
| top20 | 20 ✅ |
| ai_recognition | 89 ✅ |
| red_listed | 44 ✅ |
| top20 без піку (очікувалось 4) | 4 ✅ |
| expert_rules без hyphens | 20 ✅ |
| Coverage каталогу (0 orphan) | 0 ✅ |
| `count_summer2_autumn` (було 13, стало 2) | 2 ✅ |
| FK існує (`expert_rules_catalog_fk`) | 1 ✅ |
| CHECK `amanita_phalloides` | rejected ✅ |
| CHECK `boletus_aereus` (ЧК) | rejected ✅ |
| FK `does_not_exist` | violation ✅ |

## Інфра-фікс CI

**Проблема:** `supabase/setup-cli@v1` action at `version: latest` → `Failed to resolve
latest Supabase CLI release: rate limit exceeded` (GitHub Releases API rate limit),
ран впав на етапі setup (нічого не задеплоїлось).

**Рішення:** замінено на явний крок `npm install -g supabase` — резолвинг версії
іде через npm registry (інші ліміти), ран пройшов зеленим.

```yaml
- name: Setup Supabase CLI
  run: npm install -g supabase
```

## Коміти канонізації

```
647c4de chore(catalog): normalize species ids (- to _)
79d5838 feat(catalog): add mushroom_catalog table + regions.slug column
430261b feat(catalog): seed 326 species from JSON
8e73afe chore(catalog): patch peak_months for 9 top20 species (from §9)
79d2f95 fix(catalog): populate peak_months for 9 top20 species
        fix(forecast): normalize expert_rules.mushroom_type to catalog ids
1e01cb1 feat(forecast): sync expert_rules peak_waves from catalog
98202d6 ci: replace setup-cli action with npm install (release-resolve rate limit)
b08fa7a feat(forecast): FK to catalog + CHECK for poisonous/red-listed
```

## Що далі

Рушій прогнозу отримав чисту базу:
- `mushroom_type` = канонічні id каталогу
- `peak_waves` = справжні піки (Rule 4 розрізнятиме, а не бонуситиме все)
- FK + CHECK захищають від отруйних/ЧК/неіснуючих видів

Наступний крок — **8.2 ContextBuilder**.
