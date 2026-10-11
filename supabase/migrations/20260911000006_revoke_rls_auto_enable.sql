-- ============================================================================
-- Revoke EXECUTE on rls_auto_enable from anon/authenticated/PUBLIC
-- Defensive: функція може не існувати (створена вручну в Dashboard),
-- тому REVOKE виконуємо тільки якщо вона є.
-- ============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'rls_auto_enable'
      AND pronamespace = 'public'::regnamespace
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon;
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM authenticated;
  END IF;
END;
$$;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated, PUBLIC;
