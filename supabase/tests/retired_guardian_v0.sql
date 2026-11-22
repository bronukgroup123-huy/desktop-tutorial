-- ============================================================================
-- SEC-005 (регресія): база не викликає видалені Edge Functions Guardian v0.
-- ============================================================================
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM cron.job
  WHERE command ~ '/functions/v1/(guardian-(tick|retry|notify|demo-create)|forecast-weather)\M';
  IF n > 0 THEN
    RAISE EXCEPTION 'FAIL % cron-задач викликають видалені функції', n;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'guardian_alert_notify_trigger') THEN
    RAISE EXCEPTION 'FAIL тригер guardian_alert_notify_trigger лишився';
  END IF;
  IF to_regprocedure('public.notify_guardian_alert()') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL функція notify_guardian_alert лишилась';
  END IF;
  -- Наглядач у застосунку (ADR-022) працює далі
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'v1-guardian-tick') THEN
    RAISE EXCEPTION 'FAIL зникла задача v1-guardian-tick';
  END IF;
  RAISE NOTICE 'OK Guardian v0: cron і тригер прибрано, v1-guardian-tick на місці';
END;
$$;
