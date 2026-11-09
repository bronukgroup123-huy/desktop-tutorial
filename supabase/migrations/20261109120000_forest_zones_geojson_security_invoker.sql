-- ============================================================================
-- Формалізація ручної зміни в Dashboard (2026-11-09, Security Advisor)
--
-- PO увімкнув security_invoker = on для представлення public.forest_zones_geojson,
-- щоб RLS базових таблиць не обходилась. Правило проєкту: жодного DDL лише через
-- Dashboard (урок audit E) — фіксуємо зміну міграцією.
--
-- Представлення створювалось поза міграціями, тому змінюємо його тільки якщо
-- воно існує (на чистій БД його немає — міграція нічого не робить).
-- ============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_views
    WHERE schemaname = 'public' AND viewname = 'forest_zones_geojson'
  ) THEN
    EXECUTE 'ALTER VIEW public.forest_zones_geojson SET (security_invoker = on)';
  END IF;
END
$$;
