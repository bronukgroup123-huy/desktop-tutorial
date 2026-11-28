-- ============================================================================
-- B9.5a: запрошення (міграція 20261128170000; ADR-021 §21.4, ADR-012 №5)
--   * код — 8 символів, один на акаунт, повторний виклик — той самий;
--   * активувати: чужий код, один раз, у перші 14 днів; свій / невідомий / заблокований — ні; гостю — можна;
--   * друзі — щойно запрошений має акаунт; гостю — ні;
--   * +10 обом — лише після першого походу; запрошувачу — до 5 разів; повторний cron не дублює;
--   * таблиці й функції — лише service_role.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email, is_anonymous, created_at) VALUES
  ('b8000001-0000-4000-8000-0000000098b1', 'inviter@test.local', false, now() - INTERVAL '90 days'),
  ('b8000002-0000-4000-8000-0000000098b2', 'invitee@test.local', false, now()),
  ('b8000003-0000-4000-8000-0000000098b3', NULL, true, now()),
  ('b8000004-0000-4000-8000-0000000098b4', 'old@test.local', false, now() - INTERVAL '30 days'),
  ('b8000005-0000-4000-8000-0000000098b5', 'blocked@test.local', false, now());
INSERT INTO auth.users (id, email, is_anonymous, created_at)
  SELECT ('b8100000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'inv' || g || '@test.local', false, now()
  FROM generate_series(1, 6) g;

SET LOCAL ROLE service_role;

DO $$
DECLARE
  inviter CONSTANT UUID := 'b8000001-0000-4000-8000-0000000098b1';
  invitee CONSTANT UUID := 'b8000002-0000-4000-8000-0000000098b2';
  guest   CONSTANT UUID := 'b8000003-0000-4000-8000-0000000098b3';
  old     CONSTANT UUID := 'b8000004-0000-4000-8000-0000000098b4';
  blk     CONSTANT UUID := 'b8000005-0000-4000-8000-0000000098b5';
  r JSONB; code TEXT; i INT; u UUID;
BEGIN
  UPDATE public.users SET handle = 'Запрошувач', handle_key = 'запрошувач' WHERE id = inviter;

  -- 1. код: 8 символів без 0/O/1/I, той самий при повторі
  r := public.my_referral_code(inviter);
  code := r->>'code';
  IF r->>'ok' <> 'true' OR code !~ '^[A-HJ-NP-Z2-9]{8}$' OR public.my_referral_code(inviter)->>'code' <> code
     OR (r->>'bonuses_left')::int <> 5 THEN
    RAISE EXCEPTION 'Test 1 failed: %', r;
  END IF;

  -- 2. відмови: невідомий, свій, старий акаунт, заблокований
  IF public.redeem_referral(invitee, 'ZZZZZZZZ')->>'code' <> 'invalid_code' THEN RAISE EXCEPTION 'Test 2a failed'; END IF;
  IF public.redeem_referral(inviter, code)->>'code' <> 'own_code' THEN RAISE EXCEPTION 'Test 2b failed'; END IF;
  IF public.redeem_referral(old, code)->>'code' <> 'too_late' THEN RAISE EXCEPTION 'Test 2c failed'; END IF;
  INSERT INTO public.friendships (user_a, user_b, status, requested_by, blocked_by)
  VALUES (LEAST(inviter, blk), GREATEST(inviter, blk), 'blocked', inviter, inviter);
  IF public.redeem_referral(blk, code)->>'code' <> 'invalid_code' THEN RAISE EXCEPTION 'Test 2d failed'; END IF;

  -- 3. активувати: малими літерами з пробілами — теж; удруге — already_redeemed
  r := public.redeem_referral(invitee, ' ' || lower(code) || ' ');
  IF r->>'ok' <> 'true' OR r->>'inviter_handle' <> 'Запрошувач' OR r->>'friends_now' <> 'true'
     OR NOT public.are_friends(inviter, invitee) THEN
    RAISE EXCEPTION 'Test 3a failed (account — friends at once): %', r;
  END IF;
  IF public.redeem_referral(invitee, code)->>'code' <> 'already_redeemed' THEN RAISE EXCEPTION 'Test 3b failed'; END IF;
  -- гість теж може активувати
  r := public.redeem_referral(guest, code);
  IF r->>'ok' <> 'true' OR r->>'friends_now' <> 'false' THEN RAISE EXCEPTION 'Test 3c failed: %', r; END IF;

  -- 4. cron: гість — досі не друг; бонусу ще немає (походу не було); після входу гостя — друзі
  PERFORM public.award_due_referrals();
  IF NOT public.are_friends(inviter, invitee) THEN RAISE EXCEPTION 'Test 4a failed: not friends'; END IF;
  IF public.are_friends(inviter, guest) THEN RAISE EXCEPTION 'Test 4b failed: guest became a friend'; END IF;
  IF EXISTS (SELECT 1 FROM public.rating_events WHERE reason = 'referral') THEN RAISE EXCEPTION 'Test 4c failed: bonus before a hike'; END IF;
END $$;

-- гість увійшов в акаунт (auth.users змінює лише Auth, не service_role)
RESET ROLE;
UPDATE auth.users SET is_anonymous = false, email = 'guest-now@test.local' WHERE id = 'b8000003-0000-4000-8000-0000000098b3';
SET LOCAL ROLE service_role;

DO $$
DECLARE
  inviter CONSTANT UUID := 'b8000001-0000-4000-8000-0000000098b1';
  invitee CONSTANT UUID := 'b8000002-0000-4000-8000-0000000098b2';
  guest   CONSTANT UUID := 'b8000003-0000-4000-8000-0000000098b3';
  code TEXT := public.my_referral_code('b8000001-0000-4000-8000-0000000098b1')->>'code';
  i INT; u UUID;
BEGIN
  PERFORM public.award_due_referrals();
  IF NOT public.are_friends(inviter, guest) THEN RAISE EXCEPTION 'Test 4d failed: signed-in guest not a friend'; END IF;

  -- 5. перший похід — +10 обом; повторний cron не дублює
  INSERT INTO public.hikes (owner_id, status, route, expected_return, closed_at, closed_reason)
  VALUES (invitee, 'closed', '[{"lat":50,"lng":24}]', now(), now(), 'home');
  PERFORM public.award_due_referrals();
  PERFORM public.award_due_referrals();
  IF (SELECT rating FROM public.users WHERE id = invitee) <> 10 OR (SELECT rating FROM public.users WHERE id = inviter) <> 10 THEN
    RAISE EXCEPTION 'Test 5 failed: ratings % / %',
      (SELECT rating FROM public.users WHERE id = invitee), (SELECT rating FROM public.users WHERE id = inviter);
  END IF;

  -- 6. запрошувач — щонайбільше 5 бонусів: ще 6 запрошених із походом → лише 4 нові для нього
  FOR i IN 1..6 LOOP
    u := ('b8100000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    PERFORM public.redeem_referral(u, code);
    INSERT INTO public.hikes (owner_id, status, route, expected_return, closed_at, closed_reason)
    VALUES (u, 'closed', '[{"lat":50,"lng":24}]', now(), now(), 'home');
  END LOOP;
  PERFORM public.award_due_referrals();
  IF (SELECT count(*) FROM public.rating_events WHERE user_id = inviter AND reason = 'referral') <> 5 THEN
    RAISE EXCEPTION 'Test 6a failed: inviter bonuses %', (SELECT count(*) FROM public.rating_events WHERE user_id = inviter AND reason = 'referral');
  END IF;
  IF (SELECT count(*) FROM public.rating_events WHERE reason = 'referral' AND user_id::text LIKE 'b8100000-%') <> 6 THEN
    RAISE EXCEPTION 'Test 6b failed: each invitee gets the bonus';
  END IF;
  IF (public.my_referral_code(inviter)->>'bonuses_left')::int <> 0 OR (public.my_referral_code(inviter)->>'invited')::int <> 8 THEN
    RAISE EXCEPTION 'Test 6c failed: %', public.my_referral_code(inviter);
  END IF;

  RAISE NOTICE 'OK запрошення: код, активація, друзі, бонус після походу, ліміт 5';
END $$;

-- 7. клієнт не бачить таблиць і не викликає функцій
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.referral_codes LIMIT 1;
    RAISE EXCEPTION 'Test 7a failed: authenticated reads referral_codes';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.redeem_referral('b8000002-0000-4000-8000-0000000098b2', 'ABCDEFGH');
    RAISE EXCEPTION 'Test 7b failed: authenticated can call redeem_referral';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK запрошення: лише service_role';
END $$;
RESET ROLE;

ROLLBACK;
