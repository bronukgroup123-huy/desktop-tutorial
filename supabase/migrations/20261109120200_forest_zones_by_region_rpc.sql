-- ============================================================================
-- B1.2 / ADR-015 §15.2: полігони лісів ТІЛЬКИ в межах Home Region користувача
--
-- Фільтр за region_id гарантує, що клієнт ніколи не отримає ліси іншої області,
-- навіть якщо передасть bbox поза нею. bbox (опційно) звужує вибірку до видимої
-- частини карти; tolerance спрощує геометрію для дрібних масштабів.
-- Викликається тільки з Edge Function v1-forest-zones (service_role).
-- ============================================================================

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
    SELECT id, polygon, forest_type, stand_age_years
    FROM public.forest_zones
    WHERE region_id = p_region_id
      AND (
        p_min_lng IS NULL
        OR polygon && ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)
      )
    LIMIT LEAST(GREATEST(p_max_features, 1), 10000)
  ) fz;
$$;

REVOKE ALL ON FUNCTION public.get_forest_zones_geojson_region(INT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT, DOUBLE PRECISION) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_forest_zones_geojson_region(INT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT, DOUBLE PRECISION) TO service_role;

CREATE INDEX IF NOT EXISTS forest_zones_region_idx ON public.forest_zones (region_id);
