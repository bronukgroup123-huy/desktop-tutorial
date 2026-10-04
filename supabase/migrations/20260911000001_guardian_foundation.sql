-- ============================================================================
-- Guardian Module — Foundation Migration
-- 5 tables: guardian_sessions, guardians, guardian_track, guardian_alerts, guardian_notifications
-- ============================================================================

-- ============================================================================
-- 1. guardian_sessions
-- ============================================================================
CREATE TABLE guardian_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'pending', 'active', 'stale', 'offline',
      'exiting', 'overdue_soft', 'overdue_medium', 'overdue_hard',
      'sos', 'closing', 'closed'
    )),

  expected_return TIMESTAMPTZ NOT NULL,
  original_return TIMESTAMPTZ NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closing_started_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  recoverable_until TIMESTAMPTZ,

  last_known_coords GEOGRAPHY(Point, 4326),
  last_known_at TIMESTAMPTZ,
  last_battery_pct INT CHECK (last_battery_pct BETWEEN 0 AND 100),
  last_signal_strength INT CHECK (last_signal_strength BETWEEN 0 AND 5),

  exit_detected_at TIMESTAMPTZ,
  sos_activated_at TIMESTAMPTZ,
  overdue_level TEXT CHECK (overdue_level IN ('soft', 'medium', 'hard')),

  settings JSONB NOT NULL DEFAULT '{
    "overdue_thresholds": {"soft": 0, "medium": 30, "hard": 90},
    "stationary_threshold_min": 30,
    "offline_threshold_min": 60,
    "grace_period_min": 5,
    "recovery_window_min": 30
  }'::jsonb,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX guardian_sessions_user_idx ON guardian_sessions (user_id);
CREATE INDEX guardian_sessions_status_idx ON guardian_sessions (status);
CREATE INDEX guardian_sessions_active_idx ON guardian_sessions (status)
  WHERE status NOT IN ('closed');
CREATE INDEX guardian_sessions_coords_idx ON guardian_sessions
  USING GIST (last_known_coords)
  WHERE last_known_coords IS NOT NULL;

CREATE TRIGGER guardian_sessions_updated_at
  BEFORE UPDATE ON guardian_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 2. guardians
-- ============================================================================
CREATE TABLE guardians (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES guardian_sessions(id) ON DELETE CASCADE,

  name TEXT,
  phone TEXT,

  token_hash TEXT NOT NULL UNIQUE,
  token_prefix TEXT NOT NULL,

  is_emergency BOOLEAN NOT NULL DEFAULT FALSE,

  notified_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX guardians_session_idx ON guardians (session_id);
CREATE INDEX guardians_token_hash_idx ON guardians (token_hash);
CREATE INDEX guardians_active_idx ON guardians (session_id)
  WHERE revoked_at IS NULL;

-- ============================================================================
-- 3. guardian_track
-- ============================================================================
CREATE TABLE guardian_track (
  id BIGSERIAL PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES guardian_sessions(id) ON DELETE CASCADE,

  coords GEOGRAPHY(Point, 4326) NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL,

  battery_pct INT CHECK (battery_pct BETWEEN 0 AND 100),
  signal_strength INT CHECK (signal_strength BETWEEN 0 AND 5),
  speed_kmh NUMERIC(4,1) CHECK (speed_kmh >= 0),

  was_offline BOOLEAN NOT NULL DEFAULT FALSE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX guardian_track_session_idx ON guardian_track (session_id, recorded_at DESC);
CREATE INDEX guardian_track_coords_idx ON guardian_track USING GIST (coords);
CREATE INDEX guardian_track_time_idx ON guardian_track (recorded_at DESC);

-- ============================================================================
-- 4. guardian_alerts
-- ============================================================================
CREATE TABLE guardian_alerts (
  id BIGSERIAL PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES guardian_sessions(id) ON DELETE CASCADE,

  alert_type TEXT NOT NULL CHECK (alert_type IN (
    'sos',
    'overdue_soft', 'overdue_medium', 'overdue_hard',
    'offline', 'stationary', 'exit', 'battery_low',
    'closing', 'closed', 'recovered'
  )),

  payload JSONB NOT NULL DEFAULT '{}'::jsonb,

  delivered_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX guardian_alerts_session_idx ON guardian_alerts (session_id, created_at DESC);
CREATE INDEX guardian_alerts_type_idx ON guardian_alerts (alert_type, created_at DESC);

-- ============================================================================
-- 5. guardian_notifications
-- ============================================================================
CREATE TABLE guardian_notifications (
  id BIGSERIAL PRIMARY KEY,
  guardian_id UUID NOT NULL REFERENCES guardians(id) ON DELETE CASCADE,
  alert_id BIGINT REFERENCES guardian_alerts(id) ON DELETE SET NULL,

  channel TEXT NOT NULL CHECK (channel IN ('push', 'sms')),
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'delivered', 'failed', 'skipped')),

  provider_message_id TEXT,
  error_message TEXT,

  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX guardian_notifications_guardian_idx ON guardian_notifications (guardian_id, created_at DESC);
CREATE INDEX guardian_notifications_alert_idx ON guardian_notifications (alert_id);
CREATE INDEX guardian_notifications_status_idx ON guardian_notifications (status)
  WHERE status IN ('queued', 'sent');

-- ============================================================================
-- 6. Допоміжна функція для updated_at (якщо ще немає)
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. RLS-політики
-- ============================================================================

-- guardian_sessions
ALTER TABLE guardian_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY guardian_sessions_self_read ON guardian_sessions
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY guardian_sessions_self_insert ON guardian_sessions
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY guardian_sessions_self_update ON guardian_sessions
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- guardians
ALTER TABLE guardians ENABLE ROW LEVEL SECURITY;

CREATE POLICY guardians_owner_read ON guardians
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardians.session_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY guardians_owner_insert ON guardians
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardians.session_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY guardians_owner_update ON guardians
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardians.session_id
        AND s.user_id = auth.uid()
    )
  );

-- guardian_track
ALTER TABLE guardian_track ENABLE ROW LEVEL SECURITY;

CREATE POLICY guardian_track_owner_read ON guardian_track
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardian_track.session_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY guardian_track_owner_insert ON guardian_track
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardian_track.session_id
        AND s.user_id = auth.uid()
    )
  );

-- guardian_alerts
ALTER TABLE guardian_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY guardian_alerts_owner_read ON guardian_alerts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardian_alerts.session_id
        AND s.user_id = auth.uid()
    )
  );

-- guardian_notifications
ALTER TABLE guardian_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY guardian_notifications_owner_read ON guardian_notifications
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM guardians g
      JOIN guardian_sessions s ON s.id = g.session_id
      WHERE g.id = guardian_notifications.guardian_id
        AND s.user_id = auth.uid()
    )
  );
