-- ============================================================================
-- Прив'язка лісів до областей — за геометрією, а не за даними імпорту
--
-- Аудит 2026-11-10: у forest_zones лише ліси, завантажені з OSM прямокутником
-- 50.1–51.2 × 29.5–32.2 (scripts/download_forest_data.mjs), і всім записано
-- region_id Київської області (scripts/import-forests.ts). Прямокутник не
-- збігається з межами області: частина лісів фактично лежить у Житомирській,
-- а південь Київської не покритий. Інший скрипт (import_all_ukraine.mjs)
-- пише region_id = null.
--
-- 1) region_id перераховується для ВСІХ полігонів за геометрією (область, що
--    містить точку на полігоні).
-- 2) Тригер робить те саме для майбутніх імпортів, якщо region_id не задано.
-- 3) RPC вибирає ліси, що перетинають КОРДОН області (джерело істини —
--    геометрія), тож неточний region_id більше не ховає й не «приписує» ліси.
-- ============================================================================

SET LOCAL statement_timeout = '15min';

-- ─── 1. Перерахунок region_id за геометрією ─────────────────────────────────
UPDATE public.forest_zones fz
SET region_id = r.id
FROM public.regions r
WHERE r.polygon && ST_PointOnSurface(fz.polygon)
  AND ST_Contains(r.polygon, ST_PointOnSurface(fz.polygon))
  AND fz.region_id IS DISTINCT FROM r.id;

-- ─── 2. Тригер для нових / змінених полігонів ───────────────────────────────
CREATE OR REPLACE FUNCTION public.forest_zones_set_region()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.region_id IS NULL AND NEW.polygon IS NOT NULL THEN
    SELECT r.id INTO NEW.region_id
    FROM public.regions r
    WHERE r.polygon && ST_PointOnSurface(NEW.polygon)
      AND ST_Contains(r.polygon, ST_PointOnSurface(NEW.polygon))
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS forest_zones_set_region ON public.forest_zones;
CREATE TRIGGER forest_zones_set_region
  BEFORE INSERT OR UPDATE OF polygon, region_id ON public.forest_zones
  FOR EACH ROW EXECUTE FUNCTION public.forest_zones_set_region();

-- ─── 3. RPC: ліси, що перетинають кордон області ────────────────────────────
CREATE OR REPLACE FUNCTION public.get_forest_zones_geojson_region(
  p_region_id INT,
  p_min_lng DOUBLE PRECISION DEFAULT NULL,
  p_min_lat DOUBLE PRECISION DEFAULT NULL,
  p_max_lng DOUBLE PRECISION DEFAULT NULL,
  p_max_lat DOUBLE PRECISION DEFAULT NULL,
  p_max_features INT DEFAULT 5000,
  p_tolerance DOUBLE PRECISION DEFAULT 0
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, extensions
AS $$
  WITH region AS (
    SELECT polygon FROM public.regions WHERE id = p_region_id
  )
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(jsonb_agg(
      jsonb_build_object(
        'type', 'Feature',
        'id', fz.id,
        'geometry', ST_AsGeoJSON(
          CASE WHEN p_tolerance > 0
               THEN ST_SimplifyPreserveTopology(fz.polygon, p_tolerance)
               ELSE fz.polygon END,
          6
        )::jsonb,
        'properties', jsonb_build_object(
          'id', fz.id,
          'forest_type', fz.forest_type,
          'stand_age_years', fz.stand_age_years
        )
      )
    ), '[]'::jsonb)
  )
  FROM (
    SELECT f.id, f.polygon, f.forest_type, f.stand_age_years
    FROM public.forest_zones f, region
    WHERE f.polygon && region.polygon
      AND (
        p_min_lng IS NULL
        OR f.polygon && ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)
      )
      AND ST_Intersects(f.polygon, region.polygon)
    LIMIT LEAST(GREATEST(p_max_features, 1), 10000)
  ) fz;
$$;

REVOKE ALL ON FUNCTION public.get_forest_zones_geojson_region(INT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT, DOUBLE PRECISION) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_forest_zones_geojson_region(INT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT, DOUBLE PRECISION) TO service_role;
