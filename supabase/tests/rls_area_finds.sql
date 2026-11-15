-- ============================================================================
-- Знахідки в ділянці (міграція 20261115120000; ADR-015 §15.8 п.14)
--   * analysis_history: клієнтам недоступна; запис — лише своєї ділянки
--   * area_finds: лише власні точки в межах квадрата ділянки, з позначкою «збіглося з прогнозом»
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a1a1a1a1-0000-4000-8000-0000000031a1', 'owner31@test.local'),
  ('b2b2b2b2-0000-4000-8000-0000000031b2', 'other31@test.local');

CREATE TEMP TABLE fx31 ON COMMIT DROP AS
SELECT r.id AS region_id,
       extensions.ST_Y(p.pt) AS lat, extensions.ST_X(p.pt) AS lng
FROM (SELECT id, polygon FROM public.regions ORDER BY id LIMIT 1) r,
     LATERAL (SELECT extensions.ST_PointOnSurface(r.polygon) AS pt) p;
GRANT SELECT ON fx31 TO service_role, authenticated;

SET LOCAL ROLE service_role;

DO $$
DECLARE
  owner CONSTANT UUID := 'a1a1a1a1-0000-4000-8000-0000000031a1';
  other CONSTANT UUID := 'b2b2b2b2-0000-4000-8000-0000000031b2';
  rid INT; la FLOAT8; lo FLOAT8; area UUID; n INT; m INT;
  today DATE := (now() AT TIME ZONE 'Europe/Kyiv')::date;
BEGIN
  SELECT region_id, lat, lng INTO rid, la, lo FROM fx31;
  SELECT id INTO area FROM public.create_analysis_area(owner, 1, la, lo, 5, rid);

  -- Прогноз дня: зимовий опеньок.
  PERFORM public.save_analysis_history(owner, area, today, ARRAY['flammulina_velutipes']);
  -- Чужий користувач не може писати в чужу ділянку.
  PERFORM public.save_analysis_history(other, area, today, ARRAY['boletus_edulis']);
  IF (SELECT species FROM public.analysis_history WHERE area_id = area AND day = today) <> ARRAY['flammulina_velutipes'] THEN
    RAISE EXCEPTION 'Test 1 failed: history overwritten by another user';
  END IF;

  -- Знахідки: дві свої в ділянці (одна збігається з прогнозом), одна своя далеко, одна чужа поруч.
  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, species_id, pick_type, captured_at) VALUES
    (owner, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.001, la + 0.001), 4326)::extensions.geography,
     'flammulina_velutipes', 'flammulina_velutipes', 'private', now()),
    (owner, extensions.ST_SetSRID(extensions.ST_MakePoint(lo - 0.002, la), 4326)::extensions.geography,
     'boletus_edulis', 'boletus_edulis', 'private', now()),
    (owner, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.5, la + 0.5), 4326)::extensions.geography,
     'boletus_edulis', 'boletus_edulis', 'private', now()),
    (other, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la), 4326)::extensions.geography,
     'boletus_edulis', 'boletus_edulis', 'private', now());

  SELECT count(*), count(*) FILTER (WHERE matched) INTO n, m FROM public.area_finds(owner, area, today - 1, today);
  IF n <> 2 THEN RAISE EXCEPTION 'Test 2 failed: expected 2 own finds in the area, got %', n; END IF;
  IF m <> 1 THEN RAISE EXCEPTION 'Test 3 failed: expected 1 matched find, got %', m; END IF;

  -- Чужа ділянка — нічого.
  SELECT count(*) INTO n FROM public.area_finds(other, area, today - 1, today);
  IF n <> 0 THEN RAISE EXCEPTION 'Test 4 failed: other user sees finds of a foreign area'; END IF;
END $$;

-- Клієнт не читає історію прогнозу і не викликає функції.
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.analysis_history LIMIT 1;
    RAISE EXCEPTION 'Test 5 failed: client reads analysis_history';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM * FROM public.area_finds('a1a1a1a1-0000-4000-8000-0000000031a1', gen_random_uuid(), current_date, current_date);
    RAISE EXCEPTION 'Test 6 failed: client calls area_finds';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

ROLLBACK;
