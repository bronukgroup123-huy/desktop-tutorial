-- ============================================================================
-- Rate-limit cleanup cron (PC-TASK: G6 Fix 1 — Critical)
-- Вимикнено з audit G1-p2 A6 (конфлікт імен) → таблиця росла без обмежень.
-- Тепер: очистка раз на добу о 03:45 UTC, вікно 2 години.
-- ============================================================================

-- Прибрати стару версію (якщо існує) — ідемпотентно
DO $$
BEGIN
  PERFORM cron.unschedule('notification-rate-limit-cleanup');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'notification-rate-limit-cleanup',
  '45 3 * * *',
  $$
    DELETE FROM notification_rate_limit
    WHERE window_start < now() - interval '2 hours';
  $$
);

COMMENT ON TABLE notification_rate_limit IS
  'Rate-limit лічильники (per user+channel+hour). Cleanup щодня о 03:45 UTC, вікно 2 години (PC-TASK G6).';
