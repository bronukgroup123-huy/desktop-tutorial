-- ============================================================================
-- Наглядач у застосунку (міграція 20261120110000; ADR-022, B4.4, B4.9)
--   * «Все добре?» у час повернення; без відповіді 15 хв — тривога; автозакриття за 48 год;
--   * закрили похід — трек видалено, Наглядач більше нічого не бачить;
--   * перестали бути друзями — Наглядач зникає і з незакритого походу;
--   * координати й трек — лише власнику й Наглядачам незакритого походу; клієнт не пише.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a7000000-0000-4000-8000-000000000001', 'owner@test.local'),
  ('a7000000-0000-4000-8000-000000000002', 'guard@test.local'),
  ('a7000000-0000-4000-8000-000000000003', 'stranger@test.local');

SET LOCAL ROLE service_role;

INSERT INTO public.friendships (user_a, user_b, status, requested_by)
VALUES ('a7000000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000002', 'accepted', 'a7000000-0000-4000-8000-000000000001');
INSERT INTO public.guardian_links (owner_id, guardian_id, status)
VALUES ('a7000000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000002', 'accepted');

INSERT INTO public.hikes (id, owner_id, route, started_at, expected_return, last_lat, last_lng, last_at)
VALUES ('b7000000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000001',
        '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-20 08:00+00', '2026-11-20 14:00+00', 50.41, 28.61, '2026-11-20 13:00+00');
INSERT INTO public.hike_guardians (hike_id, guardian_id)
VALUES ('b7000000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000002');
INSERT INTO public.hike_points (hike_id, lat, lng, accuracy, recorded_at)
VALUES ('b7000000-0000-4000-8000-000000000001', 50.41, 28.61, 8, '2026-11-20 13:00+00');

DO $$
DECLARE
  h CONSTANT UUID := 'b7000000-0000-4000-8000-000000000001';
  n INT;
  k TEXT;
BEGIN
  -- 1. До часу повернення — нічого.
  SELECT count(*) INTO n FROM public.hike_tick('2026-11-20 13:59+00');
  IF n <> 0 THEN RAISE EXCEPTION 'Test 1 failed: % events before return time', n; END IF;

  -- 2. Час повернення — «Все добре?» грибнику, один раз.
  SELECT string_agg(kind, ',') INTO k FROM public.hike_tick('2026-11-20 14:00+00');
  IF k IS DISTINCT FROM 'check' THEN RAISE EXCEPTION 'Test 2 failed: %', k; END IF;
  SELECT count(*) INTO n FROM public.hike_tick('2026-11-20 14:10+00');
  IF n <> 0 THEN RAISE EXCEPTION 'Test 2b failed: repeated check'; END IF;

  -- 3. Без відповіді 15 хв — тривога Наглядачам.
  SELECT string_agg(kind, ',') INTO k FROM public.hike_tick('2026-11-20 14:15+00');
  IF k IS DISTINCT FROM 'alert' THEN RAISE EXCEPTION 'Test 3 failed: %', k; END IF;
  IF (SELECT status FROM public.hikes WHERE id = h) <> 'alert' THEN RAISE EXCEPTION 'Test 3b failed'; END IF;

  -- 4. Через 48 год після часу повернення — автозакриття, трек видалено.
  SELECT string_agg(kind, ',') INTO k FROM public.hike_tick('2026-11-22 14:01+00');
  IF k IS DISTINCT FROM 'autoclose' THEN RAISE EXCEPTION 'Test 4 failed: %', k; END IF;
  SELECT count(*) INTO n FROM public.hike_points WHERE hike_id = h;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 4b failed: track kept after close'; END IF;
  IF (SELECT last_lat FROM public.hikes WHERE id = h) IS NOT NULL THEN RAISE EXCEPTION 'Test 4c failed: last position kept'; END IF;

  -- 5. Лише один незакритий похід.
  INSERT INTO public.hikes (owner_id, route, expected_return)
  VALUES ('a7000000-0000-4000-8000-000000000001', '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-23 14:00+00');
  BEGIN
    INSERT INTO public.hikes (owner_id, route, expected_return)
    VALUES ('a7000000-0000-4000-8000-000000000001', '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-23 14:00+00');
    RAISE EXCEPTION 'Test 5 failed: two open hikes';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- 6. Без маршруту — ні.
  BEGIN
    INSERT INTO public.hikes (owner_id, route, expected_return)
    VALUES ('a7000000-0000-4000-8000-000000000003', '[]', '2026-11-23 14:00+00');
    RAISE EXCEPTION 'Test 6 failed: hike without route';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- 7. Клієнт: Наглядач бачить незакритий похід друга і трек; чужий — ні; писати — ні.
INSERT INTO public.hike_guardians (hike_id, guardian_id)
SELECT id, 'a7000000-0000-4000-8000-000000000002' FROM public.hikes
WHERE owner_id = 'a7000000-0000-4000-8000-000000000001' AND status <> 'closed';
INSERT INTO public.hike_points (hike_id, lat, lng, accuracy, recorded_at)
SELECT id, 50.42, 28.62, 10, '2026-11-23 10:00+00' FROM public.hikes
WHERE owner_id = 'a7000000-0000-4000-8000-000000000001' AND status <> 'closed';
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000002","is_anonymous":false}', true);
DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.hikes;
  IF n <> 1 THEN RAISE EXCEPTION 'Test 7a failed: guardian sees % hikes (closed must be hidden)', n; END IF;
  SELECT count(*) INTO n FROM public.hike_points;
  IF n <> 1 THEN RAISE EXCEPTION 'Test 7b failed: guardian sees % points', n; END IF;
  BEGIN
    INSERT INTO public.hike_points (hike_id, lat, lng, recorded_at)
    SELECT id, 1, 1, now() FROM public.hikes LIMIT 1;
    RAISE EXCEPTION 'Test 7c failed: client wrote track';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.hike_tick(now());
    RAISE EXCEPTION 'Test 7d failed: client ran tick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000003', true);
SELECT set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000003","is_anonymous":false}', true);
DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.hikes;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 8a failed: stranger sees hikes'; END IF;
  SELECT count(*) INTO n FROM public.hike_points;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 8b failed: stranger sees track'; END IF;
END $$;
RESET ROLE;

-- 9. Перестали бути друзями → Наглядач зникає (зв'язок і незакритий похід).
SET LOCAL ROLE service_role;
DO $$
DECLARE n INT;
BEGIN
  DELETE FROM public.friendships
  WHERE user_a = 'a7000000-0000-4000-8000-000000000001' AND user_b = 'a7000000-0000-4000-8000-000000000002';
  SELECT count(*) INTO n FROM public.guardian_links;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 9a failed: link kept'; END IF;
  SELECT count(*) INTO n FROM public.hike_guardians g JOIN public.hikes h ON h.id = g.hike_id WHERE h.status <> 'closed';
  IF n <> 0 THEN RAISE EXCEPTION 'Test 9b failed: still guardian of open hike'; END IF;
END $$;
RESET ROLE;

ROLLBACK;
