-- ============================================================================
-- Тук-тук за ADR-018 (міграція 20261111000000, BACKEND_PLAN B3.0 + B3.1)
--   * видимість лише private / public; «Не знаю» (species_id NULL) — тільки private
--   * чужу public-точку не можна прочитати напряму (точні координати — лише автору)
--   * запис точок — тільки через Edge Functions; гість не створює public
--   * can_create_pick / create_pick — тільки service_role; ліміти й ідемпотентність
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

-- ─── Фікстури ───────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email) VALUES
  ('a1a1a1a1-0000-4000-8000-0000000018a1', 'author18@test.local'),    -- Лісовик (201 бал)
  ('b2b2b2b2-0000-4000-8000-0000000018b2', 'neighbour18@test.local'), -- Мандрівник (0 балів)
  ('d4d4d4d4-0000-4000-8000-0000000018d4', NULL);                     -- гість

UPDATE public.users SET home_region_id = (SELECT min(id) FROM public.regions)
WHERE id IN ('a1a1a1a1-0000-4000-8000-0000000018a1', 'b2b2b2b2-0000-4000-8000-0000000018b2');
UPDATE public.users SET rating = 201 WHERE id = 'a1a1a1a1-0000-4000-8000-0000000018a1';

INSERT INTO public.mushroom_picks (id, user_id, geom, mushroom_type, pick_type, species_id, display_geom) VALUES
  ('00000000-0000-4000-8000-0000000018e1', 'a1a1a1a1-0000-4000-8000-0000000018a1',
   'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private', NULL, NULL),
  ('00000000-0000-4000-8000-0000000018e2', 'a1a1a1a1-0000-4000-8000-0000000018a1',
   'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public', 'boletus_edulis', 'SRID=4326;POINT(30.504 50.403)');

-- ─── 1. Обмеження таблиці ──────────────────────────────────────────────────
DO $$
BEGIN
  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type)
    VALUES ('a1a1a1a1-0000-4000-8000-0000000018a1', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'friends');
    RAISE EXCEPTION 'Test 1a failed: pick_type = friends accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- «Не знаю» (species_id NULL) не може бути публічною точкою
  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, display_geom)
    VALUES ('a1a1a1a1-0000-4000-8000-0000000018a1', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'public',
            'SRID=4326;POINT(30.504 50.403)');
    RAISE EXCEPTION 'Test 1b failed: public pick without species_id accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- публічна точка без зсунутого місця неможлива
  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, species_id)
    VALUES ('a1a1a1a1-0000-4000-8000-0000000018a1', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public',
            'boletus_edulis');
    RAISE EXCEPTION 'Test 1c failed: public pick without display_geom accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- вид має існувати в довіднику
  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, species_id)
    VALUES ('a1a1a1a1-0000-4000-8000-0000000018a1', 'SRID=4326;POINT(30.5 50.4)', 'no_such', 'private', 'no_such_species');
    RAISE EXCEPTION 'Test 1d failed: unknown species_id accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- опис — до 500 символів
  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, description)
    VALUES ('a1a1a1a1-0000-4000-8000-0000000018a1', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private', repeat('я', 501));
    RAISE EXCEPTION 'Test 1e failed: description of 501 characters accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- client_id унікальний у межах користувача
  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, client_id, description)
  VALUES ('b2b2b2b2-0000-4000-8000-0000000018b2', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private',
          'c1c1c1c1-0000-4000-8000-000000000001', repeat('я', 500));
  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, client_id)
    VALUES ('b2b2b2b2-0000-4000-8000-0000000018b2', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private',
            'c1c1c1c1-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'Test 1f failed: duplicate (user_id, client_id) accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  DELETE FROM public.mushroom_picks WHERE user_id = 'b2b2b2b2-0000-4000-8000-0000000018b2';
END $$;

-- ─── 2. Сусід по області не читає чужу public-точку напряму ────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'b2b2b2b2-0000-4000-8000-0000000018b2', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"b2b2b2b2-0000-4000-8000-0000000018b2","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.mushroom_picks;
  IF n <> 0 THEN
    RAISE EXCEPTION 'Test 2 failed: neighbour reads % picks directly (exact coordinates leak), expected 0', n;
  END IF;

  -- і не може змінити чи видалити чужу точку
  BEGIN
    UPDATE public.mushroom_picks SET description = 'x' WHERE id = '00000000-0000-4000-8000-0000000018e2';
    RAISE EXCEPTION 'Test 2b failed: client updated picks directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    DELETE FROM public.mushroom_picks WHERE id = '00000000-0000-4000-8000-0000000018e2';
    RAISE EXCEPTION 'Test 2c failed: client deleted picks directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  -- функції лімітів і створення — не для клієнтів
  BEGIN
    PERFORM * FROM public.can_create_pick('b2b2b2b2-0000-4000-8000-0000000018b2', 'private');
    RAISE EXCEPTION 'Test 2d failed: authenticated can call can_create_pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.create_pick(
      gen_random_uuid(), 'b2b2b2b2-0000-4000-8000-0000000018b2', gen_random_uuid(),
      50.4, 30.5, 'x/y.jpg', 'private');
    RAISE EXCEPTION 'Test 2e failed: authenticated can call create_pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

-- ─── 3. Автор бачить свої точки (з точними координатами), але пише лише через API ─
SELECT set_config('request.jwt.claim.sub', 'a1a1a1a1-0000-4000-8000-0000000018a1', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"a1a1a1a1-0000-4000-8000-0000000018a1","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.mushroom_picks WHERE geom IS NOT NULL;
  IF n <> 2 THEN RAISE EXCEPTION 'Test 3 failed: author sees % own picks, expected 2', n; END IF;

  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type)
    VALUES ('a1a1a1a1-0000-4000-8000-0000000018a1', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private');
    RAISE EXCEPTION 'Test 3b failed: registered user inserted a pick directly (limits bypass)';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    UPDATE public.mushroom_picks SET verification_status = 'verified'
    WHERE id = '00000000-0000-4000-8000-0000000018e2';
    RAISE EXCEPTION 'Test 3c failed: author verified own pick directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

-- ─── 4. Гість не вставляє public ───────────────────────────────────────────
SELECT set_config('request.jwt.claim.sub', 'd4d4d4d4-0000-4000-8000-0000000018d4', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"d4d4d4d4-0000-4000-8000-0000000018d4","role":"authenticated","is_anonymous":true}', true);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, species_id, display_geom)
    VALUES ('d4d4d4d4-0000-4000-8000-0000000018d4', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public',
            'boletus_edulis', 'SRID=4326;POINT(30.504 50.403)');
    RAISE EXCEPTION 'Test 4 failed: guest created a public pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

-- Другий рубіж: навіть якщо право INSERT колись повернуть, RLS не дасть гостю public.
RESET ROLE;
GRANT INSERT ON public.mushroom_picks TO authenticated;
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type)
  VALUES ('d4d4d4d4-0000-4000-8000-0000000018d4', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private');

  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, species_id, display_geom)
    VALUES ('d4d4d4d4-0000-4000-8000-0000000018d4', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public',
            'boletus_edulis', 'SRID=4326;POINT(30.504 50.403)');
    RAISE EXCEPTION 'Test 4b failed: RLS let a guest create a public pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;
REVOKE INSERT ON public.mushroom_picks FROM authenticated;
DELETE FROM public.mushroom_picks WHERE user_id = 'd4d4d4d4-0000-4000-8000-0000000018d4';

-- ─── 5. Ліміти can_create_pick (service_role) ──────────────────────────────
-- Не рахуються: видалена точка і точка, старша за 24 год.
INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, deleted_at)
VALUES ('b2b2b2b2-0000-4000-8000-0000000018b2', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private', now());
INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, created_at)
VALUES ('b2b2b2b2-0000-4000-8000-0000000018b2', 'SRID=4326;POINT(30.5 50.4)', 'unknown', 'private',
        now() - INTERVAL '25 hours');

SET LOCAL ROLE service_role;

DO $$
DECLARE r RECORD; res JSONB; first_id UUID; n INT; i INT;
BEGIN
  -- Мандрівник (0 балів): public — ні, private — так
  SELECT * INTO r FROM public.can_create_pick('b2b2b2b2-0000-4000-8000-0000000018b2', 'public');
  IF r.allowed OR r.code <> 'level_required' OR r.message IS NULL THEN
    RAISE EXCEPTION 'Test 5a failed: expected level_required, got (%, %)', r.allowed, r.code;
  END IF;
  SELECT * INTO r FROM public.can_create_pick('b2b2b2b2-0000-4000-8000-0000000018b2', 'private');
  IF NOT r.allowed THEN RAISE EXCEPTION 'Test 5b failed: private pick not allowed (%, %)', r.code, r.message; END IF;

  SELECT * INTO r FROM public.can_create_pick('b2b2b2b2-0000-4000-8000-0000000018b2', 'friends');
  IF r.allowed OR r.code <> 'validation_error' THEN
    RAISE EXCEPTION 'Test 5c failed: unknown visibility accepted (%, %)', r.allowed, r.code;
  END IF;

  -- create_pick: приватна точка «Не знаю» — pending, без display_geom
  res := public.create_pick(
    '00000000-0000-4000-8000-000000001801', 'b2b2b2b2-0000-4000-8000-0000000018b2',
    'c1c1c1c1-0000-4000-8000-000000000101', 50.4, 30.5, 'picks/00000000-0000-4000-8000-000000001801.jpg',
    'private', NULL, 'Під сосною', '{"match": false}'::jsonb, false, now(), 50.403, 30.504);
  IF NOT (res->>'allowed')::boolean OR NOT (res->>'created')::boolean
     OR res->'pick'->>'verification_status' <> 'pending' THEN
    RAISE EXCEPTION 'Test 5d failed: create_pick returned %', res;
  END IF;
  PERFORM 1 FROM public.mushroom_picks
  WHERE id = '00000000-0000-4000-8000-000000001801' AND display_geom IS NULL AND species_id IS NULL
    AND mushroom_type = 'unknown' AND verification_status = 'pending' AND pick_type = 'private'
    AND extensions.ST_Y(geom::extensions.geometry) = 50.4 AND extensions.ST_X(geom::extensions.geometry) = 30.5;
  IF NOT FOUND THEN RAISE EXCEPTION 'Test 5e failed: private pick stored incorrectly'; END IF;

  -- повтор із тим самим client_id → та сама точка, без дубля
  res := public.create_pick(
    '00000000-0000-4000-8000-000000001899', 'b2b2b2b2-0000-4000-8000-0000000018b2',
    'c1c1c1c1-0000-4000-8000-000000000101', 50.4, 30.5, 'picks/other.jpg', 'private');
  IF (res->>'created')::boolean OR res->'pick'->>'id' <> '00000000-0000-4000-8000-000000001801' THEN
    RAISE EXCEPTION 'Test 5f failed: repeated client_id returned %', res;
  END IF;
  SELECT count(*) INTO n FROM public.mushroom_picks
  WHERE user_id = 'b2b2b2b2-0000-4000-8000-0000000018b2' AND client_id = 'c1c1c1c1-0000-4000-8000-000000000101';
  IF n <> 1 THEN RAISE EXCEPTION 'Test 5g failed: % rows for one client_id', n; END IF;

  -- ще 4 приватні → разом 5 за добу; шоста — daily_limit_reached, рядок не створюється
  FOR i IN 2..5 LOOP
    res := public.create_pick(
      gen_random_uuid(), 'b2b2b2b2-0000-4000-8000-0000000018b2', gen_random_uuid(),
      50.4, 30.5, 'picks/x.jpg', 'private');
    IF NOT (res->>'created')::boolean THEN RAISE EXCEPTION 'Test 5h failed: pick % not created: %', i, res; END IF;
  END LOOP;
  res := public.create_pick(
    gen_random_uuid(), 'b2b2b2b2-0000-4000-8000-0000000018b2', gen_random_uuid(),
    50.4, 30.5, 'picks/x.jpg', 'private');
  IF (res->>'allowed')::boolean OR res->>'code' <> 'daily_limit_reached' THEN
    RAISE EXCEPTION 'Test 5i failed: 6th private pick returned %', res;
  END IF;
  SELECT * INTO r FROM public.can_create_pick('b2b2b2b2-0000-4000-8000-0000000018b2', 'private');
  IF r.allowed OR r.code <> 'daily_limit_reached' THEN
    RAISE EXCEPTION 'Test 5j failed: expected daily_limit_reached, got (%, %)', r.allowed, r.code;
  END IF;
  -- повтор уже створеної точки дозволений і після вичерпання ліміту
  res := public.create_pick(
    gen_random_uuid(), 'b2b2b2b2-0000-4000-8000-0000000018b2',
    'c1c1c1c1-0000-4000-8000-000000000101', 50.4, 30.5, 'picks/x.jpg', 'private');
  IF NOT (res->>'allowed')::boolean OR (res->>'created')::boolean THEN
    RAISE EXCEPTION 'Test 5k failed: retry after limit returned %', res;
  END IF;

  -- Лісовик (201 бал): public дозволено; точка — pending і з display_geom
  SELECT * INTO r FROM public.can_create_pick('a1a1a1a1-0000-4000-8000-0000000018a1', 'public');
  IF NOT r.allowed THEN RAISE EXCEPTION 'Test 5l failed: Lisovyk cannot publish (%, %)', r.code, r.message; END IF;

  res := public.create_pick(
    '00000000-0000-4000-8000-000000001802', 'a1a1a1a1-0000-4000-8000-0000000018a1',
    'c1c1c1c1-0000-4000-8000-000000000201', 50.4, 30.5, 'picks/00000000-0000-4000-8000-000000001802.jpg',
    'public', 'boletus_edulis', NULL, NULL, true, now(), 50.403, 30.504);
  IF NOT (res->>'created')::boolean THEN RAISE EXCEPTION 'Test 5m failed: public pick not created: %', res; END IF;
  PERFORM 1 FROM public.mushroom_picks
  WHERE id = '00000000-0000-4000-8000-000000001802' AND verification_status = 'pending' AND twin_alert
    AND mushroom_type = 'boletus_edulis' AND species_id = 'boletus_edulis'
    AND extensions.ST_Y(display_geom::extensions.geometry) = 50.403
    AND extensions.ST_X(display_geom::extensions.geometry) = 30.504;
  IF NOT FOUND THEN RAISE EXCEPTION 'Test 5n failed: public pick stored incorrectly'; END IF;

  -- у Лісовика вже 2 публічні (фікстура + щойно створена): ще 3 → ліміт
  FOR i IN 3..5 LOOP
    res := public.create_pick(
      gen_random_uuid(), 'a1a1a1a1-0000-4000-8000-0000000018a1', gen_random_uuid(),
      50.4, 30.5, 'picks/x.jpg', 'public', 'boletus_edulis', NULL, NULL, false, now(), 50.403, 30.504);
    IF NOT (res->>'created')::boolean THEN RAISE EXCEPTION 'Test 5o failed: public pick % not created: %', i, res; END IF;
  END LOOP;
  SELECT * INTO r FROM public.can_create_pick('a1a1a1a1-0000-4000-8000-0000000018a1', 'public');
  IF r.allowed OR r.code <> 'daily_limit_reached' THEN
    RAISE EXCEPTION 'Test 5p failed: expected public daily_limit_reached, got (%, %)', r.allowed, r.code;
  END IF;
  -- окремі лічильники: приватні для нього ще доступні (ADR-011)
  SELECT * INTO r FROM public.can_create_pick('a1a1a1a1-0000-4000-8000-0000000018a1', 'private');
  IF NOT r.allowed THEN RAISE EXCEPTION 'Test 5q failed: private counter shared with public'; END IF;

  RAISE NOTICE '✅ rls_picks_adr018: all checks passed';
END $$;

ROLLBACK;
