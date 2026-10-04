-- ============================================================================
-- Guardian Module — Notifications Migration
-- ============================================================================

-- ============================================================================
-- user_push_tokens — FCM токени грибника (мобільний)
-- ============================================================================

CREATE TABLE user_push_tokens (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  fcm_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),

  device_info JSONB DEFAULT '{}'::jsonb,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX user_push_tokens_fcm_idx
  ON user_push_tokens (fcm_token)
  WHERE revoked_at IS NULL;

CREATE INDEX user_push_tokens_user_idx
  ON user_push_tokens (user_id)
  WHERE revoked_at IS NULL;

-- ============================================================================
-- guardian_push_tokens — FCM токени Наглядача (Web Push)
-- ============================================================================

CREATE TABLE guardian_push_tokens (
  id BIGSERIAL PRIMARY KEY,
  guardian_id UUID NOT NULL REFERENCES guardians(id) ON DELETE CASCADE,

  fcm_token TEXT NOT NULL,
  user_agent TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX guardian_push_tokens_fcm_idx
  ON guardian_push_tokens (fcm_token)
  WHERE revoked_at IS NULL;

CREATE INDEX guardian_push_tokens_guardian_idx
  ON guardian_push_tokens (guardian_id)
  WHERE revoked_at IS NULL;

-- ============================================================================
-- Тригер на guardian_alerts → виклик guardian-notify
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_guardian_alert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url TEXT;
  v_key TEXT;
BEGIN
  v_url := current_setting('app.settings.supabase_url', true);
  v_key := current_setting('app.settings.service_role_key', true);

  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/guardian-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object('alert_id', NEW.id)
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER guardian_alert_notify_trigger
  AFTER INSERT ON guardian_alerts
  FOR EACH ROW
  EXECUTE FUNCTION notify_guardian_alert();

-- ============================================================================
-- Cron job: guardian-retry кожні 30 сек
-- ============================================================================

SELECT cron.schedule(
  'guardian-retry-every-30s',
  '* * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/guardian-retry',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  );
  $$
);

-- ============================================================================
-- Індекси для швидкого сканування черги
-- ============================================================================

CREATE INDEX IF NOT EXISTS guardian_notifications_pending_idx
  ON guardian_notifications (created_at ASC)
  WHERE status = 'queued';

CREATE INDEX IF NOT EXISTS guardian_notifications_sent_idx
  ON guardian_notifications (sent_at ASC)
  WHERE status = 'sent' AND delivered_at IS NULL;
