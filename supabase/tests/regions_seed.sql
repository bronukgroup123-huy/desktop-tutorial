-- ============================================================================
-- Regions seed — SQL tests (Група 9.1)
--
-- Виконується ВРУЧНУ в Supabase SQL Editor ПІСЛЯ застосування міграції
-- 20260912000014_regions_seed.sql. Не входить у CI (CI лише TS-тести).
--
-- Стиль: DO $$ ... RAISE EXCEPTION (якщо тест падає — голосно).
-- Проходить → відповіді "DO"; падає → помилка з текстом.
-- ============================================================================

DO $$
DECLARE
  cnt INT;
  kyiv_id INT;
  lviv_id INT;
  in_kyiv BOOLEAN;
  in_lviv BOOLEAN;
BEGIN
  -- 1. Рівно 27 регіонів
  SELECT COUNT(*) INTO cnt FROM regions;
  IF cnt != 27 THEN
    RAISE EXCEPTION 'Expected 27 regions, got %', cnt;
  END IF;

  -- 2. slug заповнений у всіх
  SELECT COUNT(*) INTO cnt FROM regions WHERE slug IS NULL;
  IF cnt != 0 THEN
    RAISE EXCEPTION 'Missing slugs: %', cnt;
  END IF;

  -- 3. katottg унікальний і не null у всіх
  SELECT COUNT(*) INTO cnt FROM regions
  WHERE katottg IS NULL OR katottg !~ '^UA[0-9]{17}$';
  IF cnt != 0 THEN
    RAISE EXCEPTION 'Bad katottg codes: %', cnt;
  END IF;

  -- 4. kyiv та lvivska існують
  SELECT id INTO kyiv_id FROM regions WHERE slug = 'kyiv';
  SELECT id INTO lviv_id FROM regions WHERE slug = 'lvivska';
  IF kyiv_id IS NULL OR lviv_id IS NULL THEN
    RAISE EXCEPTION 'Missing kyiv or lvivska';
  END IF;

  -- 5. Точка (50.45, 30.52) у Києві
  SELECT point_in_region(50.45, 30.52, kyiv_id) INTO in_kyiv;
  IF NOT in_kyiv THEN
    RAISE EXCEPTION 'Kyiv point not in Kyiv region';
  END IF;

  -- 6. Точка (50.45, 30.52) НЕ у Львівській області
  SELECT point_in_region(50.45, 30.52, lviv_id) INTO in_lviv;
  IF in_lviv THEN
    RAISE EXCEPTION 'Kyiv point shouldn''t be in Lviv region';
  END IF;

  -- 7. Orphan fix: усі forest_zones прив'язані до регіону
  SELECT COUNT(*) INTO cnt FROM forest_zones WHERE region_id IS NULL;
  IF cnt != 0 THEN
    RAISE EXCEPTION 'Orphan forest_zones: %', cnt;
  END IF;
END $$;

-- Додаткова інформація (не assertion):
--   SELECT slug, koatuu, katottg, ST_GeometryType(polygon) FROM regions ORDER BY koatuu;
