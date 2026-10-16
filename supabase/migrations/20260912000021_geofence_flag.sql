-- ============================================================================
-- Feature flag: geofence (PC-TASK #9 / Audit G4)
-- ============================================================================
-- Вимикнено поки немає polygon у forest_polygons.
-- Коли polygon будуть імпортовано → enabled = true.
-- ============================================================================

INSERT INTO feature_flags (key, enabled, value)
VALUES (
  'geofence_enabled',
  false,
  '{"reason": "forest_polygons empty — geofence disabled until polygons imported"}'::jsonb
)
ON CONFLICT (key) DO UPDATE SET enabled = false, value = EXCLUDED.value;
