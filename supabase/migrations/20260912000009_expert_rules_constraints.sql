-- ============================================================================
-- FK + CHECK: expert_rules ↔ mushroom_catalog
-- 1. FK mushroom_type → mushroom_catalog.id
-- 2. CHECK-тригер: заборона отруйних / ЧК / неїстівних
-- 3. Self-check: усі 20 існуючих видів безпечні
-- ============================================================================

-- ─── 1. FK ────────────────────────────────────────────────────────────────
ALTER TABLE public.expert_rules
  DROP CONSTRAINT IF EXISTS expert_rules_catalog_fk;

ALTER TABLE public.expert_rules
  ADD CONSTRAINT expert_rules_catalog_fk
  FOREIGN KEY (mushroom_type) REFERENCES public.mushroom_catalog(id)
  ON UPDATE CASCADE ON DELETE RESTRICT;

-- ─── 2. CHECK-тригер: забороняє отруйні/ЧК/неїстівні ──────────────────────
CREATE OR REPLACE FUNCTION public.check_expert_rules_safe()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  catalog_edibility TEXT;
  catalog_red_listed BOOLEAN;
BEGIN
  SELECT edibility, red_listed
  INTO catalog_edibility, catalog_red_listed
  FROM public.mushroom_catalog
  WHERE id = NEW.mushroom_type;

  IF catalog_edibility IS NULL THEN
    RETURN NEW;  -- FK це вже гарантує
  END IF;

  IF catalog_red_listed = TRUE THEN
    RAISE EXCEPTION 'Cannot add red-listed species to expert_rules: %', NEW.mushroom_type;
  END IF;

  IF catalog_edibility IN ('poisonous','deadly_poisonous','inedible') THEN
    RAISE EXCEPTION 'Cannot add % species to expert_rules: %',
      catalog_edibility, NEW.mushroom_type;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS expert_rules_safety_check ON public.expert_rules;
CREATE TRIGGER expert_rules_safety_check
  BEFORE INSERT OR UPDATE ON public.expert_rules
  FOR EACH ROW EXECUTE FUNCTION public.check_expert_rules_safe();

-- ─── 3. Self-check: усі 20 існуючих mushroom_type — безпечні ──────────────
DO $$
DECLARE
  unsafe_count INT;
  orphan_count INT;
BEGIN
  SELECT COUNT(*) INTO orphan_count
  FROM public.expert_rules er
  LEFT JOIN public.mushroom_catalog mc ON mc.id = er.mushroom_type
  WHERE mc.id IS NULL;

  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'FK check failed: % orphan mushroom_type', orphan_count;
  END IF;

  SELECT COUNT(*) INTO unsafe_count
  FROM public.expert_rules er
  JOIN public.mushroom_catalog mc ON mc.id = er.mushroom_type
  WHERE mc.red_listed = TRUE
     OR mc.edibility IN ('poisonous','deadly_poisonous','inedible');

  IF unsafe_count > 0 THEN
    RAISE EXCEPTION 'Знайдено % небезпечних видів у expert_rules', unsafe_count;
  END IF;
  RAISE NOTICE '✅ Constraint self-check: усі 20 видів безпечні';
END $$;
