-- ============================================================================
-- Карта тук-туків (міграція 20261111100000, BACKEND_PLAN B3.3, ADR-018 §18.5)
--   * чужі приватні точки не повертаються ніколи
--   * чужа публічна — лише зі зсунутим місцем; фільтр bbox теж працює за ним
--   * відхилені й видалені точки не повертаються
--   * власні точки — з точними координатами; приватні — лише з p_include_private
--   * функції доступні тільки service_role
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

-- ─── Фікстури ───────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email) VALUES
  ('a1a1a1a1-0000-4000-8000-0000000033a1', 'author33@test.local'),
  ('b2b2b2b2-0000-4000-8000-0000000033b2', 'viewer33@test.local');

-- Точне місце — всередині першої області; зсунуте — за 400 м на північ від нього.
CREATE TEMP TABLE fx ON COMMIT DROP AS
SELECT r.id AS region_id,
       p.pt AS exact_geom,
       extensions.ST_Project(p.pt::extensions.geography, 400, 0)::extensions.geometry AS shown_geom
FROM (SELECT id, polygon FROM public.regions ORDER BY id LIMIT 1) r,
     LATERAL (SELECT extensions.ST_PointOnSurface(r.polygon) AS pt) p;
GRANT SELECT ON fx TO service_role;

UPDATE public.users SET home_region_id = (SELECT region_id FROM fx)
WHERE id IN ('a1a1a1a1-0000-4000-8000-0000000033a1', 'b2b2b2b2-0000-4000-8000-0000000033b2');

INSERT INTO public.mushroom_picks
  (id, user_id, geom, display_geom, mushroom_type, species_id, pick_type, verification_status, deleted_at, description, photo_url)
SELECT v.id::uuid, 'a1a1a1a1-0000-4000-8000-0000000033a1', fx.exact_geom::extensions.geography,
       CASE WHEN v.pick_type = 'public' THEN fx.shown_geom::extensions.geography END,
       COALESCE(v.species, 'unknown'), v.species, v.pick_type, v.status,
       CASE WHEN v.deleted THEN now() END, v.descr, 'picks/' || v.id || '.jpg'
FROM fx, (VALUES
  ('00000000-0000-4000-8000-000000003301', 'public',  'pending',  'boletus_edulis', false, 'Під сосною'),
  ('00000000-0000-4000-8000-000000003302', 'public',  'verified', 'boletus_edulis', false, NULL),
  ('00000000-0000-4000-8000-000000003303', 'public',  'rejected', 'boletus_edulis', false, NULL),
  ('00000000-0000-4000-8000-000000003304', 'public',  'pending',  'boletus_edulis', true,  NULL),
  ('00000000-0000-4000-8000-000000003305', 'private', 'pending',  NULL,             false, 'Моє таємне місце')
) AS v(id, pick_type, status, species, deleted, descr);

-- ─── 1. Клієнтським ролям функції недоступні ───────────────────────────────
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.get_picks_map('b2b2b2b2-0000-4000-8000-0000000033b2', 1);
    RAISE EXCEPTION 'Test 1 failed: authenticated can call get_picks_map';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.get_pick_card('b2b2b2b2-0000-4000-8000-0000000033b2', 1, '00000000-0000-4000-8000-000000003301');
    RAISE EXCEPTION 'Test 1b failed: authenticated can call get_pick_card';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

SET LOCAL ROLE service_role;

DO $$
DECLARE
  viewer CONSTANT UUID := 'b2b2b2b2-0000-4000-8000-0000000033b2';
  author CONSTANT UUID := 'a1a1a1a1-0000-4000-8000-0000000033a1';
  rid INT; ex extensions.geometry; sh extensions.geometry;
  res JSONB; ids TEXT; card JSONB; item JSONB;
BEGIN
  SELECT region_id, exact_geom, shown_geom INTO rid, ex, sh FROM fx;

  -- ─── 2. Глядач бачить лише чужі публічні, не відхилені й не видалені ───────
  res := public.get_picks_map(viewer, rid, NULL, NULL, NULL, NULL, true, 500);
  SELECT string_agg(right(e->>'id', 2), ',' ORDER BY e->>'id') INTO ids FROM jsonb_array_elements(res) e;
  IF ids IS DISTINCT FROM '01,02' THEN
    RAISE EXCEPTION 'Test 2 failed: viewer sees picks [%], expected [01,02]', ids;
  END IF;

  -- …і тільки зі зсунутим місцем: координати ≠ точним, is_exact = false
  FOR item IN SELECT * FROM jsonb_array_elements(res) LOOP
    IF (item->>'is_exact')::boolean OR (item->>'is_mine')::boolean THEN
      RAISE EXCEPTION 'Test 2b failed: foreign pick marked exact/mine: %', item;
    END IF;
    IF abs((item->>'lat')::float8 - extensions.ST_Y(sh)) > 1e-9 OR abs((item->>'lng')::float8 - extensions.ST_X(sh)) > 1e-9 THEN
      RAISE EXCEPTION 'Test 2c failed: foreign pick is not at display_geom: %', item;
    END IF;
    IF abs((item->>'lat')::float8 - extensions.ST_Y(ex)) < 1e-6 THEN
      RAISE EXCEPTION 'Test 2d failed: exact latitude leaked: %', item;
    END IF;
  END LOOP;
  IF res::text LIKE '%' || extensions.ST_Y(ex)::text || '%' THEN
    RAISE EXCEPTION 'Test 2e failed: exact coordinates present in the response';
  END IF;

  -- ─── 3. bbox фільтрує за зсунутим місцем, а не за точним ──────────────────
  -- Рамка 100 м навколо ТОЧНОГО місця: зсунута точка (400 м) у неї не потрапляє.
  res := public.get_picks_map(viewer, rid,
    extensions.ST_X(ex) - 0.001, extensions.ST_Y(ex) - 0.001,
    extensions.ST_X(ex) + 0.001, extensions.ST_Y(ex) + 0.001, false, 500);
  IF jsonb_array_length(res) <> 0 THEN
    RAISE EXCEPTION 'Test 3 failed: bbox around the exact place returned % picks (location probing)', jsonb_array_length(res);
  END IF;
  -- Рамка навколо ЗСУНУТОГО місця — точки є.
  res := public.get_picks_map(viewer, rid,
    extensions.ST_X(sh) - 0.001, extensions.ST_Y(sh) - 0.001,
    extensions.ST_X(sh) + 0.001, extensions.ST_Y(sh) + 0.001, false, 500);
  IF jsonb_array_length(res) <> 2 THEN
    RAISE EXCEPTION 'Test 3b failed: bbox around the shown place returned % picks, expected 2', jsonb_array_length(res);
  END IF;

  -- ─── 4. Інша область — нічого ──────────────────────────────────────────────
  res := public.get_picks_map(viewer, (SELECT max(id) FROM public.regions), NULL, NULL, NULL, NULL, true, 500);
  IF rid <> (SELECT max(id) FROM public.regions) AND jsonb_array_length(res) <> 0 THEN
    RAISE EXCEPTION 'Test 4 failed: picks of another region returned';
  END IF;

  -- ─── 5. Автор: свої публічні завжди, приватні — лише з прапорцем; місце точне ─
  res := public.get_picks_map(author, rid, NULL, NULL, NULL, NULL, false, 500);
  SELECT string_agg(right(e->>'id', 2), ',' ORDER BY e->>'id') INTO ids FROM jsonb_array_elements(res) e;
  IF ids IS DISTINCT FROM '01,02,03' THEN
    RAISE EXCEPTION 'Test 5 failed: author sees [%], expected [01,02,03]', ids;
  END IF;
  res := public.get_picks_map(author, rid, NULL, NULL, NULL, NULL, true, 500);
  SELECT string_agg(right(e->>'id', 2), ',' ORDER BY e->>'id') INTO ids FROM jsonb_array_elements(res) e;
  IF ids IS DISTINCT FROM '01,02,03,05' THEN
    RAISE EXCEPTION 'Test 5b failed: author with private sees [%], expected [01,02,03,05]', ids;
  END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(res) LOOP
    IF NOT (item->>'is_exact')::boolean OR abs((item->>'lat')::float8 - extensions.ST_Y(ex)) > 1e-9 THEN
      RAISE EXCEPTION 'Test 5c failed: own pick is not exact: %', item;
    END IF;
  END LOOP;

  -- ─── 6. Ліміт: повертається p_limit + 1, щоб знати про «ще є» ──────────────
  res := public.get_picks_map(author, rid, NULL, NULL, NULL, NULL, true, 2);
  IF jsonb_array_length(res) <> 3 THEN
    RAISE EXCEPTION 'Test 6 failed: limit 2 returned % rows, expected 3', jsonb_array_length(res);
  END IF;

  -- ─── 7. Картка ─────────────────────────────────────────────────────────────
  card := public.get_pick_card(viewer, rid, '00000000-0000-4000-8000-000000003301');
  IF card IS NULL OR (card->>'is_exact')::boolean OR card->>'description' <> 'Під сосною'
     OR card->>'name_ua' IS NULL OR abs((card->>'lat')::float8 - extensions.ST_Y(sh)) > 1e-9 THEN
    RAISE EXCEPTION 'Test 7 failed: foreign public card is wrong: %', card;
  END IF;
  IF card ? 'user_id' THEN RAISE EXCEPTION 'Test 7b failed: card exposes the author'; END IF;

  IF public.get_pick_card(viewer, rid, '00000000-0000-4000-8000-000000003305') IS NOT NULL THEN
    RAISE EXCEPTION 'Test 7c failed: foreign private pick card returned';
  END IF;
  IF public.get_pick_card(viewer, rid, '00000000-0000-4000-8000-000000003303') IS NOT NULL THEN
    RAISE EXCEPTION 'Test 7d failed: rejected pick card returned to a stranger';
  END IF;
  IF public.get_pick_card(viewer, rid, '00000000-0000-4000-8000-000000003304') IS NOT NULL
     OR public.get_pick_card(author, rid, '00000000-0000-4000-8000-000000003304') IS NOT NULL THEN
    RAISE EXCEPTION 'Test 7e failed: deleted pick card returned';
  END IF;
  IF public.get_pick_card(viewer, rid, '00000000-0000-4000-8000-00000000ffff') IS NOT NULL THEN
    RAISE EXCEPTION 'Test 7f failed: card for a missing pick';
  END IF;

  card := public.get_pick_card(author, rid, '00000000-0000-4000-8000-000000003305');
  IF card IS NULL OR NOT (card->>'is_exact')::boolean OR abs((card->>'lat')::float8 - extensions.ST_Y(ex)) > 1e-9
     OR card->>'description' <> 'Моє таємне місце' THEN
    RAISE EXCEPTION 'Test 7g failed: own private card is wrong: %', card;
  END IF;

  RAISE NOTICE '✅ rls_picks_map: all checks passed';
END $$;

ROLLBACK;
