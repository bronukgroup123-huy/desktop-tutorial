-- ============================================================================
-- PROD-001a: журнал балів, рівні, бал за EXIF, ліміти ADR-019 §19.10 (міграція 20261125100000).
-- Самодостатній: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================
BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('aaaa0001-0000-4000-8000-00000000e001', 'walker@test.local'),   -- Мандрівник
  ('aaaa0002-0000-4000-8000-00000000e002', 'forester@test.local'), -- Лісовик
  ('aaaa0003-0000-4000-8000-00000000e003', 'keeper@test.local');   -- Хранитель лісу
UPDATE public.users SET home_region_id = (SELECT min(id) FROM public.regions)
WHERE id::text LIKE 'aaaa000%';

-- ─── 1. Межі рівнів (ті самі, що levelOf у profile-rules.ts) ────────────────
DO $$
DECLARE
  cases CONSTANT text[][] := ARRAY[
    ['0','f','traveler'], ['50','f','traveler'], ['51','f','tracker'], ['51','t','expert'],
    ['200','f','tracker'], ['200','t','expert'], ['201','f','forester'], ['201','t','forester'],
    ['500','f','forester'], ['501','f','keeper'], ['1000','f','keeper'], ['1001','f','keeper'],
    ['1001','t','master']];
  c text[];
BEGIN
  FOREACH c SLICE 1 IN ARRAY cases LOOP
    IF public.level_of(c[1]::int, c[2]::boolean) <> c[3] THEN
      RAISE EXCEPTION 'FAIL level_of(%, %) = %, expected %', c[1], c[2], public.level_of(c[1]::int, c[2]::boolean), c[3];
    END IF;
  END LOOP;
  RAISE NOTICE 'OK level_of: межі ADR-013';
END $$;

-- ─── 2. Журнал → users.rating; клієнт не пише в журнал ─────────────────────
SET LOCAL ROLE service_role;
INSERT INTO public.rating_events (user_id, delta, reason) VALUES ('aaaa0002-0000-4000-8000-00000000e002', 1, 'pick_exif');
RESET ROLE;
DO $$
BEGIN
  IF (SELECT rating FROM public.users WHERE id = 'aaaa0002-0000-4000-8000-00000000e002') <> 1 THEN
    RAISE EXCEPTION 'FAIL rating ≠ сумі журналу';
  END IF;
  RAISE NOTICE 'OK rating = сума журналу';
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"aaaa0001-0000-4000-8000-00000000e001","role":"authenticated"}', true);
DO $$
BEGIN
  BEGIN
    INSERT INTO public.rating_events (user_id, delta, reason) VALUES ('aaaa0001-0000-4000-8000-00000000e001', 500, 'pick_exif');
    RAISE EXCEPTION 'FAIL користувач записав собі бали';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  -- читає лише свої події
  IF EXISTS (SELECT 1 FROM public.rating_events WHERE user_id <> 'aaaa0001-0000-4000-8000-00000000e001') THEN
    RAISE EXCEPTION 'FAIL видно чужі бали';
  END IF;
  RAISE NOTICE 'OK журнал: запис — лише сервер, читання — свої';
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', '', true);

-- ─── 3. +1 за приватну точку з EXIF, не більше 5 за 7 днів ─────────────────
SET LOCAL ROLE service_role;
DO $$
DECLARE res jsonb; i int; r int;
BEGIN
  -- без EXIF і публічна — без балів
  res := public.create_pick(gen_random_uuid(), 'aaaa0001-0000-4000-8000-00000000e001', gen_random_uuid(),
    50.4, 30.5, 'picks/a.jpg', 'private', NULL, NULL, '{"exif":{"verified":false}}'::jsonb);
  IF (SELECT rating FROM public.users WHERE id = 'aaaa0001-0000-4000-8000-00000000e001') <> 0 THEN
    RAISE EXCEPTION 'FAIL бал без EXIF';
  END IF;
  -- 4 приватні з EXIF (разом 5 точок) → +4
  FOR i IN 1..4 LOOP
    res := public.create_pick(gen_random_uuid(), 'aaaa0001-0000-4000-8000-00000000e001', gen_random_uuid(),
      50.4, 30.5, 'picks/a.jpg', 'private', NULL, NULL, '{"exif":{"verified":true}}'::jsonb);
    IF NOT (res->>'created')::boolean THEN RAISE EXCEPTION 'FAIL точка % не створена: %', i, res; END IF;
  END LOOP;
  SELECT rating INTO r FROM public.users WHERE id = 'aaaa0001-0000-4000-8000-00000000e001';
  IF r <> 4 THEN RAISE EXCEPTION 'FAIL після 4 точок з EXIF rating = %', r; END IF;

  -- 6-та приватна → private_limit_reached; після видалення однієї — знову можна, і п'ятий бал
  res := public.create_pick(gen_random_uuid(), 'aaaa0001-0000-4000-8000-00000000e001', gen_random_uuid(),
    50.4, 30.5, 'picks/a.jpg', 'private', NULL, NULL, '{"exif":{"verified":true}}'::jsonb);
  IF (res->>'allowed')::boolean OR res->>'code' <> 'private_limit_reached' THEN
    RAISE EXCEPTION 'FAIL 6-та приватна: %', res;
  END IF;
  UPDATE public.mushroom_picks SET deleted_at = now()
  WHERE id = (SELECT id FROM public.mushroom_picks WHERE user_id = 'aaaa0001-0000-4000-8000-00000000e001' LIMIT 1);
  res := public.create_pick(gen_random_uuid(), 'aaaa0001-0000-4000-8000-00000000e001', gen_random_uuid(),
    50.4, 30.5, 'picks/a.jpg', 'private', NULL, NULL, '{"exif":{"verified":true}}'::jsonb);
  IF NOT (res->>'created')::boolean THEN RAISE EXCEPTION 'FAIL після видалення: %', res; END IF;
  SELECT rating INTO r FROM public.users WHERE id = 'aaaa0001-0000-4000-8000-00000000e001';
  IF r <> 5 THEN RAISE EXCEPTION 'FAIL п''ятий бал: rating = %', r; END IF;

  -- шостий бал за 7 днів не нараховується
  UPDATE public.mushroom_picks SET deleted_at = now()
  WHERE id = (SELECT id FROM public.mushroom_picks WHERE user_id = 'aaaa0001-0000-4000-8000-00000000e001' AND deleted_at IS NULL LIMIT 1);
  res := public.create_pick(gen_random_uuid(), 'aaaa0001-0000-4000-8000-00000000e001', gen_random_uuid(),
    50.4, 30.5, 'picks/a.jpg', 'private', NULL, NULL, '{"exif":{"verified":true}}'::jsonb);
  IF NOT (res->>'created')::boolean THEN RAISE EXCEPTION 'FAIL 7-ма точка: %', res; END IF;
  SELECT rating INTO r FROM public.users WHERE id = 'aaaa0001-0000-4000-8000-00000000e001';
  IF r <> 5 THEN RAISE EXCEPTION 'FAIL понад 5 балів за 7 днів: rating = %', r; END IF;
  RAISE NOTICE 'OK бал за EXIF: лише приватні з EXIF, до 5 за 7 днів; до 5 приватних одночасно';
END $$;

-- нових приватних — не більше 10 за 7 днів (навіть якщо видаляти)
DO $$
DECLARE res jsonb; i int;
BEGIN
  -- у Мандрівника вже 7 створених за тиждень; ще 3 з видаленням → 10, 11-та — weekly_limit_reached
  FOR i IN 1..3 LOOP
    UPDATE public.mushroom_picks SET deleted_at = now()
    WHERE id = (SELECT id FROM public.mushroom_picks WHERE user_id = 'aaaa0001-0000-4000-8000-00000000e001' AND deleted_at IS NULL LIMIT 1);
    res := public.create_pick(gen_random_uuid(), 'aaaa0001-0000-4000-8000-00000000e001', gen_random_uuid(),
      50.4, 30.5, 'picks/a.jpg', 'private');
    IF NOT (res->>'created')::boolean THEN RAISE EXCEPTION 'FAIL нова приватна %: %', i, res; END IF;
  END LOOP;
  UPDATE public.mushroom_picks SET deleted_at = now()
  WHERE id = (SELECT id FROM public.mushroom_picks WHERE user_id = 'aaaa0001-0000-4000-8000-00000000e001' AND deleted_at IS NULL LIMIT 1);
  res := public.create_pick(gen_random_uuid(), 'aaaa0001-0000-4000-8000-00000000e001', gen_random_uuid(),
    50.4, 30.5, 'picks/a.jpg', 'private');
  IF (res->>'allowed')::boolean OR res->>'code' <> 'weekly_limit_reached' THEN
    RAISE EXCEPTION 'FAIL 11-та нова приватна за тиждень: %', res;
  END IF;
  RAISE NOTICE 'OK нових приватних — до 10 за 7 днів';
END $$;
RESET ROLE;

-- ─── 4. Публічні: Мандрівник — ні; Лісовик — 7 за 7 днів; Хранитель — 15 ───
UPDATE public.users SET rating = 201 WHERE id = 'aaaa0002-0000-4000-8000-00000000e002';
UPDATE public.users SET rating = 600 WHERE id = 'aaaa0003-0000-4000-8000-00000000e003';
SET LOCAL ROLE service_role;
DO $$
DECLARE r record; i int;
BEGIN
  SELECT * INTO r FROM public.can_create_pick('aaaa0001-0000-4000-8000-00000000e001', 'public');
  IF r.allowed OR r.code <> 'level_required' THEN RAISE EXCEPTION 'FAIL Мандрівник публікує: %', r.code; END IF;

  FOR i IN 1..7 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, species_id, display_geom, deleted_at)
    VALUES ('aaaa0002-0000-4000-8000-00000000e002', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public',
            'boletus_edulis', 'SRID=4326;POINT(30.504 50.403)', CASE WHEN i = 1 THEN now() END);
  END LOOP;
  SELECT * INTO r FROM public.can_create_pick('aaaa0002-0000-4000-8000-00000000e002', 'public');
  IF r.allowed OR r.code <> 'weekly_limit_reached' THEN
    RAISE EXCEPTION 'FAIL Лісовик: 8-ма публічна за 7 днів (видалена теж рахується): % %', r.allowed, r.code;
  END IF;

  FOR i IN 1..14 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, species_id, display_geom)
    VALUES ('aaaa0003-0000-4000-8000-00000000e003', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public',
            'boletus_edulis', 'SRID=4326;POINT(30.504 50.403)');
  END LOOP;
  SELECT * INTO r FROM public.can_create_pick('aaaa0003-0000-4000-8000-00000000e003', 'public');
  IF NOT r.allowed THEN RAISE EXCEPTION 'FAIL Хранитель: 15-та публічна заборонена: %', r.code; END IF;
  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, pick_type, species_id, display_geom)
  VALUES ('aaaa0003-0000-4000-8000-00000000e003', 'SRID=4326;POINT(30.5 50.4)', 'boletus_edulis', 'public',
          'boletus_edulis', 'SRID=4326;POINT(30.504 50.403)');
  SELECT * INTO r FROM public.can_create_pick('aaaa0003-0000-4000-8000-00000000e003', 'public');
  IF r.allowed OR r.code <> 'weekly_limit_reached' THEN RAISE EXCEPTION 'FAIL Хранитель: 16-та дозволена'; END IF;
  RAISE NOTICE 'OK публічні: з Лісовика 7, Хранитель 15 за 7 днів';
END $$;
RESET ROLE;

ROLLBACK;
