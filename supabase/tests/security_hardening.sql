-- ============================================================================
-- Tests for 20260912000017_security_hardening.sql
-- ============================================================================
-- Перевіряє: (1) відсутність grants anon/authenticated на 4 таблиці,
--            (2) FORCE RLS на 4 таблицях,
--            (3) WITH CHECK у 3 UPDATE-політик.

DO $$
DECLARE
  cnt INT;
BEGIN
  -- 1. anon/authenticated НЕ мають жодних grants на 4 таблиці
  SELECT COUNT(*) INTO cnt
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name IN ('guardian_push_tokens', 'user_push_tokens',
                       'forest_polygons', 'guardian_tick_log')
    AND grantee IN ('anon', 'authenticated');
  IF cnt > 0 THEN
    RAISE EXCEPTION 'anon/authenticated still have % grants on service-only tables', cnt;
  END IF;

  -- 2. FORCE RLS увімкнено на 4 таблицях
  SELECT COUNT(*) INTO cnt
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('guardian_push_tokens', 'user_push_tokens',
                      'forest_polygons', 'guardian_tick_log')
    AND c.relforcerowsecurity = false;
  IF cnt > 0 THEN
    RAISE EXCEPTION 'FORCE RLS not enabled on % tables', cnt;
  END IF;

  -- 3. UPDATE-політики мають WITH CHECK
  SELECT COUNT(*) INTO cnt
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND p.polname IN ('users_self_update', 'guardians_owner_update',
                      'guardian_rescue_owner_update')
    AND p.polwithcheck IS NULL;
  IF cnt > 0 THEN
    RAISE EXCEPTION '% policies missing WITH CHECK', cnt;
  END IF;

  RAISE NOTICE '✅ security_hardening: all checks passed';
END $$;
