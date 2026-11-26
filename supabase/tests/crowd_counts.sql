-- ============================================================================
-- crowd_counts (міграція 20261127090000): знахідки спільноти для прогнозу — лише поруч і за видом
--   * підтверджені точки в радіусі — за видом; далеко, непідтверджені, видалені, старші за тиждень — ні;
--   * негативні звіти — лише поруч; клієнту — без доступу.
-- ============================================================================
BEGIN;

INSERT INTO auth.users (id, email) VALUES ('c7000000-0000-4000-8000-0000000071c7', 'crowd@test.local');

SET LOCAL ROLE service_role;
DO $$
DECLARE
  u CONSTANT UUID := 'c7000000-0000-4000-8000-0000000071c7';
  j JSONB;
  pt TEXT := 'SRID=4326;POINT(28.60 50.40)';
BEGIN
  INSERT INTO public.mushroom_picks (user_id, geom, mushroom_type, species_id, pick_type, verification_status, deleted_at, created_at, is_negative)
  VALUES
    (u, 'SRID=4326;POINT(28.61 50.40)', 'boletus_edulis', 'boletus_edulis', 'private', 'verified', NULL, now(), false),   -- ≈ 0,7 км
    (u, 'SRID=4326;POINT(28.62 50.41)', 'boletus_edulis', 'boletus_edulis', 'private', 'verified', NULL, now(), false),   -- ≈ 1,8 км
    (u, 'SRID=4326;POINT(28.60 50.45)', 'cantharellus_cibarius', 'cantharellus_cibarius', 'private', 'verified', NULL, now(), false), -- ≈ 5,6 км
    (u, 'SRID=4326;POINT(29.60 50.40)', 'boletus_edulis', 'boletus_edulis', 'private', 'verified', NULL, now(), false),   -- ≈ 70 км — ні
    (u, 'SRID=4326;POINT(28.61 50.40)', 'boletus_edulis', 'boletus_edulis', 'private', 'pending', NULL, now(), false),    -- не підтверджена — ні
    (u, 'SRID=4326;POINT(28.61 50.40)', 'boletus_edulis', 'boletus_edulis', 'private', 'verified', now(), now(), false),  -- видалена — ні
    (u, 'SRID=4326;POINT(28.61 50.40)', 'boletus_edulis', 'boletus_edulis', 'private', 'verified', NULL, now() - INTERVAL '10 days', false), -- стара — ні
    (u, 'SRID=4326;POINT(28.61 50.40)', 'unknown', NULL, 'private', 'pending', NULL, now(), true);                     -- негативний звіт поруч

  j := public.crowd_counts(50.40, 28.60, 10000, now() - INTERVAL '7 days');
  IF j->'verified' <> '{"boletus_edulis": 2, "cantharellus_cibarius": 1}'::jsonb OR (j->>'negatives')::int <> 1 THEN
    RAISE EXCEPTION 'Test 1 failed: %', j;
  END IF;
  -- далеко від усього — порожньо
  j := public.crowd_counts(48.0, 35.0, 10000, now() - INTERVAL '7 days');
  IF j <> '{"verified": {}, "negatives": 0}'::jsonb THEN RAISE EXCEPTION 'Test 2 failed: %', j; END IF;
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.crowd_counts(50.4, 28.6, 10000, now());
    RAISE EXCEPTION 'Test 3 failed: authenticated called crowd_counts';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

ROLLBACK;
