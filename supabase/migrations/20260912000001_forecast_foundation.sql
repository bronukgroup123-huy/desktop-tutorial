-- ============================================================================
-- Forecast Engine — Foundation (Group 8.1)
-- 6 tables: expert_rules, forest_zones, mushroom_picks, feature_flags,
-- calibration_log, region_change_log
-- ============================================================================

-- ============================================================================
-- 1. expert_rules — правила експертів по видах
-- ============================================================================

CREATE TABLE IF NOT EXISTS expert_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  legacy_id INT UNIQUE,
  mushroom_type TEXT NOT NULL UNIQUE,   -- snake_case canonical id
  name_ua TEXT NOT NULL,
  name_lat TEXT NOT NULL,

  -- Температури (°C)
  fruiting_temp_min NUMERIC(4,1),
  fruiting_temp_max NUMERIC(4,1),
  fruiting_temp_peak_min NUMERIC(4,1),
  fruiting_temp_peak_max NUMERIC(4,1),
  mycelium_temp_min NUMERIC(4,1),
  mycelium_temp_max NUMERIC(4,1),

  -- Вологість і опади
  humidity_min NUMERIC(5,2),
  rain_3d_min NUMERIC(6,2),
  rain_1d_min NUMERIC(6,2),
  rain_2d_min NUMERIC(6,2),
  drought_days_min INT,
  days_after_rain_min INT,
  days_after_rain_max INT,
  waterlogged_penalty NUMERIC(3,2),
  drought_then_rain BOOLEAN NOT NULL DEFAULT FALSE,

  -- Середовище
  forest_type TEXT[] NOT NULL DEFAULT '{}',
  habitat_type TEXT[] NOT NULL DEFAULT '{}',
  relief_type TEXT[] NOT NULL DEFAULT '{}',
  altitude_min INT,
  altitude_max INT,
  soil_ph_min NUMERIC(3,1),
  soil_ph_max NUMERIC(3,1),
  light_preference TEXT,
  stand_age_min INT,
  stand_age_max INT,
  prefers_lowland BOOLEAN NOT NULL DEFAULT FALSE,
  prefers_hilltop BOOLEAN NOT NULL DEFAULT FALSE,

  -- Сезон
  season_start TEXT NOT NULL CHECK (season_start ~ '^\d{2}-\d{2}$'),
  season_end TEXT NOT NULL CHECK (season_end ~ '^\d{2}-\d{2}$'),
  wave_spring BOOLEAN NOT NULL DEFAULT FALSE,
  wave_summer1 BOOLEAN NOT NULL DEFAULT FALSE,
  wave_summer2 BOOLEAN NOT NULL DEFAULT FALSE,
  wave_autumn BOOLEAN NOT NULL DEFAULT FALSE,
  wave_late BOOLEAN NOT NULL DEFAULT FALSE,
  peak_waves TEXT[] NOT NULL DEFAULT '{}',
  peak_months INT[] NOT NULL DEFAULT '{}',

  -- Індикатори та умови
  indicator_species TEXT[] NOT NULL DEFAULT '{}',
  shock_required BOOLEAN NOT NULL DEFAULT FALSE,
  microrefugium_dry TEXT,
  microrefugium_wet TEXT,

  -- Географія
  region_ids INT[] NOT NULL DEFAULT '{}',

  -- Мета
  weight NUMERIC(3,2) NOT NULL DEFAULT 1.0,
  mvp_stage TEXT NOT NULL DEFAULT 'mvp'
    CHECK (mvp_stage IN ('mvp', 'v2', 'future')),
  last_calibrated_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS expert_rules_mushroom_type_idx
  ON expert_rules (mushroom_type);
CREATE INDEX IF NOT EXISTS expert_rules_mvp_stage_idx
  ON expert_rules (mvp_stage);

DROP TRIGGER IF EXISTS expert_rules_updated_at ON expert_rules;
CREATE TRIGGER expert_rules_updated_at
  BEFORE UPDATE ON expert_rules
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE expert_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS expert_rules_read ON expert_rules;
CREATE POLICY expert_rules_read ON expert_rules
  FOR SELECT USING (auth.role() = 'authenticated');

-- write: тільки service_role (політик немає → RLS блокує)

-- ============================================================================
-- 2. forest_zones — лісові зони (наповнюється Групою 9)
-- ============================================================================

CREATE TABLE IF NOT EXISTS forest_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  polygon extensions.GEOMETRY(MultiPolygon, 4326) NOT NULL,
  forest_type TEXT,
  stand_age_years INT CHECK (stand_age_years BETWEEN 0 AND 500),
  stand_age_source TEXT CHECK (stand_age_source IN ('inventory', 'ndvi', 'user')),
  stand_age_confidence NUMERIC(3,2) CHECK (stand_age_confidence BETWEEN 0 AND 1),
  relief_type TEXT,
  light_type TEXT,
  region_id INT REFERENCES regions(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS forest_zones_polygon_idx
  ON forest_zones USING GIST (polygon);
CREATE INDEX IF NOT EXISTS forest_zones_region_idx
  ON forest_zones (region_id);

ALTER TABLE forest_zones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS forest_zones_read ON forest_zones;
CREATE POLICY forest_zones_read ON forest_zones
  FOR SELECT USING (auth.role() = 'authenticated');

-- ============================================================================
-- 3. mushroom_picks — приватні/дружні/публічні знахідки
-- ============================================================================

CREATE TABLE IF NOT EXISTS mushroom_picks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  trip_id UUID NULL,

  geom GEOGRAPHY(Point, 4326) NOT NULL,
  photo_url TEXT NULL,

  mushroom_type TEXT NOT NULL,
  forest_type TEXT NULL,
  weather_data JSONB NULL,

  pick_type TEXT NOT NULL CHECK (pick_type IN ('private', 'friends', 'public')),
  shared_with UUID[] NOT NULL DEFAULT '{}',

  verification_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending', 'verified', 'conditional', 'rejected')),
  verified_by UUID NULL REFERENCES auth.users(id),

  weight NUMERIC(3,2) NOT NULL DEFAULT 1.0,
  is_indicator BOOLEAN NOT NULL DEFAULT FALSE,
  is_negative BOOLEAN NOT NULL DEFAULT FALSE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS mushroom_picks_geom_idx
  ON mushroom_picks USING GIST (geom);
CREATE INDEX IF NOT EXISTS mushroom_picks_user_idx
  ON mushroom_picks (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS mushroom_picks_type_status_idx
  ON mushroom_picks (mushroom_type, verification_status);

ALTER TABLE mushroom_picks ENABLE ROW LEVEL SECURITY;

-- Read: owner + friends + public + same home region (§10.4)
DROP POLICY IF EXISTS mushroom_picks_read ON mushroom_picks;
CREATE POLICY mushroom_picks_read ON mushroom_picks
  FOR SELECT USING (
    auth.uid() = user_id
    OR auth.uid() = ANY (shared_with)
    OR pick_type = 'public'
    OR EXISTS (
      SELECT 1 FROM users me, users author
      WHERE me.id = auth.uid()
        AND author.id = mushroom_picks.user_id
        AND me.home_region_id IS NOT NULL
        AND me.home_region_id = author.home_region_id
    )
  );

-- Insert: owner
DROP POLICY IF EXISTS mushroom_picks_insert ON mushroom_picks;
CREATE POLICY mushroom_picks_insert ON mushroom_picks
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Update: owner (поля verification_status оновлює тільки service_role —
-- через відсутність full-політики RLS це частково; тотальний захист
-- верифікації — на рівні Edge Function з service_role)
DROP POLICY IF EXISTS mushroom_picks_update ON mushroom_picks;
CREATE POLICY mushroom_picks_update ON mushroom_picks
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- 4. feature_flags
-- ============================================================================

CREATE TABLE IF NOT EXISTS feature_flags (
  key TEXT PRIMARY KEY,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  value JSONB NOT NULL DEFAULT 'null'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS feature_flags_read ON feature_flags;
CREATE POLICY feature_flags_read ON feature_flags
  FOR SELECT USING (auth.role() = 'authenticated');

-- ============================================================================
-- 5. calibration_log — тільки service_role
-- ============================================================================

CREATE TABLE IF NOT EXISTS calibration_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  species TEXT NOT NULL,
  param TEXT NOT NULL,
  old_value JSONB,
  new_value JSONB,
  reason TEXT,
  approved_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE calibration_log ENABLE ROW LEVEL SECURITY;
-- read/write: тільки service_role (політик для anon/authenticated немає)

-- ============================================================================
-- 6. region_change_log — тільки service_role
-- ============================================================================

CREATE TABLE IF NOT EXISTS region_change_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  old_region_id INT REFERENCES regions(id),
  new_region_id INT REFERENCES regions(id),
  device_fingerprint TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS region_change_log_user_idx
  ON region_change_log (user_id, changed_at DESC);

ALTER TABLE region_change_log ENABLE ROW LEVEL SECURITY;
-- read/write: тільки service_role
