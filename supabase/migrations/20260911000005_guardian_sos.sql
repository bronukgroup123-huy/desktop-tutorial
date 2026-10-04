-- ============================================================================
-- Guardian Module — SOS, Rescue Requests Migration
-- ============================================================================

-- ============================================================================
-- guardian_rescue_requests — запити "передати рятувальникам"
-- ============================================================================

CREATE TABLE guardian_rescue_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES guardian_sessions(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES users(id),

  token_hash TEXT NOT NULL UNIQUE,
  token_prefix TEXT NOT NULL,

  target TEXT NOT NULL DEFAULT '101'
    CHECK (target IN ('101', 'police', 'family', 'other')),

  notes TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,

  expires_at TIMESTAMPTZ NOT NULL,
  resolved_at TIMESTAMPTZ,
  resolved_note TEXT,

  viewed_count INT NOT NULL DEFAULT 0,
  last_viewed_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX guardian_rescue_session_idx
  ON guardian_rescue_requests (session_id, created_at DESC);

CREATE INDEX guardian_rescue_token_idx
  ON guardian_rescue_requests (token_hash);

CREATE INDEX guardian_rescue_active_idx
  ON guardian_rescue_requests (expires_at)
  WHERE resolved_at IS NULL;

-- ============================================================================
-- RLS
-- ============================================================================

ALTER TABLE guardian_rescue_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY guardian_rescue_owner_read ON guardian_rescue_requests
  FOR SELECT
  USING (auth.uid() = created_by);

CREATE POLICY guardian_rescue_owner_insert ON guardian_rescue_requests
  FOR INSERT
  WITH CHECK (
    auth.uid() = created_by
    AND EXISTS (
      SELECT 1 FROM guardian_sessions s
      WHERE s.id = guardian_rescue_requests.session_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY guardian_rescue_owner_update ON guardian_rescue_requests
  FOR UPDATE
  USING (auth.uid() = created_by);
