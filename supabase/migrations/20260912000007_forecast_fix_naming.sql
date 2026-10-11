-- ============================================================================
-- Fix: expert_rules.mushroom_type → канонічні id каталогу
-- Проблема: forecast_seed (02) згенеровано ДО нормалізації каталогу,
-- тому mushroom_type містить hyphens і застарілі _spp.
-- ============================================================================

-- ─── 1. Hyphens → underscores ─────────────────────────────────────────────
UPDATE public.expert_rules
SET mushroom_type = REPLACE(mushroom_type, '-', '_')
WHERE mushroom_type LIKE '%-%';

-- ─── 2. Genus (_spp) → конкретні види з каталогу ──────────────────────────
UPDATE public.expert_rules SET mushroom_type = 'morchella_esculenta'
  WHERE mushroom_type IN ('morchella_spp', 'morchella_esculenta');

UPDATE public.expert_rules SET mushroom_type = 'russula_vesca'
  WHERE mushroom_type IN ('russula_spp', 'russula_vesca');

UPDATE public.expert_rules SET mushroom_type = 'lycoperdon_perlatum'
  WHERE mushroom_type IN ('lycoperdon_spp', 'lycoperdon_perlatum');

UPDATE public.expert_rules SET mushroom_type = 'xerocomus_subtomentosus'
  WHERE mushroom_type IN ('xerocomus_spp', 'xerocomus_subtomentosus');

-- ─── 3. Self-check A: 0 hyphens залишилось ────────────────────────────────
DO $$
DECLARE
  bad_count INT;
BEGIN
  SELECT COUNT(*) INTO bad_count FROM public.expert_rules
  WHERE mushroom_type LIKE '%-%';
  IF bad_count > 0 THEN
    RAISE EXCEPTION 'Залишилось % mushroom_type з hyphens', bad_count;
  END IF;
  RAISE NOTICE '✅ Self-check A: 0 hyphens';
END $$;

-- ─── 4. Self-check B: coverage каталогу ───────────────────────────────────
DO $$
DECLARE
  orphan_count INT;
  orphan_list TEXT;
BEGIN
  SELECT COUNT(*), string_agg(mushroom_type, ', ')
  INTO orphan_count, orphan_list
  FROM public.expert_rules er
  LEFT JOIN public.mushroom_catalog mc ON mc.id = er.mushroom_type
  WHERE mc.id IS NULL;

  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'Знайдено % orphan mushroom_type: %', orphan_count, orphan_list;
  END IF;
  RAISE NOTICE '✅ Self-check B: all mushroom_type match catalog';
END $$;
