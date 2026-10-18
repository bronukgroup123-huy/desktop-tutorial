-- ============================================================================
-- CT-14: IP-based rate limiting для публічних Edge Functions
-- Таблиця ip_rate_limit + атомарний RPC check_and_increment_ip_rate_limit
-- Захист від спаму/ботів на /forecast, /picks, /regions, /catalog
-- ============================================================================

-- ─── 1. Таблиця лімітів запитів за IP ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ip_rate_limit (
  id BIGSERIAL PRIMARY KEY,
  ip TEXT NOT NULL,
  endpoint TEXT NOT NULL CHECK (endpoint IN ('forecast', 'picks', 'regions', 'catalog')),
  window_start TIMESTAMPTZ NOT NULL,
  count INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (ip, endpoint, window_start)
);

CREATE INDEX IF NOT EXISTS ip_rate_limit_lookup_idx
  ON public.ip_rate_limit (ip, endpoint, window_start DESC);

-- Auto-cleanup: вікна старіші 7 днів непотрібні
CREATE INDEX IF NOT EXISTS ip_rate_limit_cleanup_idx
  ON public.ip_rate_limit (window_start);

-- RLS: тільки service_role (edge functions)
ALTER TABLE public.ip_rate_limit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ip_rate_limit_service_only ON public.ip_rate_limit;
CREATE POLICY ip_rate_limit_service_only ON public.ip_rate_limit
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================================
-- 2. RPC: атомарний інкремент лічильника за IP + endpoint за хвилину
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_and_increment_ip_rate_limit(
  p_ip TEXT,
  p_endpoint TEXT,
  p_window_start TIMESTAMPTZ,
  p_limit INT
)
RETURNS TABLE (count INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  INSERT INTO public.ip_rate_limit (ip, endpoint, window_start, count)
  VALUES (p_ip, p_endpoint, p_window_start, 1)
  ON CONFLICT (ip, endpoint, window_start)
  DO UPDATE SET
    count = public.ip_rate_limit.count + 1,
    updated_at = now()
  RETURNING public.ip_rate_limit.count;
END;
$$;

-- Тільки service_role
REVOKE ALL ON FUNCTION public.check_and_increment_ip_rate_limit(TEXT, TEXT, TIMESTAMPTZ, INT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_ip_rate_limit(TEXT, TEXT, TIMESTAMPTZ, INT)
  TO service_role;

-- ============================================================================
-- 3. Cleanup cron: видалити вікна старіші 7 днів (раз на добу о 04:00 UTC)
-- ============================================================================
-- PERFORM cron.schedule(
--   'ip-rate-limit-cleanup-daily',
--   '0 4 * * *',
--   $$DELETE FROM public.ip_rate_limit WHERE window_start < now() - INTERVAL '7 days'$$
-- );

COMMENT ON TABLE public.ip_rate_limit IS
  'IP-based rate limit лічильники для публічних Edge Functions (CT-14).';
