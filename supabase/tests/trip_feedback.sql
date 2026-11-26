-- ============================================================================
-- B3.11: «Знайшли?» (міграція 20261126140000; ADR-014, ADR-019 §19.9)
--   * результат аналізу ділянки записується як переглянутий прогноз (forecast_views);
--   * відгук без зв'язку з прогнозом / Наглядачем → no_trip_context; далеко від ділянки — теж;
--   * бали: акаунту — pending на 24 год, один на добу; гостю — ні; повторний відгук — already_answered;
--   * суперечність зі своєю точкою з фото знижує довіру й забирає бали; нарахування — через 24 год,
--     лише за довіри ≥ 0,5; «не знайшов» — вага калібрування 0;
--   * «збувся N з M»; функції — лише service_role.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email, is_anonymous) VALUES
  ('f1000000-0000-4000-8000-0000000071f1', 'tf1@test.local', false),
  ('f2000000-0000-4000-8000-0000000071f2', 'tf2@test.local', true);

SET LOCAL ROLE service_role;

DO $$
DECLARE
  u1 CONSTANT UUID := 'f1000000-0000-4000-8000-0000000071f1';
  g  CONSTANT UUID := 'f2000000-0000-4000-8000-0000000071f2';
  today DATE := (now() AT TIME ZONE 'Europe/Kyiv')::date;
  rid INT;
  la DOUBLE PRECISION;
  lo DOUBLE PRECISION;
  area UUID;
  area_g UUID;
  r JSONB;
  v RECORD;
BEGIN
  SELECT r2.id, extensions.ST_Y(extensions.ST_PointOnSurface(r2.polygon::extensions.geometry)),
         extensions.ST_X(extensions.ST_PointOnSurface(r2.polygon::extensions.geometry))
    INTO rid, la, lo
  FROM public.regions r2 ORDER BY r2.id LIMIT 1;

  SELECT a.id INTO area FROM public.create_analysis_area(u1, 1, la, lo, 5, rid) a;
  SELECT a.id INTO area_g FROM public.create_analysis_area(g, 1, la, lo, 5, rid) a;

  -- без прогнозу — немає зв'язку
  r := public.submit_trip_feedback(u1, false, today, la, lo, 'found');
  IF r->>'code' <> 'no_trip_context' THEN RAISE EXCEPTION 'Test 1 failed: %', r; END IF;

  -- результат аналізу = переглянутий прогноз на дні горизонту
  PERFORM public.save_analysis_result(u1, area, jsonb_build_object('days', jsonb_build_array(
    jsonb_build_object('date', today::TEXT, 'level', 'high', 'top1', jsonb_build_object('mushroom_type', 'boletus_edulis')),
    jsonb_build_object('date', (today + 1)::TEXT, 'level', 'low', 'top1', NULL))));
  SELECT * INTO v FROM public.forecast_views WHERE user_id = u1 AND area_id = area;
  IF v.viewed_on <> today OR jsonb_array_length(v.days) <> 2 OR v.days->0->>'species' <> 'boletus_edulis' THEN
    RAISE EXCEPTION 'Test 2 failed: forecast view %', row_to_json(v);
  END IF;

  -- далеко від ділянки (≈ 20 км) — немає зв'язку
  r := public.submit_trip_feedback(u1, false, today, la + 0.18, lo, 'found');
  IF r->>'code' <> 'no_trip_context' THEN RAISE EXCEPTION 'Test 3 failed: %', r; END IF;

  -- поруч (≈ 3 км) — прийнято, бали відкладені
  r := public.submit_trip_feedback(u1, false, today, la + 0.027, lo, 'found');
  IF (r->>'ok')::boolean IS NOT TRUE OR r->>'points' <> 'pending' OR r->>'source' <> 'forecast'
     OR r->>'predicted_level' <> 'high' THEN
    RAISE EXCEPTION 'Test 4 failed: %', r;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.trip_feedback WHERE id = (r->>'id')::uuid
      AND award_after > now() + INTERVAL '23 hours' AND calibration_weight = 1) THEN
    RAISE EXCEPTION 'Test 4b failed: award_after / weight';
  END IF;

  -- той самий похід ще раз
  r := public.submit_trip_feedback(u1, false, today, la, lo, 'not_found');
  IF r->>'code' <> 'already_answered' THEN RAISE EXCEPTION 'Test 5 failed: %', r; END IF;

  -- гість: відгук приймається, балів немає
  PERFORM public.save_analysis_result(g, area_g, jsonb_build_object('days', jsonb_build_array(
    jsonb_build_object('date', today::TEXT, 'level', 'low'))));
  r := public.submit_trip_feedback(g, true, today, la, lo, 'not_found');
  IF (r->>'ok')::boolean IS NOT TRUE OR r->>'points' <> 'none' OR r->>'points_reason' <> 'guest' THEN
    RAISE EXCEPTION 'Test 6 failed: %', r;
  END IF;
  IF (SELECT calibration_weight FROM public.trip_feedback WHERE user_id = g) <> 0 THEN
    RAISE EXCEPTION 'Test 6b failed: not_found must not go to calibration';
  END IF;

  -- день поза межами (позавчора) — помилка
  r := public.submit_trip_feedback(u1, false, today - 2, la, lo, 'found');
  IF r->>'code' <> 'validation_error' THEN RAISE EXCEPTION 'Test 7 failed: %', r; END IF;
END $$;

-- другий відгук того ж дня (вчорашній похід, інша ділянка) — без балів; суперечність — мінус довіра
DO $$
DECLARE
  u1 CONSTANT UUID := 'f1000000-0000-4000-8000-0000000071f1';
  today DATE := (now() AT TIME ZONE 'Europe/Kyiv')::date;
  area2 UUID;
  la DOUBLE PRECISION;
  lo DOUBLE PRECISION;
  r JSONB;
BEGIN
  SELECT extensions.ST_Y(center::extensions.geometry) + 0.2, extensions.ST_X(center::extensions.geometry)
    INTO la, lo FROM public.analysis_areas WHERE user_id = u1 AND slot = 1;
  INSERT INTO public.analysis_areas (user_id, slot, center, size_km, region_id)
  SELECT u1, 2, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la), 4326)::extensions.geography, 5, region_id
  FROM public.analysis_areas WHERE user_id = u1 AND slot = 1
  RETURNING id INTO area2;
  -- прогноз, отриманий учора, на вчора
  INSERT INTO public.forecast_views (user_id, area_id, viewed_on, center, size_km, days)
  SELECT u1, area2, today - 1, center, 5, jsonb_build_array(jsonb_build_object('date', (today - 1)::TEXT, 'level', 'medium'))
  FROM public.analysis_areas WHERE id = area2;
  -- своя точка з фото там же вчора
  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, verification_status, captured_at)
  VALUES (u1, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la), 4326)::extensions.geography, 'unknown',
          'private', 'pending', (today - 1)::timestamp + INTERVAL '10 hours');

  r := public.submit_trip_feedback(u1, false, today - 1, la, lo, 'not_found');
  IF (r->>'ok')::boolean IS NOT TRUE OR r->>'points' <> 'none' OR r->>'points_reason' <> 'contradiction' THEN
    RAISE EXCEPTION 'Test 8 failed: %', r;
  END IF;
  IF (SELECT feedback_trust FROM public.users WHERE id = u1) <> 0.75 THEN
    RAISE EXCEPTION 'Test 8b failed: trust %', (SELECT feedback_trust FROM public.users WHERE id = u1);
  END IF;

  -- похід із Наглядачем без прогнозу поруч: зв'язок — похід; бали вже були сьогодні → daily_limit
  INSERT INTO public.hikes (id, owner_id, route, started_at, expected_return, status, closed_at, closed_reason)
  VALUES ('f1000000-0000-4000-8000-0000000071b1', u1, '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', now() - INTERVAL '5 hours', now(), 'closed',
          now() - INTERVAL '1 hour', 'home');
  INSERT INTO public.hike_points (hike_id, lat, lng, accuracy, recorded_at)
  VALUES ('f1000000-0000-4000-8000-0000000071b1', la + 0.5, lo, 8, now() - INTERVAL '3 hours');
  r := public.submit_trip_feedback(u1, false, today, la + 0.51, lo, 'found');
  IF (r->>'ok')::boolean IS NOT TRUE OR r->>'source' <> 'hike' OR r->>'points' <> 'none'
     OR r->>'points_reason' <> 'daily_limit' OR r ? 'predicted_level' AND r->>'predicted_level' IS NOT NULL THEN
    RAISE EXCEPTION 'Test 8c failed: %', r;
  END IF;
  r := public.submit_trip_feedback(u1, false, today, la + 0.5, lo, 'found');
  IF r->>'code' <> 'already_answered' THEN RAISE EXCEPTION 'Test 8d failed: %', r; END IF;

  -- збувся: high+found (так), medium+not_found (ні) → 1 з 2; похід без прогнозу не рахується
  IF (SELECT row(hits, total)::TEXT FROM public.trip_feedback_accuracy(u1)) <> '(1,2)' THEN
    RAISE EXCEPTION 'Test 9 failed: accuracy %', (SELECT row(hits, total)::TEXT FROM public.trip_feedback_accuracy(u1));
  END IF;

  -- нарахування: ще рано — нічого
  IF public.award_due_trip_feedback() <> 0 THEN RAISE EXCEPTION 'Test 10 failed: awarded too early'; END IF;
  -- минули 24 год — +2 один раз
  UPDATE public.trip_feedback SET award_after = now() - INTERVAL '1 minute' WHERE user_id = u1 AND points = 'pending';
  IF public.award_due_trip_feedback() <> 1 OR public.award_due_trip_feedback() <> 0 THEN
    RAISE EXCEPTION 'Test 10b failed: award count';
  END IF;
  IF (SELECT rating FROM public.users WHERE id = u1) <> 2
     OR NOT EXISTS (SELECT 1 FROM public.rating_events WHERE user_id = u1 AND reason = 'trip_feedback' AND delta = 2) THEN
    RAISE EXCEPTION 'Test 10c failed: rating %', (SELECT rating FROM public.users WHERE id = u1);
  END IF;
END $$;

-- довіра нижче порогу на момент нарахування — бали не нараховуються
DO $$
DECLARE
  u1 CONSTANT UUID := 'f1000000-0000-4000-8000-0000000071f1';
BEGIN
  INSERT INTO public.trip_feedback (user_id, trip_day, source, answer, points, award_after)
  VALUES (u1, (now() AT TIME ZONE 'Europe/Kyiv')::date - 1, 'hike', 'found', 'pending', now() - INTERVAL '1 minute');
  UPDATE public.users SET feedback_trust = 0.25 WHERE id = u1;
  IF public.award_due_trip_feedback() <> 0 THEN RAISE EXCEPTION 'Test 11 failed: awarded with low trust'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.trip_feedback WHERE user_id = u1 AND points_reason = 'low_trust' AND points = 'none') THEN
    RAISE EXCEPTION 'Test 11b failed: low_trust not recorded';
  END IF;
END $$;

-- клієнт напряму — ні таблиць, ні функцій
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.submit_trip_feedback('f1000000-0000-4000-8000-0000000071f1', false, current_date, 50.0, 30.0, 'found');
    RAISE EXCEPTION 'Test 12 failed: authenticated called submit_trip_feedback';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM public.trip_feedback;
    RAISE EXCEPTION 'Test 12b failed: authenticated read trip_feedback';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM public.forecast_views;
    RAISE EXCEPTION 'Test 12c failed: authenticated read forecast_views';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

ROLLBACK;
