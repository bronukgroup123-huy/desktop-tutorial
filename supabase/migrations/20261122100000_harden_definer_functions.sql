-- ============================================================================
-- SEC-002: функції SECURITY DEFINER недоступні ролям API (docs/agent/AUDIT.md)
--
-- Міграція 20260911000006 відкликала права за замовчуванням лише на рівні схеми, а
-- глобальне право PostgreSQL «EXECUTE для PUBLIC» лишилося: кожна нова функція без явного
-- REVOKE FROM PUBLIC виконувана для anon і authenticated (через PUBLIC) — тобто через
-- PostgREST `POST /rest/v1/rpc/<функція>` з публічним anon-ключем.
--
-- Підтверджено на чистій БД з усіма міграціями (scripts/dev/local-db/run.sh):
--   * import_forest_zones_batch(jsonb) — адміністративний імпорт лісових ділянок, пише в
--     forest_zones від імені власника функції; без фіксованого search_path. Будь-хто з
--     anon-ключем міг підмінити дані, на яких рахується прогноз;
--   * check_forest_position, find_region_by_slug, find_zone_by_point, point_in_region —
--     важкі PostGIS-запити в обхід лімітів Edge Functions;
--   * тригерні check_expert_rules_safe, handle_new_user, notify_guardian_alert.
-- Усі виклики з сервера йдуть через service_role (`serviceClient()`, adminDb,
-- scripts/import-forests.ts) — йому право лишається.
-- ============================================================================

ALTER FUNCTION public.import_forest_zones_batch(jsonb) SET search_path = public, extensions, pg_temp;

DO $$
DECLARE
  fn regprocedure;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.prosecdef
      AND p.proname IN (
        'import_forest_zones_batch', 'check_forest_position', 'find_region_by_slug',
        'find_zone_by_point', 'point_in_region', 'check_expert_rules_safe',
        'handle_new_user', 'notify_guardian_alert'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END;
$$;
