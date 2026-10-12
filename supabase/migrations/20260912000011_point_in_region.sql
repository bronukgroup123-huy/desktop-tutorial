-- ============================================================================
-- RPC: перевірка точки (lat, lng) у полігоні регіону (group 8.6a)
-- Потрібен RegionGuard: hard-fail, якщо точка поза домашнім регіоном.
-- Відмінність від find_zone_by_point: повертає BOOLEAN, не TABLE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.point_in_region(
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  region_id INT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.regions r
    WHERE r.id = region_id
      AND ST_Contains(
        r.polygon::extensions.geometry,
        ST_SetSRID(ST_MakePoint(lng, lat), 4326)
      )
  );
$fn$;

COMMENT ON FUNCTION public.point_in_region(DOUBLE PRECISION, DOUBLE PRECISION, INT)
  IS 'Перевірка: чи точка (lat, lng) у полігоні region_id.';

GRANT EXECUTE ON FUNCTION public.point_in_region(DOUBLE PRECISION, DOUBLE PRECISION, INT)
  TO authenticated, service_role;
