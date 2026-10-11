-- ============================================================================
-- RPC: пошук forest_zone за точкою (lat, lng)
-- Використовується ContextBuilder (group 8.2).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.find_zone_by_point(
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION
)
RETURNS TABLE (
  id UUID,
  stand_age_years INT,
  stand_age_source TEXT,
  stand_age_confidence NUMERIC(3,2),
  relief_type TEXT,
  light_type TEXT,
  forest_type TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT
    fz.id,
    fz.stand_age_years,
    fz.stand_age_source,
    fz.stand_age_confidence,
    fz.relief_type,
    fz.light_type,
    fz.forest_type
  FROM public.forest_zones fz
  WHERE ST_Contains(
    fz.polygon::geometry,
    ST_SetSRID(ST_MakePoint(lng, lat), 4326)
  )
  ORDER BY fz.id
  LIMIT 1;
$fn$;

COMMENT ON FUNCTION public.find_zone_by_point(DOUBLE PRECISION, DOUBLE PRECISION)
  IS 'Знайти forest_zone, що містить точку (lat, lng). Повертає першу знайдену.';

GRANT EXECUTE ON FUNCTION public.find_zone_by_point(DOUBLE PRECISION, DOUBLE PRECISION)
  TO authenticated, service_role;
