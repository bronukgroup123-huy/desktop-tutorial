-- ============================================
-- ГРИБНИЙ РАДАР — схема v1.1 (області замість зон)
-- ============================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------- ENUM ----------
CREATE TYPE edibility_status AS ENUM (
  'edible','conditionally_edible','controversial',
  'inedible','poisonous','deadly_poisonous'
);
CREATE TYPE twin_severity AS ENUM (
  'deadly_poisonous','poisonous','conditionally_edible','inedible','other'
);
CREATE TYPE photo_license AS ENUM ('cc0','cc-by');

-- ---------- Області ----------
CREATE TABLE regions (
  id        SERIAL PRIMARY KEY,
  name      TEXT UNIQUE NOT NULL,          -- 'Львівська'
  koatuu    TEXT UNIQUE,                   -- '4600000000'
  polygon   GEOMETRY(MultiPolygon,4326),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX regions_polygon_idx ON regions USING GIST (polygon);

-- ---------- Головна таблиця ----------
CREATE TABLE species (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug               TEXT UNIQUE NOT NULL,
  scientific_name    TEXT UNIQUE NOT NULL,
  common_name_uk     TEXT,
  genus              TEXT,
  family             TEXT,

  edibility_status   edibility_status NOT NULL,
  is_red_listed      BOOLEAN NOT NULL DEFAULT FALSE,
  rarity_label_uk    TEXT,
  sensitive_location BOOLEAN NOT NULL DEFAULT FALSE,

  in_forecast        BOOLEAN NOT NULL DEFAULT FALSE,
  is_popular         BOOLEAN NOT NULL DEFAULT FALSE,
  is_poisonous       BOOLEAN NOT NULL DEFAULT FALSE,
  is_deadly          BOOLEAN NOT NULL DEFAULT FALSE,
  in_ai_recognition  BOOLEAN NOT NULL DEFAULT FALSE,
  has_ai_prompt      BOOLEAN NOT NULL DEFAULT FALSE,
  guide_visible      BOOLEAN NOT NULL DEFAULT TRUE,
  popularity_rank    INT,
  ai_priority        INT,
  source_list        TEXT[],

  short_description  TEXT,
  full_description   TEXT,
  disclaimer         TEXT,

  legacy_id          INT,

  has_photos         BOOLEAN NOT NULL DEFAULT FALSE,
  content_version    INT NOT NULL DEFAULT 1,
  reviewed_by        TEXT,
  reviewed_at        TIMESTAMPTZ,

  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT deadly_implies_poisonous CHECK (NOT is_deadly OR is_poisonous),
  CONSTRAINT forecast_requires_edible
    CHECK (NOT in_forecast OR edibility_status IN ('edible','conditionally_edible')),
  CONSTRAINT forecast_not_red_listed
    CHECK (NOT in_forecast OR NOT is_red_listed),
  CONSTRAINT ai_not_red_listed
    CHECK (NOT in_ai_recognition OR NOT is_red_listed),
  CONSTRAINT forecast_requires_photos
    CHECK (NOT in_forecast OR has_photos),
  CONSTRAINT popular_requires_photos
    CHECK (NOT is_popular OR has_photos),
  CONSTRAINT poisonous_requires_photos
    CHECK (NOT is_poisonous OR has_photos),
  CONSTRAINT ai_recognition_requires_photos
    CHECK (NOT in_ai_recognition OR has_photos),
  CONSTRAINT forecast_subset_of_ai
    CHECK (NOT in_forecast OR in_ai_recognition)
);

CREATE INDEX species_roles_idx ON species
  (in_forecast, is_popular, is_deadly, in_ai_recognition);
CREATE INDEX species_edibility_idx ON species (edibility_status);
CREATE INDEX species_red_listed_idx ON species (is_red_listed) WHERE is_red_listed;
CREATE INDEX species_fts_idx ON species USING GIN (
  to_tsvector('simple', coalesce(scientific_name,'') || ' ' ||
              coalesce(common_name_uk,'') || ' ' ||
              coalesce(short_description,''))
);

-- ---------- Прив'язка до областей ----------
CREATE TABLE species_regions (
  species_id UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  region_id  INT  NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
  PRIMARY KEY (species_id, region_id)
);
CREATE INDEX species_regions_region_idx ON species_regions (region_id);

-- ---------- Народні назви / синоніми ----------
CREATE TABLE species_names (
  id         SERIAL PRIMARY KEY,
  species_id UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  name_type  TEXT NOT NULL CHECK (name_type IN ('folk','synonym','latin_synonym')),
  language   TEXT NOT NULL DEFAULT 'uk',
  UNIQUE (species_id, name, name_type)
);
CREATE INDEX species_names_trgm ON species_names USING GIN (name gin_trgm_ops);

-- ---------- Фото ----------
CREATE TABLE species_photos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  species_id        UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  file_name         TEXT NOT NULL,
  storage_path      TEXT NOT NULL,
  angle             TEXT CHECK (angle IN (
    'general','cap_top','cap_bottom','stem','flesh_cut',
    'habitat','in_hand','twin_comparison','scale_reference')),
  license_code      photo_license NOT NULL,
  license_url       TEXT,
  license_file_path TEXT,
  author            TEXT,
  source_url        TEXT,
  attribution       TEXT NOT NULL,
  modified          BOOLEAN NOT NULL DEFAULT FALSE,
  modification_note TEXT,
  sort_order        INT NOT NULL DEFAULT 0,
  CONSTRAINT cc_by_requires_file CHECK (license_code <> 'cc-by' OR license_file_path IS NOT NULL),
  CONSTRAINT cc_by_requires_author CHECK (license_code <> 'cc-by' OR author IS NOT NULL)
);
CREATE INDEX species_photos_species ON species_photos (species_id, sort_order);

-- ---------- Двійники ----------
CREATE TABLE species_twins (
  id             SERIAL PRIMARY KEY,
  species_id     UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  twin_id        UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  severity       twin_severity NOT NULL,
  distinguishing TEXT NOT NULL,
  is_clickable   BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order     INT NOT NULL DEFAULT 0,
  UNIQUE (species_id, twin_id),
  CHECK (species_id <> twin_id)
);

-- ---------- Місцезростання ----------
CREATE TABLE species_habitats (
  id            SERIAL PRIMARY KEY,
  species_id    UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  season        TEXT[],
  forest_types  TEXT[],
  substrate     TEXT,
  symbiont_tree TEXT,
  description   TEXT,
  edible_part   TEXT
);

-- ---------- Кулінарія ----------
CREATE TABLE species_culinary (
  species_id       UUID PRIMARY KEY REFERENCES species(id) ON DELETE CASCADE,
  requires_cooking BOOLEAN NOT NULL DEFAULT FALSE,
  cooking_note     TEXT,
  worm_test        TEXT,
  taste_note       TEXT,
  storage_note     TEXT
);

CREATE TABLE species_recipes (
  id         SERIAL PRIMARY KEY,
  species_id UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0
);

-- ---------- Emergency ----------
CREATE TABLE species_emergency (
  species_id        UUID PRIMARY KEY REFERENCES species(id) ON DELETE CASCADE,
  toxin_type        TEXT NOT NULL,
  mechanism         TEXT NOT NULL,
  immediate_actions TEXT NOT NULL,
  symptom_timeline  JSONB NOT NULL,
  tell_doctor       TEXT NOT NULL,
  contacts          JSONB NOT NULL,
  take_with_you     TEXT[] NOT NULL,
  critical_warning  TEXT NOT NULL,
  reviewed_by       TEXT NOT NULL,
  reviewed_at       TIMESTAMPTZ NOT NULL
);

-- ---------- Банери ----------
CREATE TABLE species_warnings (
  id                SERIAL PRIMARY KEY,
  species_id        UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  warning_type      TEXT NOT NULL CHECK (warning_type IN (
    'conditional_edible','deadly_twin','controversial',
    'poisonous','red_listed','status_changed')),
  message           TEXT NOT NULL,
  link_twin_id      UUID REFERENCES species(id),
  color             TEXT NOT NULL CHECK (color IN ('yellow','red','orange','gray')),
  visible_collapsed BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---------- Пошук ----------
CREATE TABLE species_search_attrs (
  species_id UUID PRIMARY KEY REFERENCES species(id) ON DELETE CASCADE,
  cap_color  TEXT[],
  gimenofor  TEXT,
  has_ring   BOOLEAN,
  has_volva  BOOLEAN,
  substrate  TEXT[],
  size_class TEXT CHECK (size_class IN ('small','medium','large')),
  season     TEXT[]
);

-- ---------- Версії ----------
CREATE TABLE species_versions (
  id          SERIAL PRIMARY KEY,
  species_id  UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  version     INT NOT NULL,
  change_note TEXT NOT NULL,
  changed_by  TEXT NOT NULL,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  snapshot    JSONB NOT NULL,
  UNIQUE (species_id, version)
);

-- ---------- Рушій ----------
CREATE TABLE expert_rules (
  id                    SERIAL PRIMARY KEY,
  species_id            UUID UNIQUE REFERENCES species(id) ON DELETE RESTRICT,
  legacy_id             INT,
  mushroom_type         TEXT UNIQUE NOT NULL,
  name_ua               TEXT NOT NULL,
  name_lat              TEXT NOT NULL,
  fruiting_temp_min     NUMERIC(4,1),
  fruiting_temp_max     NUMERIC(4,1),
  fruiting_temp_peak_min NUMERIC(4,1),
  fruiting_temp_peak_max NUMERIC(4,1),
  mycelium_temp_min     NUMERIC(4,1) DEFAULT 15,
  mycelium_temp_max     NUMERIC(4,1) DEFAULT 20,
  humidity_min          NUMERIC(4,1),
  rain_3d_min           NUMERIC(5,1),
  rain_1d_min           NUMERIC(5,1),
  rain_2d_min           NUMERIC(5,1),
  drought_days_min      INT,
  days_after_rain_min   INT,
  days_after_rain_max   INT,
  waterlogged_penalty   NUMERIC(4,2),
  drought_then_rain     BOOLEAN DEFAULT FALSE,
  pressure_min          INT,
  pressure_max          INT,
  pressure_trend        TEXT,
  forest_type           TEXT[],
  habitat_type          TEXT[],
  relief_type           TEXT[],
  altitude_min          INT,
  altitude_max          INT,
  soil_ph_min           NUMERIC(3,1),
  soil_ph_max           NUMERIC(3,1),
  light_preference      TEXT,
  stand_age_min         INT,
  stand_age_max         INT,
  prefers_lowland       BOOLEAN DEFAULT FALSE,
  prefers_hilltop       BOOLEAN DEFAULT FALSE,
  season_start          TEXT NOT NULL,
  season_end            TEXT NOT NULL,
  wave_spring           BOOLEAN DEFAULT FALSE,
  wave_summer1          BOOLEAN DEFAULT FALSE,
  wave_summer2          BOOLEAN DEFAULT FALSE,
  wave_autumn           BOOLEAN DEFAULT FALSE,
  wave_late             BOOLEAN DEFAULT FALSE,
  peak_waves            TEXT[] DEFAULT '{}',
  peak_months           INT[] DEFAULT '{}',
  indicator_species     TEXT[],
  shock_required        BOOLEAN DEFAULT FALSE,
  microrefugium_dry     TEXT,
  microrefugium_wet     TEXT,
  region_ids            INT[] DEFAULT '{}',
  weight                NUMERIC(3,2) NOT NULL,
  mvp_stage             TEXT DEFAULT 'mvp',
  last_calibrated_at    TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- ---------- Користувачі ----------
CREATE TABLE users (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT,
  email        TEXT UNIQUE,
  rating       NUMERIC(5,2) DEFAULT 0,
  total_verified_picks INT DEFAULT 0,
  home_region_id INT REFERENCES regions(id),
  role         TEXT DEFAULT 'user' CHECK (role IN ('user','moderator','mycologist','admin')),
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE mushroom_picks (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID REFERENCES users(id),
  species_id   UUID REFERENCES species(id) ON DELETE RESTRICT,
  lat          NUMERIC(9,6),
  lng          NUMERIC(9,6),
  geom         GEOMETRY(Point,4326),
  photo_url    TEXT,
  pick_type    TEXT CHECK (pick_type IN ('private','friends','public')),
  verification_status TEXT DEFAULT 'pending'
    CHECK (verification_status IN ('pending','verified','conditional','rejected')),
  weight       NUMERIC(3,2) DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE calibration_log (
  id         SERIAL PRIMARY KEY,
  date       TIMESTAMPTZ DEFAULT now(),
  species_id UUID REFERENCES species(id),
  param      TEXT,
  old_value  NUMERIC,
  new_value  NUMERIC,
  reason     TEXT,
  approved_by TEXT
);

CREATE TABLE feature_flags (
  key        TEXT PRIMARY KEY,
  enabled    BOOLEAN DEFAULT FALSE,
  value      JSONB,
  updated_at TIMESTAMPTZ DEFAULT now()
);
