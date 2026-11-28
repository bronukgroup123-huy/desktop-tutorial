-- ============================================================================
-- SEC-008: у кожної таблиці схеми public увімкнено RLS (міграція 20261128160000)
--   * нова таблиця без ENABLE ROW LEVEL SECURITY — тест падає й називає її;
--   * службові таблиці (push-токени, журнали) — без прав для anon / authenticated;
--   * service_role (Edge Functions) читає їх і далі — BYPASSRLS.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

DO $$
DECLARE missing TEXT;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO missing
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL таблиці public без RLS: %', missing;
  END IF;

  IF has_table_privilege('anon', 'public.user_push_tokens', 'SELECT')
     OR has_table_privilege('authenticated', 'public.user_push_tokens', 'SELECT')
     OR has_table_privilege('authenticated', 'public.user_push_tokens', 'INSERT') THEN
    RAISE EXCEPTION 'FAIL user_push_tokens доступна клієнту';
  END IF;
  RAISE NOTICE 'OK RLS увімкнено на всіх таблицях public';
END $$;

-- service_role (BYPASSRLS) і далі бачить службові таблиці
SET LOCAL ROLE service_role;
DO $$
BEGIN
  PERFORM count(*) FROM public.user_push_tokens;
  PERFORM count(*) FROM public.forest_polygons;
  RAISE NOTICE 'OK service_role читає службові таблиці';
END $$;
RESET ROLE;

-- authenticated — ні (немає прав; тепер ще й RLS без політик)
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM count(*) FROM public.user_push_tokens;
    RAISE EXCEPTION 'FAIL authenticated читає user_push_tokens';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK authenticated не має доступу до push-токенів';
END $$;
RESET ROLE;

ROLLBACK;
