-- ============================================================================
-- RLS: сесії Наглядача — користувач бачить і змінює тільки свої
-- Самодостатній тест: створює дані в транзакції і відкочує їх (ROLLBACK).
-- Запуск: psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_guardian_sessions.sql
-- ============================================================================

BEGIN;

-- Фікстури (роль міграцій — власник таблиць, RLS не застосовується)
INSERT INTO auth.users (id, email) VALUES
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'rls-a@test.local'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'rls-b@test.local');

INSERT INTO public.guardian_sessions (id, user_id, expected_return, original_return) VALUES
  ('5e550000-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-00000000000b',
   now() + interval '3 hours', now() + interval '3 hours');

-- Далі — від імені користувача A
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-00000000000a', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-00000000000a","role":"authenticated","is_anonymous":false}', true);

DO $$
DECLARE
  n INT;
BEGIN
  -- 1. A не бачить сесію B
  SELECT count(*) INTO n FROM public.guardian_sessions
  WHERE user_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  IF n <> 0 THEN RAISE EXCEPTION 'Test 1 failed: A sees % sessions of B', n; END IF;

  -- 2. A не може створити сесію від імені B
  BEGIN
    INSERT INTO public.guardian_sessions (user_id, expected_return, original_return)
    VALUES ('bbbbbbbb-0000-4000-8000-00000000000b', now() + interval '1 hour', now() + interval '1 hour');
    RAISE EXCEPTION 'Test 2 failed: A inserted a session for B';
  EXCEPTION WHEN insufficient_privilege THEN NULL; -- 42501: RLS заблокувала
  END;

  -- 3. A не може змінити сесію B (RLS приховує рядок → 0 оновлень)
  UPDATE public.guardian_sessions SET status = 'active'
  WHERE user_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'Test 3 failed: A updated % sessions of B', n; END IF;

  -- 4. A може створити власну сесію і бачить тільки її
  INSERT INTO public.guardian_sessions (user_id, expected_return, original_return)
  VALUES ('aaaaaaaa-0000-4000-8000-00000000000a', now() + interval '1 hour', now() + interval '1 hour');
  SELECT count(*) INTO n FROM public.guardian_sessions
  WHERE user_id <> 'aaaaaaaa-0000-4000-8000-00000000000a';
  IF n <> 0 THEN RAISE EXCEPTION 'Test 4 failed: A sees % foreign sessions', n; END IF;

  -- 5–7. Пов'язані таблиці B недоступні
  SELECT count(*) INTO n FROM public.guardians g
  JOIN public.guardian_sessions s ON s.id = g.session_id
  WHERE s.user_id = 'bbbbbbbb-0000-4000-8000-00000000000b';
  IF n <> 0 THEN RAISE EXCEPTION 'Test 5 failed'; END IF;

  SELECT count(*) INTO n FROM public.guardian_track t
  WHERE t.session_id = '5e550000-0000-4000-8000-00000000000b';
  IF n <> 0 THEN RAISE EXCEPTION 'Test 6 failed'; END IF;

  SELECT count(*) INTO n FROM public.guardian_alerts a
  WHERE a.session_id = '5e550000-0000-4000-8000-00000000000b';
  IF n <> 0 THEN RAISE EXCEPTION 'Test 7 failed'; END IF;

  RAISE NOTICE '✅ rls_guardian_sessions: all checks passed';
END $$;

ROLLBACK;
