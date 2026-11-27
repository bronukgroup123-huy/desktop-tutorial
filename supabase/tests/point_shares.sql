-- ============================================================================
-- B9.4a: поділитися приватною точкою з другом (міграція 20261128130000; ADR-021 §21.5)
--   * лише своєю приватною точкою і лише з друзями; публічну — ні; повтор не дублює;
--   * друг бачить точку на карті й у картці з точним місцем і «від @нік», інші — ні;
--   * автор бачить, з ким поділився; друг переслати далі не може;
--   * відкликати — одному чи всім; точка стала публічною / видалена — поширення не діє;
--   * кінець дружби відкликає поширення, повторна дружба доступ не повертає;
--   * не більше 20 отримувачів; RLS: читають лише власник і отримувач; функції — лише service_role.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('e5000001-0000-4000-8000-0000000095e1', 'owner@test.local'),
  ('e5000002-0000-4000-8000-0000000095e2', 'friend@test.local'),
  ('e5000003-0000-4000-8000-0000000095e3', 'stranger@test.local'),
  ('e5000004-0000-4000-8000-0000000095e4', 'friend2@test.local');
INSERT INTO auth.users (id, email)
  SELECT ('e5100000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'many' || g || '@test.local'
  FROM generate_series(1, 20) g;
UPDATE public.users SET handle = 'Олена', handle_key = 'олена' WHERE id = 'e5000001-0000-4000-8000-0000000095e1';

-- друзі власника: friend, friend2 і ще 20; stranger — ні
INSERT INTO public.friendships (user_a, user_b, status, requested_by)
  SELECT LEAST(o, f), GREATEST(o, f), 'accepted', o
  FROM (SELECT 'e5000001-0000-4000-8000-0000000095e1'::uuid AS o) a,
       (SELECT id AS f FROM public.users
        WHERE id IN ('e5000002-0000-4000-8000-0000000095e2', 'e5000004-0000-4000-8000-0000000095e4')
           OR id::text LIKE 'e5100000-%') b;

SET LOCAL ROLE service_role;

DO $$
DECLARE
  o  CONSTANT UUID := 'e5000001-0000-4000-8000-0000000095e1';
  f  CONSTANT UUID := 'e5000002-0000-4000-8000-0000000095e2';
  st CONSTANT UUID := 'e5000003-0000-4000-8000-0000000095e3';
  f2 CONSTANT UUID := 'e5000004-0000-4000-8000-0000000095e4';
  rid INT; la DOUBLE PRECISION; lo DOUBLE PRECISION;
  priv UUID := gen_random_uuid();
  pub  UUID := gen_random_uuid();
  r JSONB; card JSONB; m JSONB; many UUID[];
BEGIN
  SELECT r2.id, extensions.ST_Y(extensions.ST_PointOnSurface(r2.polygon::extensions.geometry)),
         extensions.ST_X(extensions.ST_PointOnSurface(r2.polygon::extensions.geometry))
    INTO rid, la, lo FROM public.regions r2 ORDER BY r2.id LIMIT 1;
  INSERT INTO public.mushroom_picks (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type,
                                     verification_status, description)
  VALUES
    (priv, o, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la), 4326)::extensions.geography,
     extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.004, la), 4326)::extensions.geography,
     'boletus_edulis', 'boletus_edulis', 'private', 'pending', 'біля старої берези'),
    (pub, o, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.01, la), 4326)::extensions.geography,
     extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.014, la), 4326)::extensions.geography,
     'boletus_edulis', 'boletus_edulis', 'public', 'pending', NULL);

  -- 1. публічну — ні; з чужою людиною — ні; чужою точкою — ні
  r := public.share_pick(o, pub, ARRAY[f]);
  IF r->>'code' <> 'not_private' THEN RAISE EXCEPTION 'Test 1a failed: %', r; END IF;
  r := public.share_pick(o, priv, ARRAY[f, st]);
  IF r->>'code' <> 'not_friend' OR EXISTS (SELECT 1 FROM public.point_shares) THEN RAISE EXCEPTION 'Test 1b failed: %', r; END IF;
  r := public.share_pick(f, priv, ARRAY[o]);
  IF r->>'code' <> 'pick_not_found' THEN RAISE EXCEPTION 'Test 1c failed: %', r; END IF;
  r := public.share_pick(o, priv, ARRAY[]::uuid[]);
  IF r->>'code' <> 'validation_error' THEN RAISE EXCEPTION 'Test 1d failed: %', r; END IF;

  -- 2. поділитися з другом; повтор не дублює
  r := public.share_pick(o, priv, ARRAY[f, f]);
  IF r->>'ok' <> 'true' OR (r->>'shared')::int <> 1 OR (r->>'recipients')::int <> 1 THEN RAISE EXCEPTION 'Test 2a failed: %', r; END IF;
  r := public.share_pick(o, priv, ARRAY[f]);
  IF (r->>'shared')::int <> 0 OR (r->>'recipients')::int <> 1 THEN RAISE EXCEPTION 'Test 2b failed: %', r; END IF;

  -- 3. друг бачить точне місце й «від Олена» — на карті, у картці, у списку
  m := public.get_picks_map(f, rid, NULL, NULL, NULL, NULL, false, 500);
  SELECT x INTO m FROM jsonb_array_elements(m) x WHERE x->>'id' = priv::text;
  IF m IS NULL OR m->>'shared_from' <> 'Олена' OR (m->>'is_exact')::boolean IS NOT TRUE
     OR abs((m->>'lng')::float8 - lo) > 1e-9 THEN
    RAISE EXCEPTION 'Test 3a failed: %', m;
  END IF;
  card := public.get_pick_card(f, rid, priv);
  IF card IS NULL OR card->>'shared_from' <> 'Олена' OR card->>'description' <> 'біля старої берези'
     OR abs((card->>'lng')::float8 - lo) > 1e-9 OR card ? 'shared_with' AND card->'shared_with' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'Test 3b failed: %', card;
  END IF;
  -- картка поширеної точки не прив'язана до області отримувача
  IF public.get_pick_card(f, rid + 1000, priv) IS NULL THEN RAISE EXCEPTION 'Test 3c failed: other region'; END IF;
  IF jsonb_array_length(public.picks_shared_with_me(f)) <> 1
     OR public.picks_shared_with_me(f)->0->>'from_handle' <> 'Олена' THEN
    RAISE EXCEPTION 'Test 3d failed: %', public.picks_shared_with_me(f);
  END IF;

  -- 4. інші не бачать
  IF public.get_pick_card(st, rid, priv) IS NOT NULL OR public.get_pick_card(f2, rid, priv) IS NOT NULL THEN
    RAISE EXCEPTION 'Test 4a failed';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.get_picks_map(f2, rid, NULL, NULL, NULL, NULL, false, 500)) x
             WHERE x->>'id' = priv::text) THEN
    RAISE EXCEPTION 'Test 4b failed';
  END IF;

  -- 5. автор бачить, з ким поділився
  card := public.get_pick_card(o, rid, priv);
  IF jsonb_array_length(card->'shared_with') <> 1 OR card->'shared_with'->0->>'user_id' <> f::text THEN
    RAISE EXCEPTION 'Test 5 failed: %', card->'shared_with';
  END IF;

  -- 6. стала публічною — поширення не діє (друг бачить як усі: зі зсувом, без «від»)
  UPDATE public.mushroom_picks SET pick_type = 'public' WHERE id = priv;
  card := public.get_pick_card(f, rid, priv);
  IF card->>'shared_from' IS NOT NULL OR (card->>'is_exact')::boolean THEN RAISE EXCEPTION 'Test 6a failed: %', card; END IF;
  IF jsonb_array_length(public.picks_shared_with_me(f)) <> 0 THEN RAISE EXCEPTION 'Test 6b failed'; END IF;
  UPDATE public.mushroom_picks SET pick_type = 'private' WHERE id = priv;

  -- 7. відкликати одному
  r := public.share_pick(o, priv, ARRAY[f2]);
  r := public.revoke_pick_share(o, priv, f);
  IF (r->>'revoked')::int <> 1 OR public.get_pick_card(f, rid, priv) IS NOT NULL
     OR public.get_pick_card(f2, rid, priv) IS NULL THEN
    RAISE EXCEPTION 'Test 7 failed: %', r;
  END IF;
  -- чужий не відкличе
  r := public.revoke_pick_share(f2, priv, NULL);
  IF r->>'code' <> 'pick_not_found' OR public.get_pick_card(f2, rid, priv) IS NULL THEN RAISE EXCEPTION 'Test 7b failed'; END IF;

  -- 8. кінець дружби — відкликано; повторна дружба доступ не повертає
  UPDATE public.friendships SET status = 'declined' WHERE user_a = LEAST(o, f2) AND user_b = GREATEST(o, f2);
  IF public.get_pick_card(f2, rid, priv) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.point_shares WHERE recipient_id = f2 AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'Test 8a failed';
  END IF;
  UPDATE public.friendships SET status = 'accepted' WHERE user_a = LEAST(o, f2) AND user_b = GREATEST(o, f2);
  IF public.get_pick_card(f2, rid, priv) IS NOT NULL THEN RAISE EXCEPTION 'Test 8b failed'; END IF;

  -- 9. ліміт 20 отримувачів
  SELECT array_agg(id) INTO many FROM public.users WHERE id::text LIKE 'e5100000-%';
  r := public.share_pick(o, priv, many[1:20]);
  IF r->>'ok' <> 'true' OR (r->>'recipients')::int <> 20 THEN RAISE EXCEPTION 'Test 9a failed: %', r; END IF;
  r := public.share_pick(o, priv, ARRAY[f]);
  IF r->>'code' <> 'share_limit' THEN RAISE EXCEPTION 'Test 9b failed: %', r; END IF;
  r := public.revoke_pick_share(o, priv, NULL);
  IF (r->>'revoked')::int <> 20 THEN RAISE EXCEPTION 'Test 9c failed: %', r; END IF;

  -- 10. видалена точка — не видно
  r := public.share_pick(o, priv, ARRAY[f]);
  UPDATE public.mushroom_picks SET deleted_at = now() WHERE id = priv;
  IF public.get_pick_card(f, rid, priv) IS NOT NULL OR jsonb_array_length(public.picks_shared_with_me(f)) <> 0 THEN
    RAISE EXCEPTION 'Test 10 failed';
  END IF;
  UPDATE public.mushroom_picks SET deleted_at = NULL WHERE id = priv;

  RAISE NOTICE 'OK поширення точок: доступ, відкликання, дружба, ліміт';
END $$;

-- 11. RLS: таблицю читають лише власник і отримувач; писати й викликати функції клієнт не може
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"e5000002-0000-4000-8000-0000000095e2","is_anonymous":false}', true);
DO $$
BEGIN
  IF (SELECT count(*) FROM public.point_shares WHERE revoked_at IS NULL) <> 1
     OR EXISTS (SELECT 1 FROM public.point_shares WHERE 'e5000002-0000-4000-8000-0000000095e2' NOT IN (owner_id, recipient_id)) THEN
    RAISE EXCEPTION 'Test 11a failed: recipient sees %', (SELECT count(*) FROM public.point_shares);
  END IF;
END $$;
SELECT set_config('request.jwt.claims', '{"sub":"e5000003-0000-4000-8000-0000000095e3","is_anonymous":false}', true);
DO $$
BEGIN
  IF (SELECT count(*) FROM public.point_shares) <> 0 THEN RAISE EXCEPTION 'Test 11b failed: stranger sees shares'; END IF;
  BEGIN
    INSERT INTO public.point_shares (pick_id, owner_id, recipient_id)
    SELECT pick_id, owner_id, 'e5000003-0000-4000-8000-0000000095e3' FROM public.point_shares LIMIT 1;
    RAISE EXCEPTION 'Test 11c failed: client insert allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.share_pick('e5000003-0000-4000-8000-0000000095e3', gen_random_uuid(), ARRAY[]::uuid[]);
    RAISE EXCEPTION 'Test 11d failed: client can call share_pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK поширення точок: RLS і права';
END $$;
RESET ROLE;

ROLLBACK;
