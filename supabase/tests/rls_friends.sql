-- ============================================================================
-- Друзі (міграція 20261120100000; ADR-021 §21.1, BACKEND_PLAN B9.2)
--   * запит → прийняти → друзі; зустрічний запит = прийняти;
--   * відхилено — повтор не раніше ніж за 30 днів;
--   * до 20 запитів на добу, до 200 друзів;
--   * блок ховає все в обидва боки (пошук, стан, дії того, кого заблокували);
--   * клієнт не пише в таблиці напряму; бачить лише свої пари, крім тих, де його заблокували.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('f1000000-0000-4000-8000-000000000001', 'f1@test.local'),
  ('f2000000-0000-4000-8000-000000000002', 'f2@test.local'),
  ('f3000000-0000-4000-8000-000000000003', 'f3@test.local');
-- для лімітів: 21 адресат запитів і 200 друзів (auth.users пише лише власник схеми)
INSERT INTO auth.users (id, email) SELECT gen_random_uuid(), 'bulk' || lpad(g::text, 3, '0') || '@test.local' FROM generate_series(1, 21) g;
INSERT INTO auth.users (id, email) SELECT gen_random_uuid(), 'fr' || lpad(g::text, 3, '0') || '@test.local' FROM generate_series(1, 200) g;

SET LOCAL ROLE service_role;

UPDATE public.users SET handle = 'Олена_лісова', handle_key = 'олена_лісова' WHERE id = 'f1000000-0000-4000-8000-000000000001';
UPDATE public.users SET handle = 'Оленка', handle_key = 'оленка' WHERE id = 'f2000000-0000-4000-8000-000000000002';
UPDATE public.users SET handle = 'Петро', handle_key = 'петро' WHERE id = 'f3000000-0000-4000-8000-000000000003';

DO $$
DECLARE
  u1 CONSTANT UUID := 'f1000000-0000-4000-8000-000000000001';
  u2 CONSTANT UUID := 'f2000000-0000-4000-8000-000000000002';
  u3 CONSTANT UUID := 'f3000000-0000-4000-8000-000000000003';
  res JSONB;
  n INT;
  t0 CONSTANT TIMESTAMPTZ := '2026-11-20 10:00:00+00';
BEGIN
  -- 1. Запит → у мене «outgoing», в нього «incoming», push отримувачу.
  res := public.friend_action(u1, u2, 'request', t0);
  IF res->>'relation' <> 'outgoing' OR res->>'notify' <> 'request' THEN RAISE EXCEPTION 'Test 1 failed: %', res; END IF;
  IF public.friend_relation(u2, u1) <> 'incoming' THEN RAISE EXCEPTION 'Test 1b failed'; END IF;
  -- повторний запит — без дубля й без push
  res := public.friend_action(u1, u2, 'request', t0);
  IF res->>'notify' IS NOT NULL THEN RAISE EXCEPTION 'Test 1c failed: %', res; END IF;

  -- 2. Прийняти → друзі, push тому, хто запитував.
  res := public.friend_action(u2, u1, 'accept', t0);
  IF res->>'relation' <> 'friends' OR res->>'notify' <> 'accepted' THEN RAISE EXCEPTION 'Test 2 failed: %', res; END IF;
  IF NOT public.are_friends(u1, u2) OR public.friend_count(u1) <> 1 THEN RAISE EXCEPTION 'Test 2b failed'; END IF;

  -- 3. Видалити — мовчки, рядка немає.
  res := public.friend_action(u2, u1, 'remove', t0);
  IF res->>'relation' <> 'none' OR public.are_friends(u1, u2) THEN RAISE EXCEPTION 'Test 3 failed: %', res; END IF;

  -- 4. Зустрічний запит = прийняти.
  PERFORM public.friend_action(u1, u3, 'request', t0);
  res := public.friend_action(u3, u1, 'request', t0);
  IF res->>'relation' <> 'friends' OR res->>'notify' <> 'accepted' THEN RAISE EXCEPTION 'Test 4 failed: %', res; END IF;

  -- 5. Відхилено → повтор від того самого — лише через 30 днів; відхилити можна лише чужий запит.
  PERFORM public.friend_action(u2, u1, 'request', t0);
  res := public.friend_action(u2, u1, 'accept', t0);
  IF res->>'code' <> 'no_request' THEN RAISE EXCEPTION 'Test 5a failed: %', res; END IF;
  PERFORM public.friend_action(u1, u2, 'decline', t0);
  IF public.friend_relation(u2, u1) <> 'none' THEN RAISE EXCEPTION 'Test 5b failed'; END IF;
  res := public.friend_action(u2, u1, 'request', t0 + interval '29 days');
  IF res->>'code' <> 'request_cooldown' THEN RAISE EXCEPTION 'Test 5c failed: %', res; END IF;
  res := public.friend_action(u2, u1, 'request', t0 + interval '31 days');
  IF res->>'relation' <> 'outgoing' THEN RAISE EXCEPTION 'Test 5d failed: %', res; END IF;
  -- скасувати свій запит
  PERFORM public.friend_action(u2, u1, 'cancel', t0 + interval '31 days');
  IF public.friend_relation(u1, u2) <> 'none' THEN RAISE EXCEPTION 'Test 5e failed'; END IF;

  -- 6. Блок: усе зникає в обидва боки.
  PERFORM public.friend_action(u3, u1, 'remove', t0);
  PERFORM public.friend_action(u1, u3, 'request', t0);
  res := public.friend_action(u3, u1, 'block', t0);
  IF res->>'relation' <> 'blocked' THEN RAISE EXCEPTION 'Test 6a failed: %', res; END IF;
  IF public.friend_relation(u1, u3) <> 'hidden' OR public.friend_relation(u3, u1) <> 'blocked' THEN RAISE EXCEPTION 'Test 6b failed'; END IF;
  res := public.friend_action(u1, u3, 'request', t0);
  IF res->>'code' <> 'user_not_found' THEN RAISE EXCEPTION 'Test 6c failed: %', res; END IF;
  res := public.friend_action(u1, u3, 'unblock', t0);
  IF res->>'code' <> 'user_not_found' THEN RAISE EXCEPTION 'Test 6d failed (blocked person unblocks): %', res; END IF;
  SELECT count(*) INTO n FROM public.search_users_by_handle(u1, 'пет');
  IF n <> 0 THEN RAISE EXCEPTION 'Test 6e failed: blocker visible in search'; END IF;
  SELECT count(*) INTO n FROM public.search_users_by_handle(u3, 'олен') s WHERE s.id = u1;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 6f failed: blocked visible in search'; END IF;
  SELECT count(*) INTO n FROM public.friend_list(u1) WHERE id = u3;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 6g failed: blocker in my list'; END IF;
  SELECT count(*) INTO n FROM public.friend_list(u3) WHERE id = u1 AND kind = 'blocked';
  IF n <> 1 THEN RAISE EXCEPTION 'Test 6h failed: blocked list'; END IF;
  res := public.friend_action(u3, u1, 'request', t0);
  IF res->>'code' <> 'blocked_by_you' THEN RAISE EXCEPTION 'Test 6i failed: %', res; END IF;
  PERFORM public.friend_action(u3, u1, 'unblock', t0);
  IF public.friend_relation(u1, u3) <> 'none' THEN RAISE EXCEPTION 'Test 6j failed'; END IF;

  -- 7. Пошук: початок ніка, без урахування регістру, без себе; «_» і «%» — звичайні символи.
  SELECT count(*) INTO n FROM public.search_users_by_handle(u3, 'олен');
  IF n <> 2 THEN RAISE EXCEPTION 'Test 7a failed: % results', n; END IF;
  SELECT count(*) INTO n FROM public.search_users_by_handle(u1, 'олен');
  IF n <> 1 THEN RAISE EXCEPTION 'Test 7b failed: self in search'; END IF;
  SELECT count(*) INTO n FROM public.search_users_by_handle(u3, '%');
  IF n <> 0 THEN RAISE EXCEPTION 'Test 7c failed: wildcard not escaped'; END IF;

  -- 8. Не можна додати себе / неіснуючого.
  IF public.friend_action(u1, u1, 'request', t0)->>'code' <> 'invalid_target' THEN RAISE EXCEPTION 'Test 8a failed'; END IF;
  IF public.friend_action(u1, gen_random_uuid(), 'request', t0)->>'code' <> 'user_not_found' THEN RAISE EXCEPTION 'Test 8b failed'; END IF;
END $$;

-- 9. Ліміт: 20 запитів на добу.
DO $$
DECLARE
  u1 CONSTANT UUID := 'f1000000-0000-4000-8000-000000000001';
  t0 CONSTANT TIMESTAMPTZ := '2026-12-01 10:00:00+00';
  ids UUID[];
  res JSONB;
  i INT;
BEGIN
  SELECT array_agg(id ORDER BY email) INTO ids FROM public.users WHERE email LIKE 'bulk%';
  FOR i IN 1..20 LOOP
    res := public.friend_action(u1, ids[i], 'request', t0 + make_interval(mins => i));
    IF (res->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Test 9a failed at %: %', i, res; END IF;
  END LOOP;
  res := public.friend_action(u1, ids[21], 'request', t0 + interval '30 minutes');
  IF res->>'code' <> 'daily_limit' THEN RAISE EXCEPTION 'Test 9b failed: %', res; END IF;
  res := public.friend_action(u1, ids[21], 'request', t0 + interval '25 hours');
  IF (res->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Test 9c failed: %', res; END IF;
END $$;

-- 10. Ліміт: 200 друзів (і в того, хто приймає, і в того, хто запитував).
DO $$
DECLARE
  u2 CONSTANT UUID := 'f2000000-0000-4000-8000-000000000002';
  u3 CONSTANT UUID := 'f3000000-0000-4000-8000-000000000003';
  x UUID;
  res JSONB;
BEGIN
  FOR x IN SELECT id FROM public.users WHERE email LIKE 'fr%' LOOP
    INSERT INTO public.friendships (user_a, user_b, status, requested_by)
    VALUES (LEAST(u2, x), GREATEST(u2, x), 'accepted', x);
  END LOOP;
  res := public.friend_action(u2, u3, 'request');
  IF res->>'code' <> 'friends_limit' THEN RAISE EXCEPTION 'Test 10a failed: %', res; END IF;
  PERFORM public.friend_action(u3, u2, 'request');
  res := public.friend_action(u2, u3, 'accept');
  IF res->>'code' <> 'friends_limit' THEN RAISE EXCEPTION 'Test 10b failed: %', res; END IF;
END $$;

RESET ROLE;

-- 11. Клієнт: бачить лише свої пари (і не ті, де його заблокували), писати не може.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"f1000000-0000-4000-8000-000000000001","is_anonymous":false}', true);
DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.friendships
  WHERE 'f1000000-0000-4000-8000-000000000001' NOT IN (user_a, user_b);
  IF n <> 0 THEN RAISE EXCEPTION 'Test 11a failed: sees others'' pairs'; END IF;
  BEGIN
    INSERT INTO public.friendships (user_a, user_b, status, requested_by)
    VALUES ('f1000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000003', 'accepted',
            'f1000000-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'Test 11b failed: client inserted friendship';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.friend_action('f1000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000003', 'request');
    RAISE EXCEPTION 'Test 11c failed: client called friend_action';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM count(*) FROM public.user_reports;
    RAISE EXCEPTION 'Test 11d failed: client reads reports';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;
ROLLBACK;
