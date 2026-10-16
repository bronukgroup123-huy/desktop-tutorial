-- ============================================================================
-- Cron timeout hardening + rename (PC-TASK: G6 Fix 2+3)
-- guardian-tick + guardian-retry: net.http_post з timeout_milliseconds=50000
-- (менше cron interval 60 сек, щоб не блокувати слот навеки).
-- guardian-retry-every-30s → guardian-retry-every-minute (місleading назва).
-- ============================================================================

-- guardian-tick: перестворення з timeout
DO $$
BEGIN
  PERFORM cron.unschedule('guardian-tick-every-minute');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'guardian-tick-every-minute',
  '* * * * *',
  $$
    SELECT net.http_post(
      url := (SELECT url FROM public.guardian_fn_config()) || '/functions/v1/guardian-tick',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT service_key FROM public.guardian_fn_config())
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 50000
    )
    WHERE EXISTS (
      SELECT 1 FROM public.guardian_fn_config()
      WHERE url IS NOT NULL AND service_key IS NOT NULL
    );
  $$
);

-- guardian-retry: перестворення з timeout та правильною назвою
DO $$
BEGIN
  PERFORM cron.unschedule('guardian-retry-every-30s');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('guardian-retry-every-minute');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'guardian-retry-every-minute',
  '* * * * *',
  $$
    SELECT net.http_post(
      url := (SELECT url FROM public.guardian_fn_config()) || '/functions/v1/guardian-retry',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT service_key FROM public.guardian_fn_config())
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 50000
    )
    WHERE EXISTS (
      SELECT 1 FROM public.guardian_fn_config()
      WHERE url IS NOT NULL AND service_key IS NOT NULL
    );
  $$
);

COMMENT ON TABLE notification_rate_limit IS
  'Rate-limit лічильники (per user+channel+hour). Cleanup див. маніфест 20260912000023 (PC-TASK G6).';
