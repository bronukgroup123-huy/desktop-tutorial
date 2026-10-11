-- ============================================================================
-- Fix: cron jobs config via Supabase Vault
-- ============================================================================
-- Попередня версія читала GUC app.settings.* — Supabase блокує їх
-- встановлення (42501 permission denied), тому параметри завжди NULL
-- і cron/тригер тихо пропускали всі запуски.
--
-- Тепер конфіг читається з Supabase Vault (наповнений вручну):
--   - guardian_supabase_url      (URL проєкту, не секрет)
--   - guardian_service_role_key  (service_role key, зашифрований)
--
-- ПРИМІТКА: helper має SECURITY DEFINER, бо vault.decrypted_secrets
-- доступний лише postgres/supabase_admin, а cron pg_net працює
-- від іншої ролі.

-- ============================================================================
-- 0. Гарантуємо наявність Vault (no-op, якщо вже встановлено)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

-- ============================================================================
-- 1. Helper: конфіг для Edge Functions (читає з Vault)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guardian_fn_config()
RETURNS TABLE (url TEXT, service_key TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, vault
AS $fn$
  SELECT
    (SELECT decrypted_secret FROM vault.decrypted_secrets
     WHERE name = 'guardian_supabase_url') AS url,
    (SELECT decrypted_secret FROM vault.decrypted_secrets
     WHERE name = 'guardian_service_role_key') AS service_key;
$fn$;

COMMENT ON FUNCTION public.guardian_fn_config() IS
  'url + service_role_key для виклику Edge Functions з cron/pg_net. '
  'Читає з Supabase Vault. SECURITY DEFINER — бо vault.decrypted_secrets '
  'не доступний anon/authenticated.';

-- Обмежити прямий доступ — тільки через SECURITY DEFINER
REVOKE ALL ON FUNCTION public.guardian_fn_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.guardian_fn_config() TO postgres, service_role;

-- ============================================================================
-- 2. Перестворити cron jobs з NULL-safe тілом
-- ============================================================================

DO $do$
DECLARE
  jid bigint;
BEGIN
  -- guardian-tick
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'guardian-tick-every-minute';
  IF jid IS NOT NULL THEN
    PERFORM cron.unschedule(jid);
  END IF;

  PERFORM cron.schedule(
    'guardian-tick-every-minute',
    '* * * * *',
    $tick$
    SELECT net.http_post(
      url := (SELECT url FROM public.guardian_fn_config()) || '/functions/v1/guardian-tick',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT service_key FROM public.guardian_fn_config())
      ),
      body := '{}'::jsonb
    )
    WHERE (SELECT service_key FROM public.guardian_fn_config()) IS NOT NULL
      AND (SELECT url FROM public.guardian_fn_config()) IS NOT NULL;
    $tick$
  );

  -- guardian-retry
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'guardian-retry-every-30s';
  IF jid IS NOT NULL THEN
    PERFORM cron.unschedule(jid);
  END IF;

  PERFORM cron.schedule(
    'guardian-retry-every-30s',
    '* * * * *',
    $retry$
    SELECT net.http_post(
      url := (SELECT url FROM public.guardian_fn_config()) || '/functions/v1/guardian-retry',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT service_key FROM public.guardian_fn_config())
      ),
      body := '{}'::jsonb
    )
    WHERE (SELECT service_key FROM public.guardian_fn_config()) IS NOT NULL
      AND (SELECT url FROM public.guardian_fn_config()) IS NOT NULL;
    $retry$
  );
END;
$do$;

-- ============================================================================
-- 3. Тригер notify_guardian_alert — на helper
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_guardian_alert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $trg$
BEGIN
  IF (SELECT service_key FROM public.guardian_fn_config()) IS NULL
     OR (SELECT url FROM public.guardian_fn_config()) IS NULL THEN
    RETURN NEW;  -- Vault не наповнений — тихо пропускаємо
  END IF;

  PERFORM net.http_post(
    url := (SELECT url FROM public.guardian_fn_config()) || '/functions/v1/guardian-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT service_key FROM public.guardian_fn_config())
    ),
    body := jsonb_build_object('alert_id', NEW.id)
  );

  RETURN NEW;
END;
$trg$;
