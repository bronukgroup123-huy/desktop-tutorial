-- ============================================================================
-- BACKEND_PLAN B2.4 «Отруйні — ніколи»: кожне правило прогнозу (expert_rules) — для виду, який довідник
-- вважає їстівним або умовно їстівним. Додали правило отруйного виду чи змінили їстівність у довіднику —
-- тест падає ще до розгортання (код прогнозу такий вид і так відкине, але правило не має існувати).
-- ============================================================================
DO $$
DECLARE
  bad text;
BEGIN
  SELECT string_agg(e.mushroom_type || ' (' || coalesce(c.edibility, 'немає в довіднику') || ')', ', ')
    INTO bad
  FROM public.expert_rules e
  LEFT JOIN public.mushroom_catalog c ON c.id = e.mushroom_type
  WHERE c.edibility IS NULL OR c.edibility NOT IN ('edible', 'conditionally_edible');
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL правила прогнозу для неїстівних видів: %', bad;
  END IF;
  RAISE NOTICE 'OK усі правила прогнозу — для їстівних видів';
END;
$$;
