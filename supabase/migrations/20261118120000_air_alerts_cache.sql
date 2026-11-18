-- ============================================================================
-- Спільний кеш повітряних тривог (ADR-022 §22.5 п.5, BACKEND_PLAN B4.12)
--
-- v1-air-alerts бере ВЕСЬ список активних тривог України одним запитом до alerts.in.ua і
-- розкладає його по областях. Кеш у пам'яті функції в кожної копії свій — під навантаженням
-- Supabase запускає кілька копій, і кожна ходила б до alerts.in.ua окремо. Тепер:
--  * останній список областей і Last-Modified — в одному рядку цієї таблиці (спільно для всіх);
--  * оновлення «захоплює» одна копія (air_alerts_claim_refresh: атомарний UPDATE з орендою
--    на кілька секунд) — до alerts.in.ua не частіше одного запиту на TTL на весь сервер;
--  * 429 від alerts.in.ua — пауза (backoff_until), тим часом віддаються останні дані.
-- Дані — відкриті (стан тривог), без даних користувачів. Доступ — лише service_role.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.air_alerts_cache (
  id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  regions JSONB NOT NULL DEFAULT '[]'::jsonb,
  fetched_at TIMESTAMPTZ,
  last_modified TEXT,
  refreshing_until TIMESTAMPTZ,
  backoff_until TIMESTAMPTZ
);

ALTER TABLE public.air_alerts_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.air_alerts_cache FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.air_alerts_cache FROM anon, authenticated;

INSERT INTO public.air_alerts_cache (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- Чи можна цій копії функції йти до alerts.in.ua зараз: кеш застарів, ніхто інший не оновлює
-- (оренда минула) і немає паузи після 429. `true` — оренду взято.
CREATE OR REPLACE FUNCTION public.air_alerts_claim_refresh(p_ttl_seconds INTEGER, p_lease_seconds INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  WITH claimed AS (
    UPDATE public.air_alerts_cache
       SET refreshing_until = now() + make_interval(secs => p_lease_seconds)
     WHERE id = 1
       AND (fetched_at IS NULL OR fetched_at < now() - make_interval(secs => p_ttl_seconds))
       AND (refreshing_until IS NULL OR refreshing_until < now())
       AND (backoff_until IS NULL OR backoff_until < now())
    RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM claimed);
$$;

REVOKE ALL ON FUNCTION public.air_alerts_claim_refresh(INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.air_alerts_claim_refresh(INTEGER, INTEGER) TO service_role;
