-- ============================================================================
-- Guardian Module — previous_status Migration
-- ============================================================================

ALTER TABLE guardian_sessions
  ADD COLUMN previous_status TEXT
    CHECK (previous_status IN (
      'pending', 'active', 'stale', 'offline',
      'exiting', 'overdue_soft', 'overdue_medium', 'overdue_hard',
      'sos'
    ));

COMMENT ON COLUMN guardian_sessions.previous_status IS
  'Стан сесії до переходу в closing. Використовується для cancel-close.';
