-- ============================================================================
-- Уточнення лісу ділянки вручну (рішення PO 2026-11-13, ADR-015 §15.6, B2.13)
--
--  * forest_override — породи, які користувач обрав для типів лісу своєї ділянки
--    (лише зі списку; валідує Edge Function). Зберігається з ділянкою і видаляється
--    разом із нею; на загальну карту лісів не впливає.
--  * Не частіше 2 уточнень на ділянку за добу (київський час). Лічильник — на
--    ділянку: уточнення стосується саме цього місця.
--  * Переаналіз після уточнення не списує добовий ліміт аналізів (analysis_usage).
-- ============================================================================

ALTER TABLE public.analysis_areas
  ADD COLUMN IF NOT EXISTS forest_override JSONB
    CHECK (forest_override IS NULL OR jsonb_typeof(forest_override) = 'object');

CREATE TABLE IF NOT EXISTS public.analysis_forest_edits (
  area_id UUID NOT NULL REFERENCES public.analysis_areas (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  day DATE NOT NULL,
  count INT NOT NULL DEFAULT 0 CHECK (count >= 0),
  PRIMARY KEY (area_id, day)
);

CREATE INDEX IF NOT EXISTS analysis_forest_edits_user_idx ON public.analysis_forest_edits (user_id);

ALTER TABLE public.analysis_forest_edits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analysis_forest_edits FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.analysis_forest_edits FROM anon, authenticated;

-- Списати одне уточнення ділянки. NULL — ділянка не своя або ліміт вичерпано.
CREATE OR REPLACE FUNCTION public.consume_forest_edit(p_user_id UUID, p_area_id UUID, p_limit INT)
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.analysis_forest_edits AS e (area_id, user_id, day, count)
  SELECT a.id, p_user_id, (now() AT TIME ZONE 'Europe/Kyiv')::date, 1
  FROM public.analysis_areas a
  WHERE a.id = p_area_id AND a.user_id = p_user_id AND p_limit >= 1
  ON CONFLICT (area_id, day) DO UPDATE
    SET count = e.count + 1
    WHERE e.count < p_limit AND e.user_id = p_user_id
  RETURNING count;
$$;

CREATE OR REPLACE FUNCTION public.refund_forest_edit(p_user_id UUID, p_area_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.analysis_forest_edits
  SET count = count - 1
  WHERE area_id = p_area_id AND user_id = p_user_id
    AND day = (now() AT TIME ZONE 'Europe/Kyiv')::date
    AND count > 0;
$$;

CREATE OR REPLACE FUNCTION public.forest_edits_today(p_user_id UUID, p_area_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT e.count FROM public.analysis_forest_edits e
    WHERE e.area_id = p_area_id AND e.user_id = p_user_id
      AND e.day = (now() AT TIME ZONE 'Europe/Kyiv')::date
  ), 0);
$$;

-- Зберегти уточнення (NULL — «Скинути до карти») разом із результатом переаналізу.
-- TRUE — ділянка своя і збережено.
CREATE OR REPLACE FUNCTION public.save_forest_override(
  p_user_id UUID,
  p_area_id UUID,
  p_override JSONB,
  p_result JSONB
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH u AS (
    UPDATE public.analysis_areas
    SET forest_override = p_override,
        last_result = p_result,
        last_analyzed_at = now(),
        updated_at = now()
    WHERE id = p_area_id AND user_id = p_user_id
    RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM u);
$$;

DO $$
DECLARE fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.consume_forest_edit(UUID, UUID, INT)',
    'public.refund_forest_edit(UUID, UUID)',
    'public.forest_edits_today(UUID, UUID)',
    'public.save_forest_override(UUID, UUID, JSONB, JSONB)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
