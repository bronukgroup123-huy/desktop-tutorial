-- ============================================================================
-- regions — області України з полігонами
-- PostGIS включається тут, бо це перше місце, де він потрібен
-- ============================================================================
-- ІДЕМПОТЕНТНА ВЕРСІЯ: таблиця могла бути створена вручну в SQL Editor,
-- тому всі операції безпечні для повторного виконання.

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

-- Гарантуємо видимість extensions у search_path (лікує "type geography
-- does not exist" у CI, де search_path може не містити extensions)
ALTER DATABASE postgres SET search_path TO public, extensions;

-- Функція оновлення updated_at (створюється тут, бо це найперший файл,
-- який її використовує; create_users теж її створює — OR REPLACE ідемпотентний)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn_upd$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$fn_upd$;

CREATE TABLE IF NOT EXISTS public.regions (
  id SERIAL PRIMARY KEY,

  name TEXT NOT NULL,
  koatuu TEXT UNIQUE,
  katottg TEXT UNIQUE,

  polygon extensions.GEOMETRY(MultiPolygon, 4326) NOT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Дожати ключові колонки, якщо таблиця була створена вручну без них
ALTER TABLE public.regions ADD COLUMN IF NOT EXISTS koatuu TEXT;
ALTER TABLE public.regions ADD COLUMN IF NOT EXISTS katottg TEXT;

CREATE INDEX IF NOT EXISTS regions_polygon_idx
  ON public.regions USING GIST (polygon);

CREATE INDEX IF NOT EXISTS regions_name_idx
  ON public.regions (name);

-- Trigger (guarded: CREATE TRIGGER не має IF NOT EXISTS в PG15)
DO $do_regions$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'regions_updated_at'
      AND tgrelid = 'public.regions'::regclass
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER regions_updated_at
      BEFORE UPDATE ON public.regions
      FOR EACH ROW
      EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END;
$do_regions$;

ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS regions_read ON public.regions;
CREATE POLICY regions_read ON public.regions
  FOR SELECT USING (auth.role() = 'authenticated');
