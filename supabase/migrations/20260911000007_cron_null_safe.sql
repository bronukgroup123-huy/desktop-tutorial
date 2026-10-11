-- ============================================================================
-- Fix: cron jobs NULL-safe config (guardian-tick / guardian-retry)
-- ============================================================================
-- Причина падіння (job_run_details = failed щохвилини):
--   ERROR: unrecognized configuration parameter "app.settings.supabase_url"
--
-- cron.schedule()-тіла в міграціях 20260911000003 та ...004 читали
-- current_setting('app.settings.supabase_url') БЕЗ флага missing_ok=true,
-- а GUC app.settings.supabase_url / app.settings.service_role_key
-- ніде не встановлювались → кожен запуск job падав.
--
-- Ця міграція:
--   1. Створює helper public.guardian_fn_config() — читає GUC безопасно
--      (missing_ok=true), URL має дефолт для цього проєкту (не секрет),
--      service_role_key беруться ТІЛЬКИ з GUC (жодних секретів у git).
--   2. Перестворює обидва cron jobs з NULL-safe командою: якщо ключ не
--      виставлено — job тихо пропускає запуск замість ERROR щохвилини.
--
-- ЩО ПОТРІБНО ЗРОБИТИ ОДИН РАЗ (вручну, SQL Editor, як postgres):
--   ALTER DATABASE postgres SET app.settings.service_role_key = '<key>';
-- (url має дефолт у helper, але можна перевизначити тим же ALTER DATABASE)
--
-- ALTER DATABASE SET застосовується лише до НОВИХ з'єднань — нові
-- запуски cron відкривають нові сесії, тому підхоплять значення
-- протягом 1 хвилини.
--
-- ПРИМІТКА: зовнішній DO-блок використовує тег $do$ (не $$), бо
-- cron.schedule()-тіла всередині самі використовують $$.

-- ============================================================================
-- 1. Helper: конфіг для Edge Functions
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guardian_fn_config()
RETURNS TABLE (url TEXT, service_key TEXT)
LANGUAGE sql
STABLE
AS $fn$
  SELECT
    COALESCE(
      current_setting('app.settings.supabase_url', true),
      'https://wrukmuxdbkbmkygfasai.supabase.co'
    ) AS url,
    current_setting('app.settings.service_role_key', true) AS service_key;
$fn$;

COMMENT ON FUNCTION public.guardian_fn_config() IS
  'url + service_role_key для виклику Edge Functions з cron/pg_net. '
  'service_key — тільки з GUC app.settings.service_role_key (ніколи у git).';

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
    WHERE (SELECT service_key FROM public.guardian_fn_config()) IS NOT NULL;
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
    WHERE (SELECT service_key FROM public.guardian_fn_config()) IS NOT NULL;
    $retry$
  );
END;
$do$;

-- ============================================================================
-- 3. Тригер notify_guardian_alert — на helper (targeting the same config)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_guardian_alert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $trg$
BEGIN
  IF (SELECT service_key FROM public.guardian_fn_config()) IS NULL THEN
    RETURN NEW;  -- канал вимкнено — тихо пропускаємо
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
