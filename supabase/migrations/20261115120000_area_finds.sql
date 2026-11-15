-- ============================================================================
-- Знахідки в ділянці (рішення PO 2026-11-15, ADR-015 §15.8 п.14)
--
--  * analysis_history — що прогнозувалося на кожен день у ділянці (види зі шансом). Пишеться
--    при кожному аналізі за сьогоднішній день; потрібна, щоб звірити тук-туки з прогнозом того
--    дня («прогноз збігся зі знахідками: 2 з 3») і згодом калібрувати рушій.
--  * area_finds — власні знахідки користувача в межах квадрата ділянки за проміжок днів
--    (київська доба) з позначкою, чи був вид серед прогнозованих того дня. Лише свої точки:
--    чужі знахідки в межах ділянки не розкриваються (ADR-018).
-- Доступ — лише service_role (Edge Function v1-analysis).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.analysis_history (
  area_id UUID NOT NULL REFERENCES public.analysis_areas (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  day DATE NOT NULL,
  species TEXT[] NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (area_id, day)
);

CREATE INDEX IF NOT EXISTS analysis_history_user_idx ON public.analysis_history (user_id);

ALTER TABLE public.analysis_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analysis_history FORCE ROW LEVEL SECURITY;
-- Політик немає: читає і пише лише service_role.
REVOKE ALL ON public.analysis_history FROM anon, authenticated;

-- Записати прогноз дня (види зі шансом) — повторний аналіз того ж дня перезаписує.
CREATE OR REPLACE FUNCTION public.save_analysis_history(p_user_id UUID, p_area_id UUID, p_day DATE, p_species TEXT[])
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.analysis_history AS h (area_id, user_id, day, species)
  SELECT a.id, a.user_id, p_day, COALESCE(p_species, '{}')
  FROM public.analysis_areas a
  WHERE a.id = p_area_id AND a.user_id = p_user_id
  ON CONFLICT (area_id, day) DO UPDATE SET species = EXCLUDED.species, updated_at = now();
$$;

-- Власні знахідки в квадраті ділянки за [p_from .. p_to] (київська доба).
-- matched: вид був серед прогнозованих того дня; NULL — прогнозу на той день немає.
CREATE OR REPLACE FUNCTION public.area_finds(p_user_id UUID, p_area_id UUID, p_from DATE, p_to DATE)
RETURNS TABLE (lat DOUBLE PRECISION, lng DOUBLE PRECISION, species_id TEXT, name_ua TEXT, day DATE, matched BOOLEAN)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH a AS (
    SELECT ar.id, ar.center, (ar.size_km * 1000.0) / 2 AS half
    FROM public.analysis_areas ar
    WHERE ar.id = p_area_id AND ar.user_id = p_user_id
  ),
  sq AS (
    SELECT a.id, extensions.ST_MakeEnvelope(
      extensions.ST_X(extensions.ST_Project(a.center, a.half, radians(270))::extensions.geometry),
      extensions.ST_Y(extensions.ST_Project(a.center, a.half, radians(180))::extensions.geometry),
      extensions.ST_X(extensions.ST_Project(a.center, a.half, radians(90))::extensions.geometry),
      extensions.ST_Y(extensions.ST_Project(a.center, a.half, radians(0))::extensions.geometry),
      4326
    ) AS env
    FROM a
  ),
  p AS (
    SELECT extensions.ST_Y(mp.geom::extensions.geometry) AS lat,
           extensions.ST_X(mp.geom::extensions.geometry) AS lng,
           COALESCE(mp.species_id, mp.mushroom_type) AS species_id,
           (COALESCE(mp.captured_at, mp.created_at) AT TIME ZONE 'Europe/Kyiv')::date AS day
    FROM public.mushroom_picks mp, sq
    WHERE mp.user_id = p_user_id
      AND mp.deleted_at IS NULL
      AND mp.geom::extensions.geometry OPERATOR(extensions.&&) sq.env
      AND (COALESCE(mp.captured_at, mp.created_at) AT TIME ZONE 'Europe/Kyiv')::date BETWEEN p_from AND p_to
  )
  SELECT p.lat, p.lng, p.species_id, c.name_ua, p.day,
         CASE WHEN h.day IS NULL THEN NULL ELSE p.species_id = ANY (h.species) END AS matched
  FROM p
  LEFT JOIN public.analysis_history h ON h.area_id = p_area_id AND h.day = p.day
  LEFT JOIN public.mushroom_catalog c ON c.id = p.species_id
  ORDER BY p.day DESC
  LIMIT 200;
$$;

DO $$
DECLARE fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.save_analysis_history(UUID, UUID, DATE, TEXT[])',
    'public.area_finds(UUID, UUID, DATE, DATE)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
