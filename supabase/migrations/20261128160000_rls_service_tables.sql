-- ============================================================================
-- SEC-008: RLS на чотирьох службових таблицях (BACKLOG SEC-008, знайдено в DOC-001)
-- ============================================================================
-- Міграція 20260912000017 поставила на них лише FORCE ROW LEVEL SECURITY, а ENABLE — ні; без ENABLE
-- FORCE не діє. Продакшен, імовірно, має RLS з налаштувань Dashboard (2026-09) — ця міграція вирівнює
-- міграції з продакшеном і ідемпотентна (повторне ENABLE нічого не змінює).
--
-- Наслідки для доступу:
--   * anon / authenticated — прав на ці таблиці й так немає (REVOKE у 20260912000017); тепер — і RLS без політик;
--   * service_role (Edge Functions) і postgres (власник, SECURITY DEFINER функції, cron) мають BYPASSRLS —
--     для них нічого не змінюється, навіть із FORCE.
-- Таблиці Guardian v0 (guardian_push_tokens, guardian_tick_log) лишаються до рішення про дані (BLK-009).

ALTER TABLE IF EXISTS public.forest_polygons ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.guardian_push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.guardian_tick_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.user_push_tokens ENABLE ROW LEVEL SECURITY;
