-- ============================================================================
-- find_region_by_slug: резолв slug регіону ('kyiv', 'lvivska') → region_id
-- Група 8.6e / початок 9.x. Клієнти (Flutter) резолвять slug самостійно,
-- не хардкодять region_id.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.find_region_by_slug(slug_input TEXT)
RETURNS TABLE (
  id INT,
  name TEXT,
  slug TEXT,
  koatuu TEXT,
  katottg TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
  SELECT r.id, r.name, r.slug, r.koatuu, r.katottg
  FROM public.regions r
  WHERE r.slug = slug_input
  LIMIT 1;
$fn$;

COMMENT ON FUNCTION public.find_region_by_slug(TEXT)
  IS 'Резолвить slug регіону (kyiv, lvivska) → id/name.';

GRANT EXECUTE ON FUNCTION public.find_region_by_slug(TEXT)
  TO authenticated, service_role;
