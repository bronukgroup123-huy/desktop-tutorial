-- RPC для отримання лісових зон у bbox як GeoJSON FeatureCollection
-- Використовує GIST-індекс через оператор && (bbox overlap) — швидко, без точної геометрії

CREATE OR REPLACE FUNCTION get_forest_zones_geojson(
  min_lng NUMERIC,
  min_lat NUMERIC,
  max_lng NUMERIC,
  max_lat NUMERIC,
  max_features INT DEFAULT 5000
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER  -- RLS буде застосовуватися від імені викликаючого користувача
AS $$
DECLARE
  bbox GEOMETRY;
  fc JSONB;
  feature_count INT;
BEGIN
  -- 1. Валідація вхідних координат
  IF min_lng >= max_lng OR min_lat >= max_lat THEN
    RAISE EXCEPTION 'Invalid bbox: min_lng < max_lng та min_lat < max_lat required';
  END IF;
  IF min_lng < -180 OR max_lng > 180 OR min_lat < -90 OR max_lat > 90 THEN
    RAISE EXCEPTION 'Coordinates out of bounds: lng [-180,180], lat [-90,90]';
  END IF;

  -- 2. Створюємо envelope (bbox) у EPSG:4326
  bbox := ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326);

  -- 3. Вибірка з використанням GIST-індексу (оператор && — bbox overlap)
  -- ST_AsGeoJSON(geometry, maxdecimaldigits=6) — 6 знаків ≈ 0.11м précision
  WITH selected AS (
    SELECT
      id,
      polygon,
      forest_type,
      stand_age_years,
      region_id,
      (forest_type IS NOT NULL) AS has_data
    FROM forest_zones
    WHERE polygon && bbox
    LIMIT max_features
  )
  SELECT
    jsonb_build_object(
      'type', 'FeatureCollection',
      'features', COALESCE(jsonb_agg(feature), '[]'::jsonb)
    ),
    COUNT(*)::INT
  INTO fc, feature_count
  FROM (
    SELECT jsonb_build_object(
      'type', 'Feature',
      'id', id::TEXT,
      'geometry', ST_AsGeoJSON(polygon, 6)::JSONB,
      'properties', jsonb_build_object(
        'id', id,
        'forest_type', forest_type,
        'stand_age_years', stand_age_years,
        'region_id', region_id,
        'has_data', has_data
      )
    ) AS feature
    FROM selected
  ) f;

  -- 4. Логування, якщо перевищено ліміт (можна підключити до моніторингу)
  IF feature_count >= max_features THEN
    RAISE NOTICE 'get_forest_zones_geojson: max_features limit reached (%), bbox: (%,%,%,%)',
      max_features, min_lng, min_lat, max_lng, max_lat;
  END IF;

  -- 5. Повертаємо FeatureCollection (порожній масив, якщо нічого не знайдено)
  RETURN COALESCE(fc, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb));
END;
$$;

-- Дозвіл на виконання для аутентифікованих користувачів
GRANT EXECUTE ON FUNCTION get_forest_zones_geojson TO authenticated;

-- Коментарі для документації
COMMENT ON FUNCTION get_forest_zones_geojson(NUMERIC, NUMERIC, NUMERIC, NUMERIC, INT)
IS 'Повертає GeoJSON FeatureCollection лісових зон у заданому bbox. Використовує GIST-індекс (&&) для швидкого фільтру. Precision=6 (≈0.11м). ЛІМІТ max_features для захисту від надлишкового трафіку.';

/*
-- ============================================================
-- ТЕСТ: bbox Києва (30.3, 50.3, 30.8, 50.6)
-- ============================================================
SELECT get_forest_zones_geojson(30.3, 50.3, 30.8, 50.6, 100);

-- ============================================================
-- ПОЧЕМУ && А НЕ ST_Intersects / ST_Contains
-- ============================================================
-- && (bbox overlap) — використовує GIST-індекс, працює за O(log n),
--   перевіряє тільки bounding boxes, не обчислює точну геометрію.
-- ST_Intersects / ST_Contains — точні геометричні предикати,
--   потребують seq scan або recheck, на великих таблицях — повільно.
-- 
-- Для карти (рендеринг тисяч полігонів) && — правильний вибір.
-- Для точкової перевірки (детальна аналітика 5×5 км) — окрема RPC
-- get_forest_zones_at_point(lat, lng) з ST_Contains.
-- ============================================================
*/