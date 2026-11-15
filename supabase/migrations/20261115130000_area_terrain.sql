-- ============================================================================
-- Рельєф і ґрунт ділянки (рішення PO 2026-11-15, ADR-015 §15.8 п.15)
-- Визначаються один раз при першому аналізі (Open-Meteo Elevation, ISRIC SoilGrids) і
-- зберігаються з ділянкою: {elevation, relief, reliefRange, sand, clay, soil, fetchedAt}.
-- Запис — лише service_role (Edge Function v1-analysis).
-- ============================================================================

ALTER TABLE public.analysis_areas ADD COLUMN IF NOT EXISTS terrain JSONB;

CREATE OR REPLACE FUNCTION public.save_area_terrain(p_user_id UUID, p_area_id UUID, p_terrain JSONB)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.analysis_areas
  SET terrain = p_terrain, updated_at = now()
  WHERE id = p_area_id AND user_id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.save_area_terrain(UUID, UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_area_terrain(UUID, UUID, JSONB) TO service_role;
