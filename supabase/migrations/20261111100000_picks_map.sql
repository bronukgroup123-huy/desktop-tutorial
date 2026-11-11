-- ============================================================================
-- B3.3 — карта тук-туків (ADR-018 §18.2, §18.5)
--
-- get_picks_map()  — точки для карти Home Region: чужі публічні + власні.
-- get_pick_card()  — одна точка для картки (Bottom Sheet).
--
-- Приватність (ADR-018 §18.5): для чужих точок ці функції ніколи не повертають і
-- навіть не використовують у фільтрах точний geom — лише display_geom (зсув
-- 300–500 м). Якби bbox чи область фільтрувались за точним місцем, його можна було б
-- «намацати», звужуючи запит. Точні координати повертаються тільки автору.
-- Виклик — лише з Edge Function v1-picks (service_role).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_picks_map(
  p_user_id UUID,
  p_region_id INT,
  p_min_lng DOUBLE PRECISION DEFAULT NULL,
  p_min_lat DOUBLE PRECISION DEFAULT NULL,
  p_max_lng DOUBLE PRECISION DEFAULT NULL,
  p_max_lat DOUBLE PRECISION DEFAULT NULL,
  p_include_private BOOLEAN DEFAULT false,
  p_limit INT DEFAULT 500
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH region AS (
    SELECT r.polygon FROM public.regions r WHERE r.id = p_region_id
  ),
  bbox AS (
    SELECT CASE WHEN p_min_lng IS NULL THEN NULL
      ELSE extensions.ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) END AS env
  ),
  shown AS (
    -- Місце, яке бачить саме цей користувач: своє — точне, чуже — зсунуте.
    SELECT
      p.id, p.user_id, p.pick_type, p.verification_status, p.species_id, p.created_at,
      (p.user_id = p_user_id) AS is_mine,
      CASE WHEN p.user_id = p_user_id THEN p.geom ELSE p.display_geom END::extensions.geometry AS place
    FROM public.mushroom_picks p
    WHERE p.deleted_at IS NULL
      AND (
        (p.user_id = p_user_id AND (p.pick_type = 'public' OR p_include_private))
        OR (p.user_id <> p_user_id AND p.pick_type = 'public' AND p.verification_status <> 'rejected')
      )
  ),
  picked AS (
    SELECT s.*
    FROM shown s, region, bbox
    WHERE s.place IS NOT NULL
      AND extensions.ST_Intersects(region.polygon, s.place)
      AND (bbox.env IS NULL OR s.place OPERATOR(extensions.&&) bbox.env)
    ORDER BY s.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 2000) + 1
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', k.id,
    'lat', extensions.ST_Y(k.place),
    'lng', extensions.ST_X(k.place),
    'is_exact', k.is_mine,
    'is_mine', k.is_mine,
    'pick_type', k.pick_type,
    'verification_status', k.verification_status,
    'species_id', k.species_id,
    'name_ua', c.name_ua
  ) ORDER BY k.created_at DESC), '[]'::jsonb)
  FROM picked k
  LEFT JOIN public.mushroom_catalog c ON c.id = k.species_id;
$$;

COMMENT ON FUNCTION public.get_picks_map(UUID, INT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, INT)
  IS 'Точки для карти Home Region: чужі публічні (лише display_geom) + власні (точні). Повертає до p_limit + 1 рядків. Тільки service_role.';

REVOKE ALL ON FUNCTION public.get_picks_map(UUID, INT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, INT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_picks_map(UUID, INT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, INT)
  TO service_role;

-- Картка точки. NULL — точки немає або користувачу її бачити не можна
-- (чужа приватна, відхилена, видалена, з іншої області).
CREATE OR REPLACE FUNCTION public.get_pick_card(p_user_id UUID, p_region_id INT, p_pick_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'id', s.id,
    'lat', extensions.ST_Y(s.place),
    'lng', extensions.ST_X(s.place),
    'is_exact', s.is_mine,
    'is_mine', s.is_mine,
    'pick_type', s.pick_type,
    'verification_status', s.verification_status,
    'species_id', s.species_id,
    'name_ua', c.name_ua,
    'description', s.description,
    'photo_path', s.photo_url,
    'taken_at', COALESCE(s.captured_at, s.created_at)
  )
  FROM (
    SELECT p.*,
      (p.user_id = p_user_id) AS is_mine,
      CASE WHEN p.user_id = p_user_id THEN p.geom ELSE p.display_geom END::extensions.geometry AS place
    FROM public.mushroom_picks p
    WHERE p.id = p_pick_id AND p.deleted_at IS NULL
  ) s
  LEFT JOIN public.mushroom_catalog c ON c.id = s.species_id
  WHERE s.place IS NOT NULL
    AND (
      s.is_mine
      OR (
        s.pick_type = 'public'
        AND s.verification_status <> 'rejected'
        AND EXISTS (
          SELECT 1 FROM public.regions r
          WHERE r.id = p_region_id AND extensions.ST_Intersects(r.polygon, s.place)
        )
      )
    );
$$;

COMMENT ON FUNCTION public.get_pick_card(UUID, INT, UUID)
  IS 'Картка точки: своя — з точними координатами; чужа публічна — лише display_geom. Тільки service_role.';

REVOKE ALL ON FUNCTION public.get_pick_card(UUID, INT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pick_card(UUID, INT, UUID) TO service_role;
