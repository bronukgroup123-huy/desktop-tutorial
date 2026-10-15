-- ============================================================================
-- Rate limiting для нотифікацій (audit G3, Phase B)
-- Захист від SMS-фроду/спаму: атомарний UPSERT (race-safe).
-- ============================================================================

CREATE TABLE notification_rate_limit (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('sms', 'telegram')),

  -- Транковане початок вікна (для yearly/hourly діапазонів)
  window_start TIMESTAMPTZ NOT NULL,
  count INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (user_id, channel, window_start)
);

CREATE INDEX notification_rate_limit_lookup_idx
  ON notification_rate_limit (user_id, channel, window_start DESC);

-- Auto-cleanup: вікна старіші 7 днів непотрібні
CREATE INDEX notification_rate_limit_cleanup_idx
  ON notification_rate_limit (window_start);

-- RLS: тільки service_role (edge functions). Ніякого доступу для anon/authenticated.
ALTER TABLE notification_rate_limit ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RPC: атомарний інкремент (використовується rate-limit.ts)
-- ============================================================================

CREATE OR REPLACE FUNCTION check_and_increment_rate_limit(
  p_user_id UUID,
  p_channel TEXT,
  p_window_start TIMESTAMPTZ
)
RETURNS TABLE (count INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  INSERT INTO notification_rate_limit (user_id, channel, window_start)
  VALUES (p_user_id, p_channel, p_window_start)
  ON CONFLICT (user_id, channel, window_start)
  DO UPDATE SET
    count = notification_rate_limit.count + 1,
    updated_at = now()
  RETURNING notification_rate_limit.count;
END;
$$;

-- Тільки service_role
REVOKE ALL ON FUNCTION check_and_increment_rate_limit(UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION check_and_increment_rate_limit(UUID, TEXT, TIMESTAMPTZ)
  TO service_role;

-- ============================================================================
-- Cleanup cron: видалити вікна старіші 7 днів (раз на добу о 03:45 UTC)
-- Використовуємо обережно, бо cron job naming може конфліктувати.
-- Закоментовано до вирішення питання cron naming (audit G1-p2 A6).
-- ============================================================================
-- PERFORM cron.schedule(
--   'notification-rate-limit-cleanup-daily',
--   '45 3 * * *',
--   $$DELETE FROM notification_rate_limit WHERE window_start < now() - INTERVAL '7 days'$$
-- );

COMMENT ON TABLE notification_rate_limit IS
  'Rate limit лічильники нотифікацій (audit G3 Phase B). Foreign key to auth.users навмисно відсутній.';
