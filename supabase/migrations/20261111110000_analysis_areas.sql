-- ============================================================================
-- B2.9 — машинний прогноз: аналіз ділянки (ADR-015)
--
--  * analysis_areas  — збережені ділянки користувача (слоти 1–3, розмір 5 або 10 км).
--                      Безкоштовно — 1 ділянка 5×5; Pro — до 3, 5×5 або 10×10.
--  * analysis_usage  — лічильник аналізів за добу (київський час) на ділянку.
--  * save_analysis_area()    — зберегти / пересунути ділянку в слоті.
--  * consume_analysis()      — атомарно списати один аналіз (ліміт без гонок).
--  * refund_analysis()       — повернути списаний аналіз, якщо розрахунок не вдався.
--  * analyze_area_forest()   — які ліси і скільки їх у квадраті.
--
-- Запис — тільки через Edge Function v1-analysis (service_role): там перевіряються
-- область, розмір і ліміти. Користувач читає лише власні ділянки.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.analysis_areas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  slot SMALLINT NOT NULL CHECK (slot BETWEEN 1 AND 3),
  center extensions.geography(Point, 4326) NOT NULL,
  size_km SMALLINT NOT NULL CHECK (size_km IN (5, 10)),
  region_id INT NOT NULL REFERENCES public.regions (id) ON DELETE CASCADE,
  label TEXT CHECK (label IS NULL OR char_length(label) <= 60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, slot)
);

CREATE INDEX IF NOT EXISTS analysis_areas_region_idx ON public.analysis_areas (region_id);

ALTER TABLE public.analysis_areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analysis_areas FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS analysis_areas_self_read ON public.analysis_areas;
CREATE POLICY analysis_areas_self_read ON public.analysis_areas
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

REVOKE ALL ON public.analysis_areas FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.analysis_areas FROM authenticated;

CREATE TABLE IF NOT EXISTS public.analysis_usage (
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  area_id UUID NOT NULL REFERENCES public.analysis_areas (id) ON DELETE CASCADE,
  day DATE NOT NULL,
  count INT NOT NULL DEFAULT 0 CHECK (count >= 0),
  PRIMARY KEY (user_id, area_id, day)
);

CREATE INDEX IF NOT EXISTS analysis_usage_area_idx ON public.analysis_usage (area_id);

ALTER TABLE public.analysis_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analysis_usage FORCE ROW LEVEL SECURITY;
-- Політик немає: лічильник читає і змінює лише service_role.
REVOKE ALL ON public.analysis_usage FROM anon, authenticated;

-- ─── Ділянка в слоті ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.save_analysis_area(
  p_user_id UUID,
  p_slot INT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_size_km INT,
  p_region_id INT
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.analysis_areas (user_id, slot, center, size_km, region_id)
  VALUES (
    p_user_id, p_slot,
    extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography,
    p_size_km, p_region_id
  )
  ON CONFLICT (user_id, slot) DO UPDATE
    SET center = EXCLUDED.center,
        size_km = EXCLUDED.size_km,
        region_id = EXCLUDED.region_id,
        updated_at = now()
  RETURNING id;
$$;

REVOKE ALL ON FUNCTION public.save_analysis_area(UUID, INT, DOUBLE PRECISION, DOUBLE PRECISION, INT, INT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_analysis_area(UUID, INT, DOUBLE PRECISION, DOUBLE PRECISION, INT, INT)
  TO service_role;

-- ─── Ліміт аналізів на добу ────────────────────────────────────────────────
-- Доба — за київським часом. Повертає нове значення лічильника або NULL, якщо
-- ліміт вичерпано. Один оператор INSERT … ON CONFLICT — паралельні запити ліміт
-- не перевищать.
CREATE OR REPLACE FUNCTION public.consume_analysis(p_user_id UUID, p_area_id UUID, p_limit INT)
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.analysis_usage AS u (user_id, area_id, day, count)
  SELECT p_user_id, p_area_id, (now() AT TIME ZONE 'Europe/Kyiv')::date, 1
  WHERE p_limit >= 1
  ON CONFLICT (user_id, area_id, day) DO UPDATE
    SET count = u.count + 1
    WHERE u.count < p_limit
  RETURNING count;
$$;

REVOKE ALL ON FUNCTION public.consume_analysis(UUID, UUID, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_analysis(UUID, UUID, INT) TO service_role;

CREATE OR REPLACE FUNCTION public.refund_analysis(p_user_id UUID, p_area_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.analysis_usage
  SET count = count - 1
  WHERE user_id = p_user_id AND area_id = p_area_id
    AND day = (now() AT TIME ZONE 'Europe/Kyiv')::date
    AND count > 0;
$$;

REVOKE ALL ON FUNCTION public.refund_analysis(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refund_analysis(UUID, UUID) TO service_role;

-- Скільки аналізів уже використано сьогодні (для підказки в застосунку).
CREATE OR REPLACE FUNCTION public.analysis_used_today(p_user_id UUID, p_area_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT u.count FROM public.analysis_usage u
    WHERE u.user_id = p_user_id AND u.area_id = p_area_id
      AND u.day = (now() AT TIME ZONE 'Europe/Kyiv')::date
  ), 0);
$$;

REVOKE ALL ON FUNCTION public.analysis_used_today(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.analysis_used_today(UUID, UUID) TO service_role;

-- ─── Ліс у квадраті ────────────────────────────────────────────────────────
-- Квадрат p_size_km × p_size_km з центром у точці. Повертає його межі та площу
-- лісів своєї області в ньому за типами (км²) і середній вік деревостану.
CREATE OR REPLACE FUNCTION public.analyze_area_forest(
  p_region_id INT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_size_km INT
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH c AS (
    SELECT extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography AS center,
           (p_size_km * 1000.0) / 2 AS half
  ),
  sq AS (
    SELECT extensions.ST_MakeEnvelope(
      extensions.ST_X(extensions.ST_Project(c.center, c.half, radians(270))::extensions.geometry),
      extensions.ST_Y(extensions.ST_Project(c.center, c.half, radians(180))::extensions.geometry),
      extensions.ST_X(extensions.ST_Project(c.center, c.half, radians(90))::extensions.geometry),
      extensions.ST_Y(extensions.ST_Project(c.center, c.half, radians(0))::extensions.geometry),
      4326
    ) AS env
    FROM c
  ),
  parts AS (
    SELECT fz.forest_type, fz.stand_age_years,
           extensions.ST_Area(
             extensions.ST_ClipByBox2D(fz.polygon, sq.env::extensions.box2d)::extensions.geography
           ) / 1e6 AS km2
    FROM public.forest_zones fz, sq
    WHERE fz.region_id = p_region_id
      AND fz.polygon OPERATOR(extensions.&&) sq.env
  ),
  by_type AS (
    SELECT forest_type,
           sum(km2) AS km2,
           sum(stand_age_years * km2) FILTER (WHERE stand_age_years IS NOT NULL)
             / NULLIF(sum(km2) FILTER (WHERE stand_age_years IS NOT NULL), 0) AS age
    FROM parts
    WHERE km2 > 0
    GROUP BY forest_type
  )
  SELECT jsonb_build_object(
    'bbox', jsonb_build_array(
      extensions.ST_XMin(sq.env), extensions.ST_YMin(sq.env),
      extensions.ST_XMax(sq.env), extensions.ST_YMax(sq.env)
    ),
    'area_km2', (p_size_km * p_size_km),
    'forest_km2', COALESCE((SELECT round(sum(km2)::numeric, 2) FROM by_type), 0),
    'types', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'forest_type', t.forest_type,
        'km2', round(t.km2::numeric, 2),
        'stand_age_years', round(t.age)
      ) ORDER BY t.km2 DESC)
      FROM by_type t
    ), '[]'::jsonb)
  )
  FROM sq;
$$;

COMMENT ON FUNCTION public.analyze_area_forest(INT, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  IS 'Межі квадрата аналізу і площа лісів області в ньому за типами. Тільки service_role.';

REVOKE ALL ON FUNCTION public.analyze_area_forest(INT, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.analyze_area_forest(INT, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  TO service_role;
