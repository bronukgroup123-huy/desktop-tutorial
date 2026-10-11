-- ============================================================================
-- Sync: expert_rules.peak_waves / peak_months ← mushroom_catalog
-- Запускати ПІСЛЯ 0007 (naming fix) — JOIN по mushroom_type = catalog.id
-- ============================================================================

-- ─── 1. Хелпер: конвертація місяців у хвилі ────────────────────────────────
CREATE OR REPLACE FUNCTION public.months_to_waves(months INT[])
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $fn$
DECLARE
  result TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF months IS NULL OR cardinality(months) = 0 THEN
    RETURN result;
  END IF;
  IF 4 = ANY(months) OR 5 = ANY(months) THEN
    result := array_append(result, 'spring');
  END IF;
  IF 6 = ANY(months) THEN
    result := array_append(result, 'summer1');
  END IF;
  IF 7 = ANY(months) OR 8 = ANY(months) THEN
    result := array_append(result, 'summer2');
  END IF;
  IF 9 = ANY(months) OR 10 = ANY(months) THEN
    result := array_append(result, 'autumn');
  END IF;
  IF 11 = ANY(months) OR 12 = ANY(months) OR 1 = ANY(months) OR 2 = ANY(months) THEN
    result := array_append(result, 'late');
  END IF;
  RETURN result;
END;
$fn$;

COMMENT ON FUNCTION public.months_to_waves(INT[]) IS
  'Конвертація peak_months у peak_waves. Мапінг: 4-5=spring, 6=summer1, 7-8=summer2, 9-10=autumn, 11-2=late.';

-- ─── 2. Синхронізація: для кожного виду в expert_rules ───────────────────
UPDATE public.expert_rules er
SET
  peak_waves  = public.months_to_waves(mc.peak_months),
  peak_months = mc.peak_months
FROM public.mushroom_catalog mc
WHERE mc.id = er.mushroom_type;

-- ─── 3. Self-check: 0 orphan'ів + peak_months співпадає ───────────────────
DO $$
DECLARE
  orphan_count INT;
  updated_count INT;
BEGIN
  SELECT COUNT(*) INTO orphan_count
  FROM public.expert_rules er
  LEFT JOIN public.mushroom_catalog mc ON mc.id = er.mushroom_type
  WHERE mc.id IS NULL;

  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'Знайдено % orphan mushroom_type — sync не пройшов', orphan_count;
  END IF;

  SELECT COUNT(*) INTO updated_count
  FROM public.expert_rules er
  JOIN public.mushroom_catalog mc ON mc.id = er.mushroom_type
  WHERE er.peak_months IS DISTINCT FROM mc.peak_months;

  IF updated_count > 0 THEN
    RAISE EXCEPTION 'Sync неузгоджений: % видів мають різні peak_months', updated_count;
  END IF;

  RAISE NOTICE '✅ Sync passed: 20 видів синхронізовано з каталогу';
END $$;
