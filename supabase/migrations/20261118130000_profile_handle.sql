-- ============================================================================
-- Профіль: нік, ім'я, аватар; видалення акаунта (ADR-021 §21.2.1, §21.7; BACKEND_PLAN B9.1)
--
--  * handle — нік лише українськими літерами (`Олена_лісова`), показується як написали;
--  * handle_key — ключ унікальності (малі літери, один апостроф ʼ) — рахує сервер;
--  * handle_changed_at — змінювати нік не частіше разу на 30 днів;
--  * avatar — { kind: "standard", id: 1…20 } (конструктор — окремим кроком).
-- Видалення акаунта (вимога Google Play): delete_user_account — лише service_role,
-- видаляє auth.users → каскадом public.users і все, що на нього посилається.
-- ============================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS handle TEXT,
  ADD COLUMN IF NOT EXISTS handle_key TEXT,
  ADD COLUMN IF NOT EXISTS handle_changed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS avatar JSONB;

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_handle_format;
ALTER TABLE public.users ADD CONSTRAINT users_handle_format CHECK (
  handle IS NULL
  OR handle ~ '^[А-ЩЬЮЯЄІЇҐа-щьюяєіїґ][А-ЩЬЮЯЄІЇҐа-щьюяєіїґ0-9_.ʼ]{2,19}$'
);
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_handle_key_pair;
ALTER TABLE public.users ADD CONSTRAINT users_handle_key_pair CHECK ((handle IS NULL) = (handle_key IS NULL));
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_avatar_shape;
ALTER TABLE public.users ADD CONSTRAINT users_avatar_shape CHECK (
  avatar IS NULL OR (jsonb_typeof(avatar) = 'object' AND avatar ? 'kind')
);

CREATE UNIQUE INDEX IF NOT EXISTS users_handle_key_uidx ON public.users (handle_key) WHERE handle_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.delete_user_account(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Посилання без каскаду: хто підтвердив чужу знахідку / схвалив калібрування — лишаємо запис,
  -- без людини.
  UPDATE public.mushroom_picks SET verified_by = NULL WHERE verified_by = p_user_id;
  UPDATE public.calibration_log SET approved_by = NULL WHERE approved_by = p_user_id;
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_user_account(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO service_role;
