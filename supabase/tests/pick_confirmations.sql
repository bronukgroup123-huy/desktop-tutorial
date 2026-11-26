-- ============================================================================
-- B3.8a: підтвердження публічної точки відповіддю знахідкою (міграція 20261126150000; ADR-019 §19.5)
--   * свою точку — ні; інший вид — ні; далі 200 м — не зараховано (відповідь лишається звичайною точкою);
--   * без перевіреного EXIF — не зараховано; не більше 2 спроб на чужу точку;
--   * місце підмінене програмою (mock location) або телефон не повідомив — не зараховано (B3.8b);
--   * 1 зарахована відповідь → «Підтверджена»; з twin_alert — лише після 2;
--   * бали: +3 тому, хто підтвердив, +2 автору; взаємні підтвердження двох людей — до 3 за 30 днів;
--   * картка показує кількість; функції й таблиця — лише service_role.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('c0000001-0000-4000-8000-0000000081c1', 'author@test.local'),
  ('c0000002-0000-4000-8000-0000000081c2', 'helper@test.local'),
  ('c0000003-0000-4000-8000-0000000081c3', 'third@test.local');

SET LOCAL ROLE service_role;

DO $$
DECLARE
  author CONSTANT UUID := 'c0000001-0000-4000-8000-0000000081c1';
  helper CONSTANT UUID := 'c0000002-0000-4000-8000-0000000081c2';
  third  CONSTANT UUID := 'c0000003-0000-4000-8000-0000000081c3';
  sp TEXT := 'boletus_edulis';
  rid INT;
  la DOUBLE PRECISION;
  lo DOUBLE PRECISION;
  target UUID := gen_random_uuid();
  twin UUID := gen_random_uuid();
  r JSONB;
  reply UUID;
  card JSONB;
BEGIN
  SELECT r2.id, extensions.ST_Y(extensions.ST_PointOnSurface(r2.polygon::extensions.geometry)),
         extensions.ST_X(extensions.ST_PointOnSurface(r2.polygon::extensions.geometry))
    INTO rid, la, lo FROM public.regions r2 ORDER BY r2.id LIMIT 1;

  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
  VALUES
    (target, author, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la), 4326)::extensions.geography,
     extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.005, la), 4326)::extensions.geography, sp, sp, 'public', 'pending'),
    (twin, author, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.05, la), 4326)::extensions.geography,
     extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.055, la), 4326)::extensions.geography, sp, sp, 'public', 'pending');
  UPDATE public.mushroom_picks SET twin_alert = true WHERE id = twin;

  -- рання перевірка: своя точка, інший вид, неіснуюча
  IF public.can_confirm_pick(author, target, sp)->>'code' <> 'own_pick' THEN RAISE EXCEPTION 'Test 1 failed: own'; END IF;
  r := public.can_confirm_pick(helper, target, 'cantharellus_cibarius');
  IF r->>'code' <> 'species_mismatch' OR r->>'message' NOT LIKE '%того самого виду%' THEN RAISE EXCEPTION 'Test 2 failed: %', r; END IF;
  IF public.can_confirm_pick(helper, gen_random_uuid(), sp)->>'code' <> 'pick_not_found' THEN RAISE EXCEPTION 'Test 3 failed'; END IF;
  IF (public.can_confirm_pick(helper, target, sp)->>'allowed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Test 4 failed'; END IF;

  -- спроба 1: ≈ 330 м від справжнього місця — не зараховано, точка-відповідь лишається
  reply := gen_random_uuid();
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, ai_check)
  VALUES (reply, helper, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la + 0.003), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la + 0.004), 4326)::extensions.geography, sp, sp, 'public', 'pending',
          '{"exif":{"verified":true},"location":{"mocked":false}}');
  r := public.confirm_pick(helper, target, reply);
  IF (r->>'counted')::boolean OR r->>'reason' <> 'too_far' OR (r->>'confirmations')::int <> 0 THEN RAISE EXCEPTION 'Test 5 failed: %', r; END IF;
  IF (SELECT reply_to FROM public.mushroom_picks WHERE id = reply) <> target THEN RAISE EXCEPTION 'Test 5b failed: reply_to'; END IF;

  -- спроба 2: ≈ 110 м, але без перевіреного EXIF — не зараховано
  reply := gen_random_uuid();
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, ai_check)
  VALUES (reply, helper, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la + 0.001), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la + 0.002), 4326)::extensions.geography, sp, sp, 'public', 'pending',
          '{"exif":{"verified":false}}');
  r := public.confirm_pick(helper, target, reply);
  IF (r->>'counted')::boolean OR r->>'reason' <> 'exif_unverified' THEN RAISE EXCEPTION 'Test 6 failed: %', r; END IF;

  -- спроби вичерпано (захист зсунутого місця від перебору)
  IF public.can_confirm_pick(helper, target, sp)->>'code' <> 'attempts_exhausted' THEN RAISE EXCEPTION 'Test 7 failed'; END IF;

  -- третій грибник: ≈ 110 м, EXIF є — зараховано, точка підтверджена, бали
  reply := gen_random_uuid();
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, ai_check)
  VALUES (reply, third, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la + 0.001), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la + 0.002), 4326)::extensions.geography, sp, sp, 'public', 'pending',
          '{"exif":{"verified":true},"location":{"mocked":false}}');
  r := public.confirm_pick(third, target, reply);
  IF (r->>'counted')::boolean IS NOT TRUE OR (r->>'verified')::boolean IS NOT TRUE OR (r->>'confirmations')::int <> 1 THEN
    RAISE EXCEPTION 'Test 8 failed: %', r;
  END IF;
  IF (SELECT verification_status FROM public.mushroom_picks WHERE id = target) <> 'verified' THEN RAISE EXCEPTION 'Test 8b failed'; END IF;
  IF (SELECT rating FROM public.users WHERE id = third) <> 3 OR (SELECT rating FROM public.users WHERE id = author) <> 2 THEN
    RAISE EXCEPTION 'Test 8c failed: rating third=% author=%',
      (SELECT rating FROM public.users WHERE id = third), (SELECT rating FROM public.users WHERE id = author);
  END IF;
  IF public.can_confirm_pick(third, target, sp)->>'code' <> 'already_confirmed' THEN RAISE EXCEPTION 'Test 9 failed'; END IF;

  -- картка: кількість, дата, «ви підтвердили»
  card := public.get_pick_card(third, rid, target);
  IF (card->>'confirmations')::int <> 1 OR card->>'last_confirmed_at' IS NULL OR (card->>'confirmed_by_me')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'Test 10 failed: %', card;
  END IF;

  -- twin_alert: одна відповідь — ще сіра, друга — підтверджена
  reply := gen_random_uuid();
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, ai_check)
  VALUES (reply, third, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.05, la + 0.001), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.05, la + 0.002), 4326)::extensions.geography, sp, sp, 'public', 'pending',
          '{"exif":{"verified":true},"location":{"mocked":false}}');
  r := public.confirm_pick(third, twin, reply);
  IF (r->>'counted')::boolean IS NOT TRUE OR (r->>'verified')::boolean THEN RAISE EXCEPTION 'Test 11 failed: %', r; END IF;
  IF (SELECT verification_status FROM public.mushroom_picks WHERE id = twin) <> 'pending' THEN
    RAISE EXCEPTION 'Test 11b failed: twin_alert verified after one answer';
  END IF;
END $$;

-- взаємні підтвердження: 3 за 30 днів між тими самими двома — далі не зараховується
DO $$
DECLARE
  author CONSTANT UUID := 'c0000001-0000-4000-8000-0000000081c1';
  third  CONSTANT UUID := 'c0000003-0000-4000-8000-0000000081c3';
  sp TEXT := 'boletus_edulis';
  la DOUBLE PRECISION;
  lo DOUBLE PRECISION;
  t UUID;
  reply UUID;
  r JSONB;
BEGIN
  SELECT extensions.ST_Y(geom::extensions.geometry), extensions.ST_X(geom::extensions.geometry) INTO la, lo
  FROM public.mushroom_picks WHERE user_id = author AND NOT twin_alert LIMIT 1;
  -- уже зараховано між author і third: 2 (target і twin). Третя пара — зараховується, четверта — ні.
  FOR i IN 1..2 LOOP
    t := gen_random_uuid();
    INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
    VALUES (t, author, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.1 * i, la), 4326)::extensions.geography,
            extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.1 * i + 0.005, la), 4326)::extensions.geography, sp, sp, 'public', 'pending');
    reply := gen_random_uuid();
    INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, ai_check)
    VALUES (reply, third, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.1 * i, la + 0.001), 4326)::extensions.geography,
            extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.1 * i, la + 0.002), 4326)::extensions.geography, sp, sp, 'public', 'pending',
            '{"exif":{"verified":true},"location":{"mocked":false}}');
    r := public.confirm_pick(third, t, reply);
    IF i = 1 AND (r->>'counted')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Test 12 failed: %', r; END IF;
    IF i = 2 AND ((r->>'counted')::boolean OR r->>'reason' <> 'pair_limit') THEN RAISE EXCEPTION 'Test 12b failed: %', r; END IF;
  END LOOP;
  -- бали тому, хто підтвердив: до 3 на добу (зараховано 3 → 9 балів, не більше)
  IF (SELECT rating FROM public.users WHERE id = third) <> 9 THEN
    RAISE EXCEPTION 'Test 13 failed: rating %', (SELECT rating FROM public.users WHERE id = third);
  END IF;
END $$;

-- B3.8b: підмінене місце (Android mock location) і старий застосунок без ознаки — не зараховуються
DO $$
DECLARE
  author CONSTANT UUID := 'c0000001-0000-4000-8000-0000000081c1';
  helper CONSTANT UUID := 'c0000002-0000-4000-8000-0000000081c2';
  sp TEXT := 'boletus_edulis';
  la DOUBLE PRECISION;
  lo DOUBLE PRECISION;
  t UUID := gen_random_uuid();
  t2 UUID := gen_random_uuid();
  reply UUID;
  r JSONB;
BEGIN
  SELECT extensions.ST_Y(geom::extensions.geometry), extensions.ST_X(geom::extensions.geometry) INTO la, lo
  FROM public.mushroom_picks WHERE user_id = author AND NOT twin_alert LIMIT 1;
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
  VALUES (t, author, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.5, la), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.505, la), 4326)::extensions.geography, sp, sp, 'public', 'pending'),
         (t2, author, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.6, la), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.605, la), 4326)::extensions.geography, sp, sp, 'public', 'pending');

  reply := gen_random_uuid();
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, ai_check)
  VALUES (reply, helper, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.5, la + 0.001), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.5, la + 0.002), 4326)::extensions.geography, sp, sp, 'public', 'pending',
          '{"exif":{"verified":true},"location":{"mocked":true}}');
  r := public.confirm_pick(helper, t, reply);
  IF (r->>'counted')::boolean OR r->>'reason' <> 'mock_location' THEN RAISE EXCEPTION 'Test 15 failed: %', r; END IF;

  reply := gen_random_uuid();
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, ai_check)
  VALUES (reply, helper, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.6, la + 0.001), 4326)::extensions.geography,
          extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.6, la + 0.002), 4326)::extensions.geography, sp, sp, 'public', 'pending',
          '{"exif":{"verified":true}}');
  r := public.confirm_pick(helper, t2, reply);
  IF (r->>'counted')::boolean OR r->>'reason' <> 'location_unknown' THEN RAISE EXCEPTION 'Test 16 failed: %', r; END IF;
  IF (SELECT verification_status FROM public.mushroom_picks WHERE id IN (t, t2) AND verification_status <> 'pending' LIMIT 1) IS NOT NULL THEN
    RAISE EXCEPTION 'Test 16b failed: pick verified without real location';
  END IF;
END $$;

-- клієнт напряму — ні
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.confirm_pick('c0000003-0000-4000-8000-0000000081c3', gen_random_uuid(), gen_random_uuid());
    RAISE EXCEPTION 'Test 14 failed: authenticated called confirm_pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM public.pick_confirmations;
    RAISE EXCEPTION 'Test 14b failed: authenticated read pick_confirmations';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

ROLLBACK;
