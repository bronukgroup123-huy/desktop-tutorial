-- ============================================================================
-- Приватність фото знахідок (ADR-002 / ADR-018, SEC-006)
--   * bucket mushroom-photos не публічний;
--   * клієнт бачить і змінює лише чернетки у своїй UUID-теці;
--   * чужі чернетки та фінальні очищені фото у server-only теці picks/ невидимі;
--   * anon без Supabase-сесії не має доступу.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('d1000000-0000-4000-8000-000000000001', 'storage-owner@test.local'),
  ('d2000000-0000-4000-8000-000000000002', 'storage-other@test.local');

SET LOCAL ROLE service_role;

DO $$
BEGIN
  IF (SELECT public FROM storage.buckets WHERE id = 'mushroom-photos') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Test 1 failed: mushroom-photos bucket is public or missing';
  END IF;
END $$;

INSERT INTO storage.objects (bucket_id, name, owner_id, metadata) VALUES
  ('mushroom-photos', 'd1000000-0000-4000-8000-000000000001/11111111-1111-4111-8111-111111111111.jpg',
   'd1000000-0000-4000-8000-000000000001', '{"owner":"one"}'),
  ('mushroom-photos', 'd2000000-0000-4000-8000-000000000002/22222222-2222-4222-8222-222222222222.jpg',
   'd2000000-0000-4000-8000-000000000002', '{"owner":"two"}'),
  ('mushroom-photos', 'picks/33333333-3333-4333-8333-333333333333.jpg',
   NULL, '{"final":true}');

RESET ROLE;

-- Власник першої теки: бачить тільки свою чернетку; чужу та server-only фінальну — ні.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"d1000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE
  n INT;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'mushroom-photos';
  IF n <> 1 THEN RAISE EXCEPTION 'Test 2a failed: owner sees % objects, expected 1', n; END IF;

  IF EXISTS (
    SELECT 1 FROM storage.objects
    WHERE name LIKE 'd2000000-%' OR name LIKE 'picks/%'
  ) THEN
    RAISE EXCEPTION 'Test 2b failed: foreign draft or server-only final photo is visible';
  END IF;

  -- Своя чернетка дозволена (саме цей префікс видає POST v1-picks/upload-url).
  INSERT INTO storage.objects (bucket_id, name, owner_id)
  VALUES (
    'mushroom-photos',
    'd1000000-0000-4000-8000-000000000001/44444444-4444-4444-8444-444444444444.webp',
    'd1000000-0000-4000-8000-000000000001'
  );

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner_id)
    VALUES (
      'mushroom-photos',
      'd2000000-0000-4000-8000-000000000002/55555555-5555-4555-8555-555555555555.jpg',
      'd1000000-0000-4000-8000-000000000001'
    );
    RAISE EXCEPTION 'Test 2c failed: user inserted a draft into another user prefix';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner_id)
    VALUES (
      'mushroom-photos',
      'picks/66666666-6666-4666-8666-666666666666.jpg',
      'd1000000-0000-4000-8000-000000000001'
    );
    RAISE EXCEPTION 'Test 2d failed: user inserted into the server-only picks prefix';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  UPDATE storage.objects SET metadata = '{"tampered":true}'
  WHERE bucket_id = 'mushroom-photos'
    AND name = 'd2000000-0000-4000-8000-000000000002/22222222-2222-4222-8222-222222222222.jpg';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 2e failed: user updated a foreign draft'; END IF;

  DELETE FROM storage.objects
  WHERE bucket_id = 'mushroom-photos'
    AND name = 'picks/33333333-3333-4333-8333-333333333333.jpg';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 2f failed: user deleted a server-only final photo'; END IF;
END $$;

RESET ROLE;

-- Інший користувач також бачить тільки власну теку, не чернетки першого власника.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'd2000000-0000-4000-8000-000000000002', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"d2000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'mushroom-photos';
  IF n <> 1 THEN RAISE EXCEPTION 'Test 3 failed: second user sees % objects, expected 1', n; END IF;
END $$;

RESET ROLE;

-- Без Supabase Auth-сесії роль anon не бачить bucket і не може писати.
SET LOCAL ROLE anon;
DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'mushroom-photos';
  IF n <> 0 THEN RAISE EXCEPTION 'Test 4a failed: anon sees % private objects', n; END IF;
  BEGIN
    INSERT INTO storage.objects (bucket_id, name)
    VALUES ('mushroom-photos', 'anonymous/file.jpg');
    RAISE EXCEPTION 'Test 4b failed: anon inserted an object';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;

-- Перевірка після спроб клієнта: чужа чернетка й фінальне фото не змінені/не видалені.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  IF (SELECT metadata FROM storage.objects
      WHERE name = 'd2000000-0000-4000-8000-000000000002/22222222-2222-4222-8222-222222222222.jpg')
      IS DISTINCT FROM '{"owner":"two"}'::jsonb THEN
    RAISE EXCEPTION 'Test 5a failed: foreign draft was modified';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'mushroom-photos'
      AND name = 'picks/33333333-3333-4333-8333-333333333333.jpg'
  ) THEN
    RAISE EXCEPTION 'Test 5b failed: server-only final photo was deleted';
  END IF;
END $$;

RESET ROLE;
ROLLBACK;
