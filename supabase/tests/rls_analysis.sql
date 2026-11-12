-- ============================================================================
-- Аналіз ділянки (міграції 20261111110000, 20261112100000; B2.9, ADR-015 §15.4)
--   * ділянки: користувач читає лише свої; запис — тільки service_role
--   * ділянку не пересувають: лише створюють у вільний слот і видаляють
--   * ліміт на добу — на слот: «видалити → створити» його не обнуляє
--   * лічильник аналізів клієнтам недоступний; ліміт на добу не перевищується
--   * analyze_area_forest: межі квадрата і площа лісів за типами
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a1a1a1a1-0000-4000-8000-0000000029a1', 'owner29@test.local'),
  ('b2b2b2b2-0000-4000-8000-0000000029b2', 'other29@test.local');

CREATE TEMP TABLE fx ON COMMIT DROP AS
SELECT r.id AS region_id,
       extensions.ST_Y(p.pt) AS lat, extensions.ST_X(p.pt) AS lng
FROM (SELECT id, polygon FROM public.regions ORDER BY id LIMIT 1) r,
     LATERAL (SELECT extensions.ST_PointOnSurface(r.polygon) AS pt) p;
GRANT SELECT ON fx TO service_role, authenticated;

-- Сосновий ліс ~2×2 км навколо центру і дубовий ~1×1 км поруч (вік 60 і 90 років).
INSERT INTO public.forest_zones (polygon, forest_type, stand_age_years, region_id)
SELECT extensions.ST_Multi(extensions.ST_MakeEnvelope(lng - 0.014, lat - 0.009, lng + 0.014, lat + 0.009, 4326)), 'pine', 60, region_id FROM fx
UNION ALL
SELECT extensions.ST_Multi(extensions.ST_MakeEnvelope(lng + 0.016, lat - 0.0045, lng + 0.030, lat + 0.0045, 4326)), 'oak', 90, region_id FROM fx;

SET LOCAL ROLE service_role;

DO $$
DECLARE
  owner CONSTANT UUID := 'a1a1a1a1-0000-4000-8000-0000000029a1';
  rid INT; la FLOAT8; lo FLOAT8;
  area UUID; area2 UUID; n INT; i INT; f JSONB; w FLOAT8; h FLOAT8;
BEGIN
  SELECT region_id, lat, lng INTO rid, la, lo FROM fx;

  -- ─── 1. Ділянка створюється у вільному слоті і не пересувається ────────────
  SELECT a.id INTO area FROM public.create_analysis_area(owner, 1, la, lo, 5, rid) a;
  IF area IS NULL THEN RAISE EXCEPTION 'Test 1 failed: first area not created'; END IF;
  SELECT a.id INTO area2 FROM public.create_analysis_area(owner, 1, la + 0.01, lo, 5, rid) a;
  IF area2 IS NOT NULL THEN RAISE EXCEPTION 'Test 1b failed: second area in a full free slot'; END IF;
  IF (SELECT extensions.ST_Y(center::extensions.geometry) FROM public.analysis_areas WHERE id = area) <> la THEN
    RAISE EXCEPTION 'Test 1c failed: existing area was moved';
  END IF;
  -- Pro: другий слот
  SELECT a.id, a.slot INTO area2, n FROM public.create_analysis_area(owner, 3, la + 0.01, lo, 10, rid) a;
  IF area2 IS NULL OR n <> 2 THEN RAISE EXCEPTION 'Test 1d failed: Pro area not in slot 2 (%)', n; END IF;
  BEGIN
    PERFORM public.create_analysis_area(owner, 3, la, lo, 7, rid);
    RAISE EXCEPTION 'Test 1e failed: size 7 km accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF NOT public.delete_analysis_area(owner, area2) OR public.delete_analysis_area(owner, area2) THEN
    RAISE EXCEPTION 'Test 1f failed: delete did not report correctly';
  END IF;
  IF public.delete_analysis_area('b2b2b2b2-0000-4000-8000-0000000029b2', area) THEN
    RAISE EXCEPTION 'Test 1g failed: another user deleted the area';
  END IF;
  PERFORM public.save_analysis_result(owner, area, '{"date":"2026-11-12"}'::jsonb);
  IF (SELECT last_result->>'date' FROM public.analysis_areas WHERE id = area) <> '2026-11-12' THEN
    RAISE EXCEPTION 'Test 1h failed: last result not saved';
  END IF;

  -- ─── 2. Ліміт слоту: 5 на добу; повернення звільняє один ─────────────────
  IF public.analysis_used_today(owner, 1) <> 0 THEN RAISE EXCEPTION 'Test 2 failed: usage is not 0'; END IF;
  FOR i IN 1..5 LOOP
    n := public.consume_analysis(owner, 1, 5);
    IF n IS DISTINCT FROM i THEN RAISE EXCEPTION 'Test 2b failed: consume #% returned %', i, n; END IF;
  END LOOP;
  IF public.consume_analysis(owner, 1, 5) IS NOT NULL THEN
    RAISE EXCEPTION 'Test 2c failed: 6th analysis allowed';
  END IF;
  IF public.analysis_used_today(owner, 1) <> 5 THEN RAISE EXCEPTION 'Test 2d failed: usage is not 5'; END IF;
  PERFORM public.refund_analysis(owner, 1);
  IF public.analysis_used_today(owner, 1) <> 4 OR public.consume_analysis(owner, 1, 5) <> 5 THEN
    RAISE EXCEPTION 'Test 2e failed: refund did not free one analysis';
  END IF;
  IF public.consume_analysis(owner, 1, 0) IS NOT NULL THEN
    RAISE EXCEPTION 'Test 2f failed: zero limit allowed an analysis';
  END IF;
  -- «видалити → створити» не обнуляє ліміт слоту
  PERFORM public.delete_analysis_area(owner, area);
  SELECT a.id INTO area FROM public.create_analysis_area(owner, 1, la, lo, 5, rid) a;
  IF public.consume_analysis(owner, 1, 5) IS NOT NULL THEN
    RAISE EXCEPTION 'Test 2g failed: delete + create reset the daily limit';
  END IF;

  -- ─── 3. Ліс у квадраті 5×5 км ──────────────────────────────────────────────
  f := public.analyze_area_forest(rid, la, lo, 5);
  w := extensions.ST_Distance(
    extensions.ST_SetSRID(extensions.ST_MakePoint((f->'bbox'->>0)::float8, la), 4326)::extensions.geography,
    extensions.ST_SetSRID(extensions.ST_MakePoint((f->'bbox'->>2)::float8, la), 4326)::extensions.geography);
  h := extensions.ST_Distance(
    extensions.ST_SetSRID(extensions.ST_MakePoint(lo, (f->'bbox'->>1)::float8), 4326)::extensions.geography,
    extensions.ST_SetSRID(extensions.ST_MakePoint(lo, (f->'bbox'->>3)::float8), 4326)::extensions.geography);
  IF abs(w - 5000) > 25 OR abs(h - 5000) > 25 THEN
    RAISE EXCEPTION 'Test 3 failed: square is % × % m, expected 5000 × 5000', round(w), round(h);
  END IF;
  IF (f->>'area_km2')::int <> 25 OR (f->>'forest_km2')::float8 <= 0 OR (f->>'forest_km2')::float8 > 25 THEN
    RAISE EXCEPTION 'Test 3b failed: forest summary %', f;
  END IF;
  IF f->'types'->0->>'forest_type' <> 'pine' OR (f->'types'->0->>'stand_age_years')::int <> 60
     OR f->'types'->1->>'forest_type' <> 'oak' OR (f->'types'->0->>'km2')::float8 <= (f->'types'->1->>'km2')::float8 THEN
    RAISE EXCEPTION 'Test 3c failed: forest types %', f->'types';
  END IF;

  -- у квадраті 10×10 км лісу не менше, ніж у 5×5
  IF (public.analyze_area_forest(rid, la, lo, 10)->>'forest_km2')::float8 < (f->>'forest_km2')::float8 THEN
    RAISE EXCEPTION 'Test 3d failed: 10x10 has less forest than 5x5';
  END IF;
  -- чужа область — її лісів у відповіді немає
  IF rid <> (SELECT max(id) FROM public.regions)
     AND (public.analyze_area_forest((SELECT max(id) FROM public.regions), la, lo, 5)->>'forest_km2')::float8 <> 0 THEN
    RAISE EXCEPTION 'Test 3e failed: forests of another region counted';
  END IF;
END $$;

RESET ROLE;

-- ─── 4. Клієнт: читає лише свої ділянки, не пише і не викликає функції ──────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  '{"sub":"b2b2b2b2-0000-4000-8000-0000000029b2","role":"authenticated","is_anonymous":false}', true);
SELECT set_config('request.jwt.claim.sub', 'b2b2b2b2-0000-4000-8000-0000000029b2', true);

DO $$
DECLARE rid INT; la FLOAT8; lo FLOAT8;
BEGIN
  SELECT region_id, lat, lng INTO rid, la, lo FROM fx;
  IF EXISTS (SELECT 1 FROM public.analysis_areas) THEN
    RAISE EXCEPTION 'Test 4 failed: stranger sees foreign analysis areas';
  END IF;
  BEGIN
    PERFORM 1 FROM public.analysis_usage LIMIT 1;
    RAISE EXCEPTION 'Test 4b failed: client reads analysis_usage';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO public.analysis_areas (user_id, slot, center, size_km, region_id)
    VALUES ('b2b2b2b2-0000-4000-8000-0000000029b2', 1, 'SRID=4326;POINT(30.5 50.4)', 10, rid);
    RAISE EXCEPTION 'Test 4c failed: client created a 10x10 area directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.create_analysis_area('b2b2b2b2-0000-4000-8000-0000000029b2', 3, la, lo, 10, rid);
    RAISE EXCEPTION 'Test 4d failed: client can call create_analysis_area';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.consume_analysis('b2b2b2b2-0000-4000-8000-0000000029b2', 1, 100);
    RAISE EXCEPTION 'Test 4e failed: client can call consume_analysis';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.refund_analysis('b2b2b2b2-0000-4000-8000-0000000029b2', 1);
    RAISE EXCEPTION 'Test 4f failed: client can call refund_analysis';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.delete_analysis_area('b2b2b2b2-0000-4000-8000-0000000029b2', gen_random_uuid());
    RAISE EXCEPTION 'Test 4h failed: client can call delete_analysis_area';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.analyze_area_forest(rid, la, lo, 5);
    RAISE EXCEPTION 'Test 4g failed: client can call analyze_area_forest';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

-- власник бачить свою ділянку
SELECT set_config('request.jwt.claims',
  '{"sub":"a1a1a1a1-0000-4000-8000-0000000029a1","role":"authenticated","is_anonymous":false}', true);
SELECT set_config('request.jwt.claim.sub', 'a1a1a1a1-0000-4000-8000-0000000029a1', true);
DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.analysis_areas;
  IF n <> 1 THEN RAISE EXCEPTION 'Test 5 failed: owner sees % own areas, expected 1', n; END IF;
  RAISE NOTICE '✅ rls_analysis: all checks passed';
END $$;

ROLLBACK;
