-- ============================================================================
-- regions — області України з полігонами
-- PostGIS включається тут, бо це перше місце, де він потрібен
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

CREATE TABLE public.regions (
  id SERIAL PRIMARY KEY,

  name TEXT NOT NULL,
  koatuu TEXT UNIQUE,
  katottg TEXT UNIQUE,

  polygon extensions.GEOMETRY(MultiPolygon, 4326) NOT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX regions_polygon_idx
  ON public.regions USING GIST (polygon);

CREATE INDEX regions_name_idx
  ON public.regions (name);

CREATE TRIGGER regions_updated_at
  BEFORE UPDATE ON public.regions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;

CREATE POLICY regions_read ON public.regions
  FOR SELECT USING (auth.role() = 'authenticated');
