-- ============================================================================
-- Demo-Guardian: seed demo-user + cron cleanup (group 8.8)
-- ============================================================================
-- Demo-user ...0d1 використовується публічною demo-кнопкою на лендінгу
-- (guardian-demo-create Edge Function, без реєстрації).
-- Фіксований UUID: читабельний, унікальний, зайнятий тільки demo.

INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-0000000000d1')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id) VALUES ('00000000-0000-0000-0000-0000000000d1')
ON CONFLICT (id) DO NOTHING;

-- Idempotent cron: cleanup старих demo-сесій кожні 30 хв (TTL 2h)
-- Патерн DO-блоку — як 20260911000007_cron_null_safe.sql
DO $$
DECLARE jid bigint;
BEGIN
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'guardian-demo-cleanup';
  IF jid IS NOT NULL THEN
    PERFORM cron.unschedule(jid);
  END IF;

  PERFORM cron.schedule(
    'guardian-demo-cleanup',
    '*/30 * * * *',
    $cleanup$
    DELETE FROM guardian_sessions
    WHERE settings->>'demo' = 'true'
      AND started_at < now() - interval '2 hours';
    $cleanup$
  );
END $$;
