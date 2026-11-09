-- ============================================================================
-- B1.1: кордон області для маски «острова» (GET v1-regions/{slug}/geometry)
--
-- Повертає спрощений кордон області (GeoJSON), bbox і центр.
-- Викликається тільки з Edge Function (service_role); клієнти напряму не мають доступу.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_region_geometry(
  p_slug TEXT,
  p_tolerance DOUBLE PRECISION DEFAULT 0.005
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, extensions
AS $$
  SELECT jsonb_build_object(
    'id', r.id,
    'slug', r.slug,
    'name', r.name,
    'bbox', jsonb_build_array(
      ST_XMin(r.polygon), ST_YMin(r.polygon),
      ST_XMax(r.polygon), ST_YMax(r.polygon)
    ),
    'center', jsonb_build_array(
      ST_X(ST_PointOnSurface(r.polygon)),
      ST_Y(ST_PointOnSurface(r.polygon))
    ),
    'geometry', ST_AsGeoJSON(
      ST_SimplifyPreserveTopology(r.polygon, GREATEST(p_tolerance, 0)),
      5
    )::jsonb
  )
  FROM public.regions r
  WHERE r.slug = p_slug
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_region_geometry(TEXT, DOUBLE PRECISION) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_region_geometry(TEXT, DOUBLE PRECISION) TO service_role;
