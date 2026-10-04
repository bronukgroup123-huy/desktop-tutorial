-- ============================================================================
-- Guardian Module — Cron, Geofence, Tick Log Migration
-- ============================================================================

-- ============================================================================
-- Extensions
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ============================================================================
-- forest_polygons — OSM геозони лісів
-- ============================================================================

CREATE TABLE IF NOT EXISTS forest_polygons (
  id BIGSERIAL PRIMARY KEY,
  polygon GEOGRAPHY(MultiPolygon, 4326) NOT NULL,
  source TEXT NOT NULL DEFAULT 'osm',
  osm_id BIGINT,
  region_id INT REFERENCES regions(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS forest_polygons_geom_idx
  ON forest_polygons USING GIST (polygon);

CREATE INDEX IF NOT EXISTS forest_polygons_region_idx
  ON forest_polygons (region_id);

-- ============================================================================
-- Допоміжна функція: чи точка в лісі?
-- ============================================================================

CREATE OR REPLACE FUNCTION is_point_in_forest(
  p_lat NUMERIC,
  p_lng NUMERIC
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM forest_polygons fp
    WHERE ST_Contains(fp.polygon::geometry, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326))
  );
$$;

-- ============================================================================
-- guardian_tick_log — історія запусків
-- ============================================================================

CREATE TABLE IF NOT EXISTS guardian_tick_log (
  id BIGSERIAL PRIMARY KEY,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  sessions_scanned INT DEFAULT 0,
  transitions_made INT DEFAULT 0,
  alerts_created INT DEFAULT 0,
  errors INT DEFAULT 0,
  error_details JSONB
);

CREATE INDEX IF NOT EXISTS guardian_tick_log_started_idx
  ON guardian_tick_log (started_at DESC);

-- ============================================================================
-- Cron job: guardian-tick кожну хвилину
-- ============================================================================
-- Примітка: для 30-секундного інтервалу налаштуйте Scheduled Functions в Dashboard.
-- Цей job — fallback для dev-середовища.

SELECT cron.schedule(
  'guardian-tick-every-minute',
  '* * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/guardian-tick',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  );
  $$
);
