-- ============================================================================
-- B1.3: згоди з EULA / Privacy Policy (обов'язковий крок онбордингу)
--
-- Запис створює тільки Edge Function v1-me (service_role) при PATCH
-- { accept_terms_version }. Користувач бачить лише власні згоди.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_consents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  doc TEXT NOT NULL CHECK (doc IN ('eula', 'privacy')),
  version TEXT NOT NULL CHECK (char_length(version) BETWEEN 1 AND 32),
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, doc, version)
);

CREATE INDEX IF NOT EXISTS user_consents_user_idx ON public.user_consents (user_id);

ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_consents FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_consents_self_read ON public.user_consents;
CREATE POLICY user_consents_self_read ON public.user_consents
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

REVOKE INSERT, UPDATE, DELETE ON public.user_consents FROM anon, authenticated;
