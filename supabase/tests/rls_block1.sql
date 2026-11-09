-- ============================================================================
-- RLS / доступи для змін робочого блоку 1 (міграції 20261109*)
--   * приватні та «дружні» тук-туки не видно сусідам по області (20261109120500)
--   * гість (is_anonymous) — тільки private точки, без сесій Наглядача (20261109120300, ADR-001)
--   * user_consents — читання своїх, запис лише service_role (20261109120400)
--   * нові RPC недоступні клієнтам напряму (20261109120100, 20261109120200)
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

-- ─── Фікстури ───────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email) VALUES
  ('a1a1a1a1-0000-4000-8000-0000000000a1', 'author@test.local'),
  ('b2b2b2b2-0000-4000-8000-0000000000b2', 'neighbour@test.local'),
  ('c3c3c3c3-0000-4000-8000-0000000000c3', 'friend@test.local'),
  ('d4d4d4d4-0000-4000-8000-0000000000d4', NULL); -- гість

-- автор і сусід — в одній області
UPDATE public.users SET home_region_id = (SELECT min(id) FROM public.regions)
WHERE id IN ('a1a1a1a1-0000-4000-8000-0000000000a1', 'b2b2b2b2-0000-4000-8000-0000000000b2');

INSERT INTO public.mushroom_picks (id, user_id, geom, mushroom_type, pick_type, shared_with) VALUES
  ('00000000-0000-4000-8000-0000000000e1', 'a1a1a1a1-0000-4000-8000-0000000000a1',
   'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'private', '{}'),
  ('00000000-0000-4000-8000-0000000000e2', 'a1a1a1a1-0000-4000-8000-0000000000a1',
   'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'friends', '{c3c3c3c3-0000-4000-8000-0000000000c3}'),
  ('00000000-0000-4000-8000-0000000000e3', 'a1a1a1a1-0000-4000-8000-0000000000a1',
   'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public', '{}');

INSERT INTO public.user_consents (user_id, doc, version) VALUES
  ('a1a1a1a1-0000-4000-8000-0000000000a1', 'eula', '2026-11');

-- ─── 1. Сусід по області бачить тільки public ──────────────────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'b2b2b2b2-0000-4000-8000-0000000000b2', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"b2b2b2b2-0000-4000-8000-0000000000b2","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE types TEXT;
BEGIN
  SELECT string_agg(pick_type, ',' ORDER BY pick_type) INTO types
  FROM public.mushroom_picks WHERE user_id = 'a1a1a1a1-0000-4000-8000-0000000000a1';
  IF types IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'Test 1 failed: neighbour sees pick types [%], expected [public]', types;
  END IF;

  -- згоди автора сусіду недоступні
  IF EXISTS (SELECT 1 FROM public.user_consents) THEN
    RAISE EXCEPTION 'Test 1b failed: neighbour sees foreign consents';
  END IF;
END $$;

-- ─── 2. Друг бачить friends (shared_with) і public, але не private ─────────
SELECT set_config('request.jwt.claim.sub', 'c3c3c3c3-0000-4000-8000-0000000000c3', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"c3c3c3c3-0000-4000-8000-0000000000c3","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE types TEXT;
BEGIN
  SELECT string_agg(pick_type, ',' ORDER BY pick_type) INTO types
  FROM public.mushroom_picks WHERE user_id = 'a1a1a1a1-0000-4000-8000-0000000000a1';
  IF types IS DISTINCT FROM 'friends,public' THEN
    RAISE EXCEPTION 'Test 2 failed: friend sees [%], expected [friends,public]', types;
  END IF;
END $$;

-- ─── 3. Автор бачить усе своє; згоди — свої, але не може їх вставити ───────
SELECT set_config('request.jwt.claim.sub', 'a1a1a1a1-0000-4000-8000-0000000000a1', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"a1a1a1a1-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.mushroom_picks WHERE user_id = 'a1a1a1a1-0000-4000-8000-0000000000a1';
  IF n <> 3 THEN RAISE EXCEPTION 'Test 3 failed: author sees % own picks, expected 3', n; END IF;

  SELECT count(*) INTO n FROM public.user_consents;
  IF n <> 1 THEN RAISE EXCEPTION 'Test 3b failed: author sees % consents, expected 1', n; END IF;

  BEGIN
    INSERT INTO public.user_consents (user_id, doc, version)
    VALUES ('a1a1a1a1-0000-4000-8000-0000000000a1', 'privacy', '2026-11');
    RAISE EXCEPTION 'Test 3c failed: client inserted a consent directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  -- зареєстрований користувач може створити public-точку
  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type)
  VALUES ('a1a1a1a1-0000-4000-8000-0000000000a1', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public');

  IF NOT public.is_registered() THEN RAISE EXCEPTION 'Test 3d failed: registered user not recognised'; END IF;
END $$;

-- ─── 4. Гість: private — так; public/friends і сесії Наглядача — ні ────────
SELECT set_config('request.jwt.claim.sub', 'd4d4d4d4-0000-4000-8000-0000000000d4', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"d4d4d4d4-0000-4000-8000-0000000000d4","role":"authenticated","is_anonymous":true}', true);

DO $$
BEGIN
  IF public.is_registered() THEN RAISE EXCEPTION 'Test 4 failed: guest treated as registered'; END IF;

  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type)
  VALUES ('d4d4d4d4-0000-4000-8000-0000000000d4', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'private');

  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type)
    VALUES ('d4d4d4d4-0000-4000-8000-0000000000d4', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public');
    RAISE EXCEPTION 'Test 4b failed: guest created a public pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type)
    VALUES ('d4d4d4d4-0000-4000-8000-0000000000d4', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'friends');
    RAISE EXCEPTION 'Test 4c failed: guest created a friends pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    UPDATE public.mushroom_picks SET pick_type = 'public'
    WHERE user_id = 'd4d4d4d4-0000-4000-8000-0000000000d4';
    RAISE EXCEPTION 'Test 4d failed: guest made a pick public';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.guardian_sessions (user_id, expected_return, original_return)
    VALUES ('d4d4d4d4-0000-4000-8000-0000000000d4', now() + interval '1 hour', now() + interval '1 hour');
    RAISE EXCEPTION 'Test 4e failed: guest created a guardian session';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

-- ─── 5. Нові RPC недоступні клієнтам напряму (тільки service_role) ─────────
DO $$
BEGIN
  BEGIN
    PERFORM public.get_region_geometry('kyivska', 0.005);
    RAISE EXCEPTION 'Test 5 failed: authenticated can call get_region_geometry';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.get_forest_zones_geojson_region(1, NULL, NULL, NULL, NULL, 10, 0);
    RAISE EXCEPTION 'Test 5b failed: authenticated can call get_forest_zones_geojson_region';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;

-- ─── 6. RPC працюють для service_role ──────────────────────────────────────
SET LOCAL ROLE service_role;
DO $$
DECLARE g JSONB; slug TEXT;
BEGIN
  SELECT r.slug INTO slug FROM public.regions r WHERE r.slug IS NOT NULL ORDER BY r.id LIMIT 1;
  g := public.get_region_geometry(slug, 0.01);
  IF g IS NULL OR jsonb_array_length(g->'bbox') <> 4 OR g->'geometry' IS NULL THEN
    RAISE EXCEPTION 'Test 6 failed: get_region_geometry(%) returned %', slug, left(g::text, 200);
  END IF;

  g := public.get_forest_zones_geojson_region((SELECT min(id) FROM public.regions), NULL, NULL, NULL, NULL, 10, 0.001);
  IF g->>'type' <> 'FeatureCollection' THEN
    RAISE EXCEPTION 'Test 6b failed: forest zones RPC returned %', left(g::text, 200);
  END IF;

  RAISE NOTICE '✅ rls_block1: all checks passed';
END $$;

ROLLBACK;
