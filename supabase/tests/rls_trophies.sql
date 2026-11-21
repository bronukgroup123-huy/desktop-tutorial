-- ============================================================================
-- Трофеї (міграція 20261121100000; ADR-021 §21.10)
--   * рахуються лише підтверджені знахідки (фото пройшло перевірку EXIF), не відхилені й не видалені;
--   * види за сезон — різні види поточного року; білий гриб, лисички, Червона книга (лише приватна
--     точка), підказка ШІ збіглася з видом, зморшки навесні, зимовий опеньок узимку;
--   * походи — лише з Наглядачем, завершені «Я вдома»; вчасно, з чек-листом, з «Додому»;
--   * клієнт не читає user_trophies і не викликає trophy_stats.
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
BEGIN
  INSERT INTO public.mushroom_catalog (id, name_ua, name_lat, red_listed) VALUES
    ('zz_red_species', 'Тестовий рідкісний', 'Testus rarus', true)
  ON CONFLICT (id) DO UPDATE SET red_listed = true;

  INSERT INTO public.mushroom_picks (user_id, species_id, pick_type, ai_check, verification_status, captured_at, geom, mushroom_type)
  SELECT u, sp, pt, ac::jsonb, vs, ts::timestamptz, 'SRID=4326;POINT(28.6 50.4)', sp
  FROM (VALUES
    ('boletus_edulis', 'private', ok, 'pending', '2026-09-10 10:00+03'),
    ('boletus_edulis', 'public', ok || '{"top": [{"species_id": "boletus_edulis", "level": "high"}]}'::jsonb, 'pending', '2026-09-11 10:00+03'),
    ('cantharellus_cibarius', 'private', ok, 'pending', '2026-07-01 10:00+03'),
    ('morchella_esculenta', 'private', ok, 'pending', '2026-04-20 10:00+03'),
    ('flammulina_velutipes', 'private', ok, 'pending', '2026-01-15 10:00+02'),
    ('zz_red_species', 'private', ok, 'pending', '2026-08-01 10:00+03'),
    ('boletus_edulis', 'private', '{"exif": {"verified": false}}'::jsonb, 'pending', '2026-09-12 10:00+03'),  -- фото не пройшло перевірку
    ('boletus_edulis', 'private', ok, 'rejected', '2026-09-13 10:00+03'),                                    -- відхилено
    ('boletus_edulis', 'private', ok, 'pending', '2025-09-13 10:00+03')                                      -- минулий сезон
  ) AS v(sp, pt, ac, vs, ts);

  s := public.trophy_stats(u, '2026-11-21 12:00+02');
  IF (s->>'finds')::int <> 7 THEN RAISE EXCEPTION 'Test 1 failed: finds %', s; END IF;
  IF (s->>'species_season')::int <> 5 THEN RAISE EXCEPTION 'Test 2 failed: species_season %', s; END IF;
  IF (s->>'porcini')::int <> 3 THEN RAISE EXCEPTION 'Test 3 failed: porcini %', s; END IF;
  IF (s->>'chanterelle')::int <> 1 THEN RAISE EXCEPTION 'Test 4 failed: chanterelle %', s; END IF;
  IF (s->>'red_book_private')::int <> 1 THEN RAISE EXCEPTION 'Test 5 failed: red_book %', s; END IF;
  IF (s->>'ai_match')::int <> 1 THEN RAISE EXCEPTION 'Test 6 failed: ai_match %', s; END IF;
  IF (s->>'morels_spring')::int <> 1 OR (s->>'winter_honey')::int <> 1 THEN RAISE EXCEPTION 'Test 7 failed: seasons %', s; END IF;

  -- Походи з Наглядачем
  INSERT INTO public.friendships (user_a, user_b, status, requested_by) VALUES (u, g, 'accepted', u);
  INSERT INTO public.guardian_links (owner_id, guardian_id, status) VALUES (u, g, 'accepted');
  INSERT INTO public.hikes (owner_id, route, started_at, expected_return, checklist_done)
  VALUES (u, '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-20 08:00+02', '2026-11-20 14:00+02', true) RETURNING id INTO h;
  INSERT INTO public.hike_guardians VALUES (h, g);
  UPDATE public.hikes SET status = 'closed', closed_at = '2026-11-20 13:00+02', closed_reason = 'home', used_home_nav = true WHERE id = h;
  INSERT INTO public.hikes (owner_id, route, started_at, expected_return)
  VALUES (u, '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-21 08:00+02', '2026-11-21 10:00+02') RETURNING id INTO h;
  UPDATE public.hikes SET status = 'closed', closed_at = '2026-11-21 11:30+02', closed_reason = 'home' WHERE id = h;  -- запізнився

  s := public.trophy_stats(u, '2026-11-21 12:00+02');
  IF (s->>'hikes_safe')::int <> 2 THEN RAISE EXCEPTION 'Test 8 failed: hikes_safe %', s; END IF;
  IF (s->>'hikes_on_time')::int <> 1 THEN RAISE EXCEPTION 'Test 9 failed: on_time %', s; END IF;
  IF (s->>'hikes_checklist')::int <> 1 OR (s->>'hikes_home_nav')::int <> 1 THEN RAISE EXCEPTION 'Test 10 failed: flags %', s; END IF;
  IF (s->>'has_guardian')::int <> 1 OR (s->>'friends')::int <> 1 THEN RAISE EXCEPTION 'Test 11 failed: social %', s; END IF;

  s := public.trophy_stats(g, '2026-11-21 12:00+02');
  IF (s->>'guarded_hikes')::int <> 1 THEN RAISE EXCEPTION 'Test 12 failed: guarded %', s; END IF;
  IF (s->>'finds')::int <> 0 THEN RAISE EXCEPTION 'Test 13 failed: others finds %', s; END IF;

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
    PERFORM public.trophy_stats('c1000000-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'Test 16 failed: client runs trophy_stats';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

ROLLBACK;
