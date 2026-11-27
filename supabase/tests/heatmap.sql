-- ============================================================================
-- B3.5a: теплова карта (міграція 20261128150000; ADR-010, ADR-013 §13.5)
--   * нижче «Лісовика» — level_required; «Лісовик» — своя область, 3 дні; 7/30 днів і чужа область — pro_required;
--   * «Майстер» і Pro — уся Україна й історія;
--   * клітинка — лише ≥ 5 перевірених публічних точок від ≥ 2 авторів; приватні, неперевірені, видалені,
--     старі — не рахуються; кількість не віддаємо, лише рівень 1–3;
--   * функція — лише service_role.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a7000001-0000-4000-8000-0000000097a1', 'hm-forester@test.local'),
  ('a7000002-0000-4000-8000-0000000097a2', 'hm-author2@test.local'),
  ('a7000003-0000-4000-8000-0000000097a3', 'hm-novice@test.local'),
  ('a7000004-0000-4000-8000-0000000097a4', 'hm-master@test.local'),
  ('a7000005-0000-4000-8000-0000000097a5', 'hm-solo@test.local');

SET LOCAL ROLE service_role;

DO $$
DECLARE
  f  CONSTANT UUID := 'a7000001-0000-4000-8000-0000000097a1';
  a2 CONSTANT UUID := 'a7000002-0000-4000-8000-0000000097a2';
  nv CONSTANT UUID := 'a7000003-0000-4000-8000-0000000097a3';
  ms CONSTANT UUID := 'a7000004-0000-4000-8000-0000000097a4';
  so CONSTANT UUID := 'a7000005-0000-4000-8000-0000000097a5';
  rid INT; other INT; la DOUBLE PRECISION; lo DOUBLE PRECISION; ola DOUBLE PRECISION; olo DOUBLE PRECISION;
  r JSONB; i INT;
BEGIN
  SELECT r2.id, extensions.ST_Y(extensions.ST_PointOnSurface(r2.polygon)), extensions.ST_X(extensions.ST_PointOnSurface(r2.polygon))
    INTO rid, la, lo FROM public.regions r2 ORDER BY r2.id LIMIT 1;
  -- далека область (не сусідня)
  SELECT r2.id, extensions.ST_Y(extensions.ST_PointOnSurface(r2.polygon)), extensions.ST_X(extensions.ST_PointOnSurface(r2.polygon))
    INTO other, ola, olo FROM public.regions r2, public.regions h
  WHERE h.id = rid AND NOT extensions.ST_DWithin(r2.polygon, h.polygon, 0.5) ORDER BY r2.id LIMIT 1;

  -- тестові точки — у центрах клітинок сітки (0.009° × 0.014°), щоб група не розпалась на дві клітинки
  la := (floor(la / 0.009) + 0.5) * 0.009;   lo := (floor(lo / 0.014) + 0.5) * 0.014;
  ola := (floor(ola / 0.009) + 0.5) * 0.009; olo := (floor(olo / 0.014) + 0.5) * 0.014;

  UPDATE public.users SET home_region_id = rid, rating = 250 WHERE id = f;                       -- Лісовик
  UPDATE public.users SET home_region_id = rid, rating = 100 WHERE id = nv;                      -- Слідопит
  UPDATE public.users SET home_region_id = rid, rating = 1200, knowledge_certified_at = now() WHERE id = ms; -- Майстер

  -- клітинка A: 3 + 3 перевірені публічні від двох авторів, свіжі
  FOR i IN 1..6 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
    VALUES (CASE WHEN i <= 3 THEN f ELSE a2 END,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.0001 * i, la), 4326)::extensions.geography,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.004, la), 4326)::extensions.geography,
      'boletus_edulis', 'boletus_edulis', 'public', 'verified');
  END LOOP;
  -- клітинка B (~5 км північніше): 6 точок, але від одного автора — не показуємо
  FOR i IN 1..6 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
    VALUES (so, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.0001 * i, la + 0.045), 4326)::extensions.geography,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la + 0.045), 4326)::extensions.geography,
      'boletus_edulis', 'boletus_edulis', 'public', 'verified');
  END LOOP;
  -- клітинка C (~5 км південніше): 2 + 2 перевірені + приватні, неперевірені й видалені — разом < 5 врахованих
  FOR i IN 1..4 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
    VALUES (CASE WHEN i <= 2 THEN f ELSE a2 END,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.0001 * i, la - 0.045), 4326)::extensions.geography,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la - 0.045), 4326)::extensions.geography,
      'boletus_edulis', 'boletus_edulis', 'public', 'verified');
  END LOOP;
  INSERT INTO public.mushroom_picks (user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, deleted_at)
  VALUES
    (f,  extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la - 0.045), 4326)::extensions.geography, NULL, 'boletus_edulis', 'boletus_edulis', 'private', 'pending', NULL),
    (a2, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la - 0.045), 4326)::extensions.geography,
         extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la - 0.045), 4326)::extensions.geography, 'boletus_edulis', 'boletus_edulis', 'public', 'pending', NULL),
    (a2, extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la - 0.045), 4326)::extensions.geography,
         extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la - 0.045), 4326)::extensions.geography, 'boletus_edulis', 'boletus_edulis', 'public', 'verified', now());
  -- клітинка D у далекій області: 6 точок від двох авторів — бачить лише Майстер
  FOR i IN 1..6 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
    VALUES (CASE WHEN i <= 3 THEN f ELSE a2 END,
      extensions.ST_SetSRID(extensions.ST_MakePoint(olo + 0.0001 * i, ola), 4326)::extensions.geography,
      extensions.ST_SetSRID(extensions.ST_MakePoint(olo, ola), 4326)::extensions.geography,
      'boletus_edulis', 'boletus_edulis', 'public', 'verified');
  END LOOP;
  -- клітинка E: 6 старих (10 днів) у своїй області — лише в історії за 30 днів
  FOR i IN 1..6 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, created_at)
    VALUES (CASE WHEN i <= 3 THEN f ELSE a2 END,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.056 + 0.0001 * i, la), 4326)::extensions.geography,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.056, la), 4326)::extensions.geography,
      'boletus_edulis', 'boletus_edulis', 'public', 'verified', now() - INTERVAL '10 days');
  END LOOP;

  -- 1. нижче «Лісовика» — level_required; Pro відкриває
  r := public.heatmap_cells(nv);
  IF r->>'code' <> 'level_required' THEN RAISE EXCEPTION 'Test 1a failed: %', r; END IF;
  r := public.heatmap_cells(nv, 3, true);
  IF r->>'ok' <> 'true' OR r->>'scope' <> 'ukraine' THEN RAISE EXCEPTION 'Test 1b failed: %', r; END IF;

  -- 2. Лісовик: своя область, 3 дні — лише клітинка A (B — один автор, C — мало, D — чужа, E — старі)
  r := public.heatmap_cells(f);
  IF r->>'ok' <> 'true' OR r->>'scope' <> 'home' OR jsonb_array_length(r->'cells') <> 1
     OR (r->'cells'->0->>'level')::int <> 1 OR abs((r->'cells'->0->>'lat')::float8 - la) > 0.009 THEN
    RAISE EXCEPTION 'Test 2 failed: %', r;
  END IF;
  IF r::text LIKE '%"n"%' OR r::text LIKE '%count%' THEN RAISE EXCEPTION 'Test 2b failed: count leaked'; END IF;

  -- 3. Лісовик: 7/30 днів і чужа область — pro_required; невідомий період — validation_error
  IF public.heatmap_cells(f, 7)->>'code' <> 'pro_required' THEN RAISE EXCEPTION 'Test 3a failed'; END IF;
  IF public.heatmap_cells(f, 5)->>'code' <> 'validation_error' THEN RAISE EXCEPTION 'Test 3b failed'; END IF;
  r := public.heatmap_cells(f, 3, false, olo - 0.05, ola - 0.05, olo + 0.05, ola + 0.05);
  IF r->>'code' <> 'pro_required' THEN RAISE EXCEPTION 'Test 3c failed: %', r; END IF;
  -- bbox у своїй області — працює й обрізає
  r := public.heatmap_cells(f, 3, false, lo - 0.02, la - 0.02, lo + 0.02, la + 0.02);
  IF jsonb_array_length(r->'cells') <> 1 THEN RAISE EXCEPTION 'Test 3d failed: %', r; END IF;

  -- 4. Майстер: уся Україна (A + D), за 30 днів — ще й E
  r := public.heatmap_cells(ms);
  IF r->>'scope' <> 'ukraine' OR jsonb_array_length(r->'cells') <> 2 OR r->>'can_change_period' <> 'true' THEN
    RAISE EXCEPTION 'Test 4a failed: %', r;
  END IF;
  r := public.heatmap_cells(ms, 30);
  IF jsonb_array_length(r->'cells') <> 3 THEN RAISE EXCEPTION 'Test 4b failed: %', r; END IF;

  -- 5. Хранитель: своя + сусідні області
  UPDATE public.users SET rating = 600 WHERE id = f;
  r := public.heatmap_cells(f);
  IF r->>'scope' <> 'neighbours' OR jsonb_array_length(r->'cells') <> 1 THEN RAISE EXCEPTION 'Test 5 failed: %', r; END IF;

  -- 6. рівні: 10+ точок — рівень 2
  FOR i IN 1..5 LOOP
    INSERT INTO public.mushroom_picks (user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status)
    VALUES (a2, extensions.ST_SetSRID(extensions.ST_MakePoint(lo + 0.0002 * i, la), 4326)::extensions.geography,
      extensions.ST_SetSRID(extensions.ST_MakePoint(lo, la), 4326)::extensions.geography,
      'boletus_edulis', 'boletus_edulis', 'public', 'verified');
  END LOOP;
  r := public.heatmap_cells(f);
  IF (r->'cells'->0->>'level')::int <> 2 THEN RAISE EXCEPTION 'Test 6 failed: %', r; END IF;

  -- 7. без області — home_region_required
  UPDATE public.users SET home_region_id = NULL WHERE id = nv;
  IF public.heatmap_cells(nv)->>'code' <> 'home_region_required' THEN RAISE EXCEPTION 'Test 7 failed'; END IF;

  RAISE NOTICE 'OK теплова карта: доступ, k-анонімність, період, області';
END $$;

-- 8. клієнт функцію не викликає
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.heatmap_cells('a7000001-0000-4000-8000-0000000097a1');
    RAISE EXCEPTION 'Test 8 failed: authenticated can call heatmap_cells';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK теплова карта: лише service_role';
END $$;
RESET ROLE;

ROLLBACK;
