-- ============================================================================
-- SEC-002 (регресія): жодна функція SECURITY DEFINER у public не виконувана ролями API
-- (anon, authenticated) і кожна має фіксований search_path. Нова функція без
-- REVOKE ... FROM PUBLIC, anon, authenticated — падіння цього тесту в CI.
-- Свідомі винятки — лише явним списком нижче (зараз порожній).
-- ============================================================================
DO $$
DECLARE
  allowed CONSTANT text[] := ARRAY[]::text[];
  r record;
  bad text := '';
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS fn,
           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_x,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_x,
           EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%') AS has_path
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef
  LOOP
    IF (r.anon_x OR r.auth_x) AND NOT r.fn = ANY (allowed) THEN
      bad := bad || format(E'\n  %s виконувана для%s%s', r.fn,
        CASE WHEN r.anon_x THEN ' anon' ELSE '' END, CASE WHEN r.auth_x THEN ' authenticated' ELSE '' END);
    END IF;
    IF NOT r.has_path THEN
      bad := bad || format(E'\n  %s без фіксованого search_path', r.fn);
    END IF;
  END LOOP;
  IF bad <> '' THEN
    RAISE EXCEPTION 'FAIL SECURITY DEFINER:%', bad;
  END IF;
  -- service_role, як і раніше, може викликати адміністративний імпорт
  IF NOT has_function_privilege('service_role', 'public.import_forest_zones_batch(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL service_role втратив import_forest_zones_batch';
  END IF;
  RAISE NOTICE 'OK SECURITY DEFINER: недоступні ролям API, search_path зафіксовано';
END;
$$;

-- Як це виглядає для зловмисника: anon не може викликати імпорт навіть з порожнім масивом.
SET ROLE anon;
DO $$
BEGIN
  PERFORM public.import_forest_zones_batch('[]'::jsonb);
  RAISE EXCEPTION 'FAIL anon викликав import_forest_zones_batch';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'OK anon → permission denied';
END;
$$;
RESET ROLE;
