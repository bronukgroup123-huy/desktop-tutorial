-- ============================================================================
-- B3.5a: теплова карта знахідок (ADR-010 §10.4 п.2, ADR-013 §13.5, ADR-018 §18.5)
-- ============================================================================
-- * Лише підтверджені публічні точки (verified), не видалені, за період.
-- * Сітка ≈ 1 км (0.009° широти × 0.014° довготи — на широтах України це ≈ 1 × 1 км).
--   Клітинку показуємо, лише якщо в ній ≥ 5 точок ВІД ≥ 2 АВТОРІВ (k-анонімність: одна людина
--   з п'ятьма точками не «засвітить» своє місце). Кількість не віддаємо — лише рівень 1–3.
-- * Точні координати — тільки тут, на сервері (§18.5); назовні — центр клітинки.
-- * Доступ:
--     нижче «Лісовика» без Pro            → level_required;
--     «Лісовик»                            → своя область, останні 3 дні;
--     «Хранитель лісу»                     → своя + сусідні області, 3 дні;
--     «Грибний Майстер» або Pro            → уся Україна, 3 / 7 / 30 днів.
--   Період 7/30 або bbox поза дозволеними областями без Pro → pro_required.
-- * Pro (entitlements) з'явиться з B6.3 — до того p_pro = false у всіх, крім тестів.

-- Точки за видимістю, статусом і часом — для теплової карти й інших агрегатів.
CREATE INDEX IF NOT EXISTS mushroom_picks_public_verified_created_idx
  ON public.mushroom_picks (created_at DESC)
  WHERE pick_type = 'public' AND verification_status = 'verified' AND deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.heatmap_cells(
  p_user_id UUID,
  p_period_days INT DEFAULT 3,
  p_pro BOOLEAN DEFAULT false,
  p_min_lng DOUBLE PRECISION DEFAULT NULL,
  p_min_lat DOUBLE PRECISION DEFAULT NULL,
  p_max_lng DOUBLE PRECISION DEFAULT NULL,
  p_max_lat DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_lat_step CONSTANT DOUBLE PRECISION := 0.009;
  c_lng_step CONSTANT DOUBLE PRECISION := 0.014;
  c_min_points CONSTANT INT := 5;
  c_min_authors CONSTANT INT := 2;
  v_level TEXT;
  v_home INT;
  v_all BOOLEAN;
  v_regions INT[];
  v_scope TEXT;
  v_env extensions.geometry;
  v_cells JSONB;
BEGIN
  SELECT public.level_of(u.rating, u.knowledge_certified_at IS NOT NULL), u.home_region_id
    INTO v_level, v_home
  FROM public.users u WHERE u.id = p_user_id;
  IF v_home IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'home_region_required', 'message', 'Спочатку оберіть свою область');
  END IF;

  v_all := p_pro OR v_level = 'master';
  IF NOT v_all AND coalesce(v_level, 'traveler') NOT IN ('forester', 'keeper') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'level_required', 'message',
      'Теплова карта — з рівня «Лісовик» або в Pro. Бали дають за перевірені точки, підтвердження й тести');
  END IF;
  IF p_period_days IS NULL OR p_period_days NOT IN (3, 7, 30) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Період — 3, 7 або 30 днів');
  END IF;
  IF p_period_days > 3 AND NOT v_all THEN
    RETURN jsonb_build_object('ok', false, 'code', 'pro_required', 'message',
      'Знахідки за 7 і 30 днів — у Pro. Зараз — за останні 3 дні');
  END IF;

  IF p_min_lng IS NOT NULL THEN
    v_env := extensions.ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326);
  END IF;

  IF v_all THEN
    v_scope := 'ukraine';
  ELSIF v_level = 'keeper' THEN
    v_scope := 'neighbours';
    SELECT array_agg(r.id) INTO v_regions
    FROM public.regions r, public.regions h
    WHERE h.id = v_home AND extensions.ST_DWithin(r.polygon, h.polygon, 0.02);
  ELSE
    v_scope := 'home';
    v_regions := ARRAY[v_home];
  END IF;

  IF v_env IS NOT NULL AND NOT v_all AND NOT EXISTS (
    SELECT 1 FROM public.regions r WHERE r.id = ANY (v_regions) AND extensions.ST_Intersects(r.polygon, v_env)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'pro_required', 'message',
      'Теплова карта інших областей — у Pro');
  END IF;

  WITH pts AS (
    SELECT p.geom::extensions.geometry AS g, p.user_id
    FROM public.mushroom_picks p
    WHERE p.pick_type = 'public' AND p.verification_status = 'verified' AND p.deleted_at IS NULL
      AND p.geom IS NOT NULL
      AND p.created_at > now() - make_interval(days => p_period_days)
  ),
  scoped AS (
    SELECT pts.* FROM pts
    WHERE (v_env IS NULL OR pts.g OPERATOR(extensions.&&) v_env)
      AND (v_all OR EXISTS (
        SELECT 1 FROM public.regions r
        WHERE r.id = ANY (v_regions) AND extensions.ST_Intersects(r.polygon, pts.g)
      ))
  ),
  cells AS (
    SELECT floor(extensions.ST_Y(g) / c_lat_step) AS cy, floor(extensions.ST_X(g) / c_lng_step) AS cx,
           count(*) AS n, count(DISTINCT user_id) AS authors
    FROM scoped GROUP BY 1, 2
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'lat', round(((cy + 0.5) * c_lat_step)::numeric, 5),
      'lng', round(((cx + 0.5) * c_lng_step)::numeric, 5),
      'level', CASE WHEN n >= 20 THEN 3 WHEN n >= 10 THEN 2 ELSE 1 END
    ) ORDER BY n DESC), '[]'::jsonb)
    INTO v_cells
  FROM (SELECT * FROM cells WHERE n >= c_min_points AND authors >= c_min_authors ORDER BY n DESC LIMIT 5000) c;

  RETURN jsonb_build_object(
    'ok', true,
    'cells', v_cells,
    'cell_lat', c_lat_step,
    'cell_lng', c_lng_step,
    'period_days', p_period_days,
    'scope', v_scope,
    'can_change_period', v_all
  );
END;
$$;

COMMENT ON FUNCTION public.heatmap_cells(UUID, INT, BOOLEAN, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION)
  IS 'Теплова карта (B3.5): клітинки ≈1 км з ≥5 перевіреними публічними точками від ≥2 авторів; доступ за рівнем/Pro. Тільки service_role.';
REVOKE ALL ON FUNCTION public.heatmap_cells(UUID, INT, BOOLEAN, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.heatmap_cells(UUID, INT, BOOLEAN, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION)
  TO service_role;
