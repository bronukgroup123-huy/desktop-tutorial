-- ============================================================================
-- B1.6 / ADR-001: гостьовий режим (Supabase Anonymous Sign-In)
-- B1.9 / ADR-016: джерело зміни Home Region
--
-- Гість — анонімний користувач з реальним UUID (JWT claim is_anonymous = true).
-- Гостю заборонено: публічні та «дружні» точки, сесії Наглядача (а отже й SOS).
-- Заборона реалізована RESTRICTIVE-політиками: вони діють поверх існуючих
-- permissive-політик і не послаблюють їх. Edge Functions (service_role) додатково
-- перевіряють це в коді (registration_required).
-- ============================================================================

-- ─── 1. Хелпер: чи зареєстрований поточний користувач ──────────────────────
CREATE OR REPLACE FUNCTION public.is_registered()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
     AND COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false) = false;
$$;

GRANT EXECUTE ON FUNCTION public.is_registered() TO authenticated, service_role;

-- ─── 2. Тук-туки: гість — лише private ─────────────────────────────────────
DROP POLICY IF EXISTS mushroom_picks_guest_private_only_insert ON public.mushroom_picks;
CREATE POLICY mushroom_picks_guest_private_only_insert ON public.mushroom_picks
  AS RESTRICTIVE
  FOR INSERT TO authenticated
  WITH CHECK (pick_type = 'private' OR public.is_registered());

DROP POLICY IF EXISTS mushroom_picks_guest_private_only_update ON public.mushroom_picks;
CREATE POLICY mushroom_picks_guest_private_only_update ON public.mushroom_picks
  AS RESTRICTIVE
  FOR UPDATE TO authenticated
  WITH CHECK (pick_type = 'private' OR public.is_registered());

-- ─── 3. Сесії Наглядача: тільки зареєстровані ──────────────────────────────
DROP POLICY IF EXISTS guardian_sessions_registered_only_insert ON public.guardian_sessions;
CREATE POLICY guardian_sessions_registered_only_insert ON public.guardian_sessions
  AS RESTRICTIVE
  FOR INSERT TO authenticated
  WITH CHECK (public.is_registered());

-- ─── 4. region_change_log.source (ADR-016) ─────────────────────────────────
-- onboarding      — перший вибір області
-- onboarding_fix  — безкоштовне виправлення протягом 24 год після першого вибору
-- pro             — одноразова зміна в Pro
-- support         — зміна через підтримку (вручну, service_role)
-- legacy          — записи, створені до цієї міграції
ALTER TABLE public.region_change_log
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'legacy';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'region_change_log_source_check'
  ) THEN
    ALTER TABLE public.region_change_log
      ADD CONSTRAINT region_change_log_source_check
      CHECK (source IN ('onboarding', 'onboarding_fix', 'pro', 'support', 'legacy'));
  END IF;
END
$$;
