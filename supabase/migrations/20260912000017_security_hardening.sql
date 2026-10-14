-- ============================================================================
-- Security Hardening — Audit B fix
-- ============================================================================
-- Результати live-SQL перевірок (аудит B):
--   RLS увімкнено на 15/19 таблиць; 4 таблиці (guardian_push_tokens,
--   user_push_tokens, forest_polygons, guardian_tick_log) мають RLS без політик
--   (deny-all), але з залишковими GRANT ALL від anon/authenticated
--   (стандартні Supabase default privileges, не з міграцій цього репо).
--
--   rolbypassrls: service_role=true, postgres=true, anon/authenticated=false
--   → FORCE ROW LEVEL SECURITY не вплине на Edge Functions (service_role).
--
--   Клієнт (web-guardian) не звертається до цих 4 таблиць напряму —
--   усі операції лише через Edge Functions з service_role key.
--   Тому: REVOKE (без нових GRANT/політик).
--
--   notify_guardian_alert вже має SET search_path = public, vault
--   (див. 20260911000007_cron_null_safe.sql) — окреме ALTER не потрібен.
--
--   UPDATE-політики users_self_update / guardians_owner_update /
--   guardian_rescue_owner_update мали лише USING (Postgres за замовчуванням
--   застосовує USING і як WITH CHECK, тобто реальної вразливості не було) —
--   додаємо явний WITH CHECK як defense/clarity.
-- ============================================================================

-- ============================================================================
-- 1. REVOKE ALL — прибрати залишкові Supabase default grants
--    (жодних нових GRANT: таблиці лишаються service_role-only)
-- ============================================================================

REVOKE ALL ON public.guardian_push_tokens FROM anon, authenticated;
REVOKE ALL ON public.user_push_tokens     FROM anon, authenticated;
REVOKE ALL ON public.forest_polygons      FROM anon, authenticated;
REVOKE ALL ON public.guardian_tick_log    FROM anon, authenticated;

-- ============================================================================
-- 2. FORCE ROW LEVEL SECURITY — defense in depth
--    (service_role має rolbypassrls=true → не постраждає;
--     cron jobs не торкаються цих таблиць на рівні DB)
-- ============================================================================

ALTER TABLE public.guardian_push_tokens FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_push_tokens     FORCE ROW LEVEL SECURITY;
ALTER TABLE public.forest_polygons      FORCE ROW LEVEL SECURITY;
ALTER TABLE public.guardian_tick_log    FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. WITH CHECK для 3 UPDATE-політик (hardening/clarity)
--    USING не змінюється (реальної вразливості не було)
--    CREATE OR REPLACE POLICY не існує в Postgres (перевірено по PG17 docs):
--    fallback DROP + CREATE — безпечно, бо міграція виконується в одній
--    транзакції (вікна без політики для інших транзакцій немає).
-- ============================================================================

DROP POLICY IF EXISTS users_self_update ON public.users;
CREATE POLICY users_self_update ON public.users
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS guardians_owner_update ON public.guardians;
CREATE POLICY guardians_owner_update ON public.guardians
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardians.session_id
        AND s.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardians.session_id
        AND s.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS guardian_rescue_owner_update ON public.guardian_rescue_requests;
CREATE POLICY guardian_rescue_owner_update ON public.guardian_rescue_requests
  FOR UPDATE
  USING (auth.uid() = created_by)
  WITH CHECK (auth.uid() = created_by);

-- ============================================================================
-- 4. Документування: notify_guardian_alert вже має search_path
-- ============================================================================

COMMENT ON FUNCTION public.notify_guardian_alert() IS
  'Trigger → net.http_post на guardian-notify. search_path = public, vault '
  'встановлено в 20260911000007_cron_null_safe.sql.';
