-- ============================================================================
-- Formalize rls_auto_enable() + event trigger (audit E — Schema Drift)
-- ============================================================================
-- ПРОБЛЕМА (audit E):
--   Функція public.rls_auto_enable() та її event trigger існували в ЖИВІЙ БД,
--   але НЕ були описані в жодній міграції — створені вручну через Dashboard
--   2026-09-11. Побічні ефекти: (1) fresh-deploy не відтворює структуру БД,
--   (2) RLS на нових таблицях умикався "невидимо" для git-історії.
--   Міграція 20260911000006 лише REVOKE-ила EXECUTE (guarded) — сама функція
--   так і залишалась поза контролем версій.
--
-- РІШЕННЯ: формалізувати функцію + event trigger ідемпотентно:
--   * тіло функції — VERBATIM з живої БД (pg_get_functiondef);
--   * owner → postgres (як у живій БД);
--   * ACL відтворює живий стан: {postgres=ALL, service_role=EXECUTE};
--   * усі event triggers, прив'язані до цієї функції, дропаються (захист від
--     дублів, якщо оригінальний тригер мав інше ім'я), потім створюється
--     канонічний `ensure_rls` ON ddl_command_end (без WHEN TAG — як оригінал:
--     функція сама фільтрує command_tag/object_type у циклі).
--
-- БЕЗПЕКА: виконується в одній транзакції (Supabase migration) — між
-- DROP і CREATE event trigger немає вікна для інших транзакцій.
-- ============================================================================

-- ─── 1. Функція (VERBATIM з живої БД, audit E) ─────────────────────────────

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

-- ─── 2. Owner — як у живій БД (proowner = postgres) ─────────────────────────

ALTER FUNCTION public.rls_auto_enable() OWNER TO postgres;

-- ─── 3. ACL — відтворює живий стан {postgres=ALL, service_role=EXECUTE} ─────
-- CREATE OR REPLACE скидає привілеї до дефолтних — ревок/грант після OR REPLACE.
-- (Це також дублює сенс міграції 20260911000006_revoke_rls_auto_enable.)

REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rls_auto_enable() TO service_role;

-- ─── 4. Event trigger ────────────────────────────────────────────────────────
-- CREATE/DROP EVENT TRIGGER потребує суперкористувача. На хостингу Supabase тригер
-- уже існує (створений у Dashboard 2026-09-11), а на чистій локальній БД / у CI
-- роль міграцій не має цих прав. Тому блок виконується лише за наявності прав:
-- при insufficient_privilege міграція не падає, а пише NOTICE (B0.9).
-- Ловимо ТІЛЬКИ insufficient_privilege — будь-яка інша помилка, як і раніше, валить
-- міграцію. Функція rls_auto_enable() (крок 1–3) створюється в будь-якому разі.
--
-- 4a. Дроп усіх event triggers, прив'язаних до цієї функції (захист від дублів,
--     якщо оригінальний тригер мав інше ім'я, ніж ensure_rls).
-- 4b. Канонічний event trigger ensure_rls ON ddl_command_end (без WHEN TAG — як
--     в оригіналі: функція фільтрує команди сама).

DO $$
DECLARE
  ev record;
BEGIN
  FOR ev IN
    SELECT evtname
    FROM pg_event_trigger
    WHERE evtfoid = 'public.rls_auto_enable()'::regprocedure
  LOOP
    EXECUTE format('DROP EVENT TRIGGER %I', ev.evtname);
    RAISE LOG 'rls_auto_enable: dropped old event trigger %', ev.evtname;
  END LOOP;

  EXECUTE 'DROP EVENT TRIGGER IF EXISTS ensure_rls';
  EXECUTE 'CREATE EVENT TRIGGER ensure_rls ON ddl_command_end '
       || 'EXECUTE FUNCTION public.rls_auto_enable()';
  EXECUTE 'ALTER EVENT TRIGGER ensure_rls OWNER TO postgres';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'rls_auto_enable: no privilege to manage event trigger ensure_rls (local/CI database) — skipped';
END $$;

-- ─── 5. Коментар (прозорість для наступних аудитів) ──────────────────────────

COMMENT ON FUNCTION public.rls_auto_enable() IS
  'Auto-enable RLS on new public tables (formalized from Dashboard, audit E). Created manually 2026-09-11, formalized 2026-10-14.';
