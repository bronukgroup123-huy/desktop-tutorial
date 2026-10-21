-- 1. Видаляємо старі версії
DROP FUNCTION IF EXISTS get_forest_zones_geojson(NUMERIC, NUMERIC, NUMERIC, NUMERIC, INT);
DROP FUNCTION IF EXISTS get_forest_zones_geojson(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT);

-- 2. Створюємо функцію
CREATE OR REPLACE FUNCTION get_forest_zones_geojson(
  min_lng DOUBLE PRECISION,
  min_lat DOUBLE PRECISION,
  max_lng DOUBLE PRECISION,
  max_lat DOUBLE PRECISION,
  max_features INT DEFAULT 5000
)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(jsonb_agg(
      jsonb_build_object(
        'type', 'Feature',
        'id', fz.id,
        'geometry', ST_AsGeoJSON(fz.polygon, 6)::jsonb,
        'properties', jsonb_build_object(
          'id', fz.id,
          'forest_type', fz.forest_type,
          'stand_age_years', fz.stand_age_years,
          'region_id', fz.region_id
        )
      )
    ), '[]'::jsonb)
  )
  FROM (
    SELECT id, polygon, forest_type, stand_age_years, region_id
    FROM forest_zones
    WHERE polygon && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)
    LIMIT max_features
  ) fz;
$$;

-- 3. Даємо права з точним підписом типів
GRANT EXECUTE ON FUNCTION get_forest_zones_geojson(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT) TO authenticated;