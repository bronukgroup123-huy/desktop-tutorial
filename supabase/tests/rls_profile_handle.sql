-- ============================================================================
-- Профіль: нік (міграція 20261118130000; ADR-021 §21.2.1)
--   * нік — лише українські літери (латиниця, ы/э/ъ/ё, цифра на початку — ні);
--   * один ключ ніка — один користувач;
--   * delete_user_account — лише service_role; видаляє користувача каскадом.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a1a1a1a1-0000-4000-8000-0000000041a1', 'p1@test.local'),
  ('b2b2b2b2-0000-4000-8000-0000000041b2', 'p2@test.local');

SET LOCAL ROLE service_role;

DO $$
DECLARE
  u1 CONSTANT UUID := 'a1a1a1a1-0000-4000-8000-0000000041a1';
  u2 CONSTANT UUID := 'b2b2b2b2-0000-4000-8000-0000000041b2';
  bad TEXT;
BEGIN
  UPDATE public.users SET handle = 'Олена_лісова', handle_key = 'олена_лісова', avatar = '{"kind":"standard","id":3}' WHERE id = u1;

  FOREACH bad IN ARRAY ARRAY['olena', 'Олeна', 'мыло', '1олена', 'ол'] LOOP
    BEGIN
      UPDATE public.users SET handle = bad, handle_key = lower(bad) WHERE id = u2;
      RAISE EXCEPTION 'Test 1 failed: handle % accepted', bad;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
  END LOOP;

  BEGIN
    UPDATE public.users SET handle = 'ОЛЕНА_ЛІСОВА', handle_key = 'олена_лісова' WHERE id = u2;
    RAISE EXCEPTION 'Test 2 failed: duplicate handle key accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  PERFORM public.delete_user_account(u1);
  IF EXISTS (SELECT 1 FROM public.users WHERE id = u1) OR EXISTS (SELECT 1 FROM auth.users WHERE id = u1) THEN
    RAISE EXCEPTION 'Test 3 failed: account not deleted';
  END IF;
END $$;

RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.delete_user_account('b2b2b2b2-0000-4000-8000-0000000041b2');
    RAISE EXCEPTION 'Test 4 failed: authenticated can delete accounts';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;
ROLLBACK;
