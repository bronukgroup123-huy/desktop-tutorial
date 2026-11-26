-- ============================================================================
-- Виправлення: «підтверджені знахідки» в прогнозі — лише поруч із ділянкою і того самого виду
-- ============================================================================
-- Раніше рушій рахував підтверджені точки по всій країні, без місця й виду: поки їх майже не було,
-- правило «0 знахідок → −1 рівень» знижувало прогноз усім і всюди, а 3 знахідки будь-де піднімали б
-- його всім. Тепер: знахідки за 7 днів у радіусі від центру ділянки, окремо для кожного виду.
-- Негативні звіти — теж лише поруч. Відсутність знахідок прогноз більше не знижує (як і «не знайшов»
-- не є доказом відсутності, ADR-019 §19.9).

CREATE OR REPLACE FUNCTION public.crowd_counts(
  p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION, p_radius_m INT, p_since TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH here AS (
    SELECT extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography AS g
  ),
  near AS (
    SELECT p.species_id, p.verification_status, p.is_negative
    FROM public.mushroom_picks p, here
    WHERE p.deleted_at IS NULL
      AND p.created_at >= p_since
      AND extensions.ST_DWithin(p.geom, here.g, least(greatest(p_radius_m, 100), 50000))
  )
  SELECT jsonb_build_object(
    'verified', coalesce((
      SELECT jsonb_object_agg(species_id, n) FROM (
        SELECT species_id, count(*) AS n FROM near
        WHERE verification_status = 'verified' AND NOT coalesce(is_negative, false) AND species_id IS NOT NULL
        GROUP BY species_id
      ) s
    ), '{}'::jsonb),
    'negatives', (SELECT count(*) FROM near WHERE coalesce(is_negative, false))
  );
$$;
REVOKE ALL ON FUNCTION public.crowd_counts(DOUBLE PRECISION, DOUBLE PRECISION, INT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crowd_counts(DOUBLE PRECISION, DOUBLE PRECISION, INT, TIMESTAMPTZ) TO service_role;
