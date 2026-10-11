-- ============================================================================
-- Canonical mushroom catalog — 326 species (structure only)
-- Seed: 20260912000005_mushroom_catalog_seed.sql
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.mushroom_catalog (
  id TEXT PRIMARY KEY,
  name_ua TEXT NOT NULL,
  name_lat TEXT NOT NULL,
  edibility TEXT CHECK (edibility IN (
    'edible','conditionally_edible','inedible','poisonous','deadly_poisonous'
  )),
  edibility_label TEXT,
  red_listed BOOLEAN NOT NULL DEFAULT FALSE,
  rarity TEXT,
  has_photo BOOLEAN NOT NULL DEFAULT FALSE,
  top20 BOOLEAN NOT NULL DEFAULT FALSE,
  popular BOOLEAN NOT NULL DEFAULT FALSE,
  ai_recognition BOOLEAN NOT NULL DEFAULT FALSE,
  features TEXT,
  months INT[] NOT NULL DEFAULT '{}',
  attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
  photos JSONB NOT NULL DEFAULT '[]'::jsonb,
  peak_months INT[] NOT NULL DEFAULT '{}',
  zones TEXT[] NOT NULL DEFAULT '{}',
  license JSONB,
  red_book_source JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS mushroom_catalog_top20_idx
  ON public.mushroom_catalog (top20) WHERE top20;
CREATE INDEX IF NOT EXISTS mushroom_catalog_ai_idx
  ON public.mushroom_catalog (ai_recognition) WHERE ai_recognition;
CREATE INDEX IF NOT EXISTS mushroom_catalog_edibility_idx
  ON public.mushroom_catalog (edibility);
CREATE INDEX IF NOT EXISTS mushroom_catalog_red_listed_idx
  ON public.mushroom_catalog (red_listed) WHERE red_listed;
CREATE INDEX IF NOT EXISTS mushroom_catalog_months_gin
  ON public.mushroom_catalog USING GIN (months);
CREATE INDEX IF NOT EXISTS mushroom_catalog_zones_gin
  ON public.mushroom_catalog USING GIN (zones);

ALTER TABLE public.mushroom_catalog ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalog_read ON public.mushroom_catalog;
CREATE POLICY catalog_read ON public.mushroom_catalog
  FOR SELECT USING (auth.role() = 'authenticated');

COMMENT ON TABLE public.mushroom_catalog IS
  'Canonical catalog of 326 species. Source: mushroom_catalog.json.';

-- ============================================================================
-- regions.slug — мапінг zones каталогу (дані заповнються в Групі 9.1)
-- ============================================================================

ALTER TABLE public.regions
  ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS regions_slug_idx ON public.regions (slug);

COMMENT ON COLUMN public.regions.slug IS
  'Latin slug of oblast (kyivska, lvivska, ...). Maps zones from mushroom_catalog. Seed — Group 9.1.';
