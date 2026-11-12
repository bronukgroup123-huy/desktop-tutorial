-- ============================================================================
-- Аналіз ділянки: ділянку не пересувають — лише створюють і видаляють
-- (рішення PO 2026-11-12, ADR-015 §15.4)
--
--  * Ділянка після створення незмінна (центр і розмір). Нова — тільки у вільний
--    слот: безкоштовно 1 слот, Pro — до 3. Щоб створити іншу, стару видаляють.
--  * Ліміт аналізів на добу рахується на СЛОТ, а не на ділянку: раніше лічильник
--    був прив'язаний до area_id з ON DELETE CASCADE, і «видалити → створити»
--    обнуляв би ліміт.
--  * Останній результат аналізу зберігається з ділянкою — вкладка «Прогноз»
--    показує його без повторного списання аналізу.
-- ============================================================================

-- ─── 1. Останній результат ─────────────────────────────────────────────────
ALTER TABLE public.analysis_areas
  ADD COLUMN IF NOT EXISTS last_result JSONB,
  ADD COLUMN IF NOT EXISTS last_analyzed_at TIMESTAMPTZ;

-- ─── 2. Лічильник — на слот ────────────────────────────────────────────────
ALTER TABLE public.analysis_usage ADD COLUMN IF NOT EXISTS slot SMALLINT;

UPDATE public.analysis_usage u
SET slot = a.slot
FROM public.analysis_areas a
WHERE a.id = u.area_id AND u.slot IS NULL;

DELETE FROM public.analysis_usage WHERE slot IS NULL;

ALTER TABLE public.analysis_usage DROP CONSTRAINT IF EXISTS analysis_usage_area_id_fkey;
ALTER TABLE public.analysis_usage DROP CONSTRAINT IF EXISTS analysis_usage_pkey;
DROP INDEX IF EXISTS public.analysis_usage_area_idx;

-- Кілька рядків одного слоту за добу (різні area_id) → один із сумою.
CREATE TEMP TABLE _usage_merged ON COMMIT DROP AS
SELECT user_id, slot, day, sum(count)::INT AS count
FROM public.analysis_usage
GROUP BY user_id, slot, day;
DELETE FROM public.analysis_usage;
ALTER TABLE public.analysis_usage DROP COLUMN area_id;
INSERT INTO public.analysis_usage (user_id, slot, day, count)
SELECT user_id, slot, day, count FROM _usage_merged;

ALTER TABLE public.analysis_usage ALTER COLUMN slot SET NOT NULL;
ALTER TABLE public.analysis_usage
  ADD CONSTRAINT analysis_usage_slot_check CHECK (slot BETWEEN 1 AND 3),
  ADD CONSTRAINT analysis_usage_pkey PRIMARY KEY (user_id, slot, day);

-- ─── 3. Функції ────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.save_analysis_area(UUID, INT, DOUBLE PRECISION, DOUBLE PRECISION, INT, INT);
DROP FUNCTION IF EXISTS public.consume_analysis(UUID, UUID, INT);
DROP FUNCTION IF EXISTS public.refund_analysis(UUID, UUID);
DROP FUNCTION IF EXISTS public.analysis_used_today(UUID, UUID);

-- Нова ділянка в найменшому вільному слоті ≤ p_max_slots. NULL — вільних слотів немає.
-- Наявну ділянку не змінює (ON CONFLICT DO NOTHING — паралельні запити безпечні).
CREATE OR REPLACE FUNCTION public.create_analysis_area(
  p_user_id UUID,
  p_max_slots INT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_size_km INT,
  p_region_id INT
)
RETURNS TABLE (id UUID, slot SMALLINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
  s INT;
  new_id UUID;
BEGIN
  FOR s IN 1..LEAST(GREATEST(p_max_slots, 0), 3) LOOP
    INSERT INTO public.analysis_areas (user_id, slot, center, size_km, region_id)
    VALUES (
      p_user_id, s,
      extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography,
      p_size_km, p_region_id
    )
    ON CONFLICT ON CONSTRAINT analysis_areas_user_id_slot_key DO NOTHING
    RETURNING analysis_areas.id INTO new_id;
    IF new_id IS NOT NULL THEN
      id := new_id;
      slot := s;
      RETURN NEXT;
      RETURN;
    END IF;
  END LOOP;
  RETURN;
END;
$$;

-- Видалити свою ділянку. TRUE — видалено.
CREATE OR REPLACE FUNCTION public.delete_analysis_area(p_user_id UUID, p_area_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH d AS (
    DELETE FROM public.analysis_areas WHERE id = p_area_id AND user_id = p_user_id RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM d);
$$;

-- Зберегти останній результат аналізу ділянки.
CREATE OR REPLACE FUNCTION public.save_analysis_result(p_user_id UUID, p_area_id UUID, p_result JSONB)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.analysis_areas
  SET last_result = p_result, last_analyzed_at = now(), updated_at = now()
  WHERE id = p_area_id AND user_id = p_user_id;
$$;

-- Списати один аналіз слоту (доба — за київським часом). NULL — ліміт вичерпано.
CREATE OR REPLACE FUNCTION public.consume_analysis(p_user_id UUID, p_slot INT, p_limit INT)
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.analysis_usage AS u (user_id, slot, day, count)
  SELECT p_user_id, p_slot, (now() AT TIME ZONE 'Europe/Kyiv')::date, 1
  WHERE p_limit >= 1
  ON CONFLICT (user_id, slot, day) DO UPDATE
    SET count = u.count + 1
    WHERE u.count < p_limit
  RETURNING count;
$$;

CREATE OR REPLACE FUNCTION public.refund_analysis(p_user_id UUID, p_slot INT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.analysis_usage
  SET count = count - 1
  WHERE user_id = p_user_id AND slot = p_slot
    AND day = (now() AT TIME ZONE 'Europe/Kyiv')::date
    AND count > 0;
$$;

CREATE OR REPLACE FUNCTION public.analysis_used_today(p_user_id UUID, p_slot INT)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT u.count FROM public.analysis_usage u
    WHERE u.user_id = p_user_id AND u.slot = p_slot
      AND u.day = (now() AT TIME ZONE 'Europe/Kyiv')::date
  ), 0);
$$;

DO $$
DECLARE fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.create_analysis_area(UUID, INT, DOUBLE PRECISION, DOUBLE PRECISION, INT, INT)',
    'public.delete_analysis_area(UUID, UUID)',
    'public.save_analysis_result(UUID, UUID, JSONB)',
    'public.consume_analysis(UUID, INT, INT)',
    'public.refund_analysis(UUID, INT)',
    'public.analysis_used_today(UUID, INT)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
