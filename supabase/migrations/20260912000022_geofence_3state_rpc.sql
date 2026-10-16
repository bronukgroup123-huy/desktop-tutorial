-- ============================================================================
-- 3-state geofence RPC (PC-TASK #9 / Audit G4)
-- Повертає: 'inside' | 'outside' | 'unknown'
-- unknown = жоден polygon у радіусі 5 км (безпечно, немає false-positive)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_forest_position(
  p_lat NUMERIC,
  p_lng NUMERIC
)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH
    inside_check AS (
      SELECT EXISTS (
        SELECT 1
        FROM forest_polygons fp
        WHERE ST_Contains(
          fp.polygon::geometry,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)
        )
      ) AS is_inside
    ),
    nearby_check AS (
      SELECT EXISTS (
        SELECT 1
        FROM forest_polygons fp
        WHERE ST_DWithin(
          fp.polygon::geography,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
          5000
        )
      ) AS has_nearby
    )
  SELECT
    CASE
      WHEN (SELECT is_inside FROM inside_check) THEN 'inside'
      WHEN NOT (SELECT has_nearby FROM nearby_check) THEN 'unknown'
      ELSE 'outside'
    END;
$$;

GRANT EXECUTE ON FUNCTION public.check_forest_position(NUMERIC, NUMERIC)
  TO authenticated, service_role;

-- is_point_in_forest збережено для зворотної сумісності.

COMMENT ON FUNCTION public.check_forest_position IS
  'Geofence: inside/outside/unknown. unknown = жоден polygon у радіусі 5 км від точки.';
