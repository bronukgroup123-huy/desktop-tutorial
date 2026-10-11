-- ============================================================================
-- Fix: peak_months у mushroom_catalog для top20 видів
-- Джерело: §9 плану v6.0 + мікологічна логіка (глива — варіант B)
-- Картинка: 13 top20 без peak_months → заповнюємо 9, 4 залишаємо без
-- (boletus_luridus, leccinum_aurantiacum, suillus_luteus, russula_vesca —
--  ростуть рівномірно, чіткого піку немає)
-- ============================================================================

-- ─── 1. Додати peak_months ────────────────────────────────────────────────
UPDATE public.mushroom_catalog SET peak_months = '{4,5}'::INT[]
  WHERE id = 'morchella_esculenta' AND cardinality(peak_months) = 0;

UPDATE public.mushroom_catalog SET peak_months = '{7,8}'::INT[]
  WHERE id IN ('lactarius_resimus','agaricus_campestris',
               'xerocomus_subtomentosus','suillus_bovinus')
    AND cardinality(peak_months) = 0;

UPDATE public.mushroom_catalog SET peak_months = '{9,10}'::INT[]
  WHERE id IN ('imleria_badia','lactarius_torminosus')
    AND cardinality(peak_months) = 0;

UPDATE public.mushroom_catalog SET peak_months = '{11,12,1,2}'::INT[]
  WHERE id = 'flammulina_velutipes' AND cardinality(peak_months) = 0;

-- ─── 2. Плеуротус — варіант B: розширюємо months + додаємо пік ────────────
UPDATE public.mushroom_catalog
SET months = '{6,7,8,9,10,11,12,1,2}'::INT[],
    peak_months = '{11,12,1,2}'::INT[]
WHERE id = 'pleurotus_ostreatus';

-- ─── 3. Self-check: рівно 4 види top20 без піку ───────────────────────────
DO $$
DECLARE
  no_peak_count INT;
  unexpected_count INT;
BEGIN
  SELECT COUNT(*) INTO no_peak_count
  FROM public.mushroom_catalog
  WHERE top20 = TRUE AND cardinality(peak_months) = 0;

  IF no_peak_count <> 4 THEN
    RAISE EXCEPTION 'Очікується 4 види top20 без піку, знайдено %', no_peak_count;
  END IF;

  SELECT COUNT(*) INTO unexpected_count
  FROM public.mushroom_catalog
  WHERE top20 = TRUE AND cardinality(peak_months) = 0
    AND id NOT IN ('boletus_luridus','leccinum_aurantiacum',
                   'suillus_luteus','russula_vesca');

  IF unexpected_count > 0 THEN
    RAISE EXCEPTION 'Знайдено % неочікуваних видів без піку', unexpected_count;
  END IF;

  RAISE NOTICE '✅ Catalog peak_months self-check passed';
END $$;
