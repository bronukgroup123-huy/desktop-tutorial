-- ============================================================================
-- Трофеї (міграція 20261121100000; ADR-021 §21.10)
--   * trophy_finds — лише фото, що пройшло перевірку EXIF, не відхилені й не видалені; з першою
--     підказкою розпізнавання, позначкою модератора й Червоної книги;
--   * закритий похід зберігає підсумок (метри за точками з добрим GPS, кількість точок), трек
--     видаляється;
--   * у залік — лише справжні походи (≥ 30 хв, ≥ 1 км, ≥ 10 точок), один на день; «вчасно» —
--     не пізніше запланованого й не раніше ніж за 1,5 год; Наглядач — у справжніх походах друзів;
--   * клієнт не читає user_trophies і не викликає trophy_finds / trophy_stats.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('c1000000-0000-4000-8000-000000000001', 'tr1@test.local'),
  ('c1000000-0000-4000-8000-000000000002', 'tr2@test.local');

SET LOCAL ROLE service_role;

DO $$
DECLARE
  u CONSTANT UUID := 'c1000000-0000-4000-8000-000000000001';
  g CONSTANT UUID := 'c1000000-0000-4000-8000-000000000002';
  ok CONSTANT JSONB := '{"exif": {"verified": true}}';
  s JSONB;
  h UUID;
  n INT;
  r RECORD;
  i INT;
BEGIN
  INSERT INTO public.mushroom_catalog (id, name_ua, name_lat, red_listed) VALUES
    ('zz_red_species', 'Тестовий рідкісний', 'Testus rarus', true)
  ON CONFLICT (id) DO UPDATE SET red_listed = true;

  INSERT INTO public.mushroom_picks (user_id, species_id, pick_type, ai_check, verification_status, captured_at, geom, mushroom_type)
  SELECT u, sp, 'private', ac::jsonb, vs, ts::timestamptz, 'SRID=4326;POINT(28.6 50.4)', sp
  FROM (VALUES
    ('boletus_edulis', ok || '{"top": [{"species_id": "boletus_edulis", "level": "high"}]}'::jsonb, 'pending', '2026-09-11 10:00+03'),
    ('zz_red_species', ok, 'verified', '2026-08-01 10:00+03'),
    ('boletus_edulis', '{"exif": {"verified": false}}'::jsonb, 'pending', '2026-09-12 10:00+03'),  -- фото не пройшло перевірку
    ('boletus_edulis', ok, 'rejected', '2026-09-13 10:00+03')                                      -- відхилено
  ) AS v(sp, ac, vs, ts);

  SELECT count(*) INTO n FROM public.trophy_finds(u);
  IF n <> 2 THEN RAISE EXCEPTION 'Test 1 failed: % finds (only EXIF-verified, not rejected)', n; END IF;
  SELECT * INTO r FROM public.trophy_finds(u) LIMIT 1;  -- найстаріша — Червона книга
  IF r.species_id <> 'zz_red_species' OR NOT r.moderated OR NOT r.red_listed THEN RAISE EXCEPTION 'Test 2 failed: %', r; END IF;
  IF abs(r.lat - 50.4) > 1e-6 OR abs(r.lng - 28.6) > 1e-6 THEN RAISE EXCEPTION 'Test 3 failed: coords %', r; END IF;
  SELECT * INTO r FROM public.trophy_finds(u) OFFSET 1;
  IF r.ai_species <> 'boletus_edulis' OR r.ai_level <> 'high' OR r.moderated THEN RAISE EXCEPTION 'Test 4 failed: %', r; END IF;
  IF r.local_at <> '2026-09-11 10:00'::timestamp THEN RAISE EXCEPTION 'Test 5 failed: local time %', r.local_at; END IF;

  -- Похід: ~1,1 км на північ (11 відрізків по ~100 м), 12 точок, 3 год → справжній
  INSERT INTO public.friendships (user_a, user_b, status, requested_by) VALUES (u, g, 'accepted', u);
  INSERT INTO public.guardian_links (owner_id, guardian_id, status) VALUES (u, g, 'accepted');
  INSERT INTO public.hikes (owner_id, route, started_at, expected_return, checklist_done)
  VALUES (u, '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-20 08:00+02', '2026-11-20 11:30+02', true) RETURNING id INTO h;
  INSERT INTO public.hike_guardians VALUES (h, g);
  FOR i IN 0..11 LOOP
    INSERT INTO public.hike_points (hike_id, lat, lng, accuracy, recorded_at)
    VALUES (h, 50.4 + i * 0.0009, 28.6, 8, '2026-11-20 08:00+02'::timestamptz + make_interval(mins => i * 15));
  END LOOP;
  INSERT INTO public.hike_points (hike_id, lat, lng, accuracy, low_accuracy, recorded_at)
  VALUES (h, 51.0, 29.0, 400, true, '2026-11-20 09:07+02');  -- стрибок GPS — не рахується
  UPDATE public.hikes SET status = 'closed', closed_at = '2026-11-20 11:00+02', closed_reason = 'home', used_home_nav = true WHERE id = h;
  SELECT walked_m, points_count INTO r FROM public.hikes WHERE id = h;
  IF r.walked_m NOT BETWEEN 1050 AND 1150 OR r.points_count <> 12 THEN RAISE EXCEPTION 'Test 6 failed: summary %', r; END IF;
  SELECT count(*) INTO n FROM public.hike_points WHERE hike_id = h;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 7 failed: track kept'; END IF;

  -- Того ж дня ще один справжній похід — у залік не йде (один на день); і 10-хвилинний «похід» — не справжній
  INSERT INTO public.hikes (owner_id, route, started_at, expected_return, walked_m, points_count, status, closed_at, closed_reason)
  VALUES (u, '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-20 13:00+02', '2026-11-20 15:00+02', 2000, 30, 'closed', '2026-11-20 14:59+02', 'home'),
         (u, '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-21 09:00+02', '2026-11-21 11:00+02', 1500, 20, 'closed', '2026-11-21 09:10+02', 'home');

  s := public.trophy_stats(u, '2026-11-21 12:00+02');
  IF (s->>'hikes_safe')::int <> 1 THEN RAISE EXCEPTION 'Test 8 failed: hikes_safe %', s; END IF;
  IF (s->>'hikes_on_time')::int <> 1 THEN RAISE EXCEPTION 'Test 9 failed: on_time %', s; END IF;
  IF (s->>'hikes_checklist')::int <> 1 OR (s->>'hikes_home_nav')::int <> 1 THEN RAISE EXCEPTION 'Test 10 failed: flags %', s; END IF;
  IF (s->>'has_guardian')::int <> 1 OR (s->>'friends')::int <> 1 THEN RAISE EXCEPTION 'Test 11 failed: social %', s; END IF;

  -- Повернувся на 3 год раніше запланованого — не «вчасно»
  UPDATE public.hikes SET expected_return = '2026-11-20 14:00+02' WHERE id = h;
  s := public.trophy_stats(u, '2026-11-21 12:00+02');
  IF (s->>'hikes_on_time')::int <> 1 THEN RAISE EXCEPTION 'Test 12 failed: early return counted as on time? %', s; END IF; -- лишився другий похід того дня (14:59 ≤ 15:00)

  s := public.trophy_stats(g, '2026-11-21 12:00+02');
  IF (s->>'guarded_hikes')::int <> 1 THEN RAISE EXCEPTION 'Test 13 failed: guarded %', s; END IF;

  INSERT INTO public.user_trophies (user_id, trophy_id) VALUES (u, 'first_find');
  BEGIN
    INSERT INTO public.user_trophies (user_id, trophy_id) VALUES (u, 'Bad Id!');
    RAISE EXCEPTION 'Test 14 failed: bad trophy id accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000001', true);
DO $$
BEGIN
  BEGIN
    PERFORM count(*) FROM public.user_trophies;
    RAISE EXCEPTION 'Test 15 failed: client reads user_trophies';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM count(*) FROM public.trophy_finds('c1000000-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'Test 16 failed: client runs trophy_finds';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.trophy_stats('c1000000-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'Test 17 failed: client runs trophy_stats';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

ROLLBACK;
