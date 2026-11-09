-- ============================================================================
-- B2.6: кеш погоди (Open-Meteo) по сітці ~10×10 км
--
-- Сусідні точки й різні користувачі беруть погоду з кешу: у Open-Meteo йде
-- не більше одного запиту на клітинку раз на кілька годин. Один рядок на
-- клітинку (upsert), тож таблиця обмежена кількістю клітинок України.
-- Доступ — лише service_role (Edge Functions).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.weather_cache (
  cell_key TEXT PRIMARY KEY,           -- "50.3:28.7" — центр клітинки 0.1°
  payload JSONB NOT NULL,              -- WeatherData
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.weather_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weather_cache FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.weather_cache FROM anon, authenticated;
