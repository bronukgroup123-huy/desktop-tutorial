-- ============================================================================
-- SEC-005: застарілий Guardian v0 більше не викликається з бази (ADR-022)
--
-- Edge Functions guardian-tick / guardian-retry / guardian-notify видаляються з проєкту
-- (deploy.yml). Тут — те, що їх викликало: cron-задачі (щохвилини) і тригер на
-- guardian_alerts, що слав pg_net-запит на guardian-notify. Наглядач у застосунку працює
-- через v1-guardian-tick (задача 'v1-guardian-tick' лишається).
-- Таблиці Guardian v0 (guardian_sessions, guardians, guardian_track, …) НЕ видаляються:
-- зберігання/видалення цих даних — рішення власника (docs/agent/BLOCKERS.md, BLK-009).
-- ============================================================================

DO $$
DECLARE
  j record;
BEGIN
  FOR j IN
    SELECT jobid, jobname FROM cron.job
    WHERE jobname IN ('guardian-tick-every-minute', 'guardian-retry-every-minute', 'guardian-retry-every-30s')
       OR command ~ '/functions/v1/guardian-(tick|retry|notify)\M'
  LOOP
    PERFORM cron.unschedule(j.jobid);
    RAISE NOTICE 'unscheduled %', j.jobname;
  END LOOP;
END;
$$;

DROP TRIGGER IF EXISTS guardian_alert_notify_trigger ON public.guardian_alerts;
DROP FUNCTION IF EXISTS public.notify_guardian_alert();
