-- ============================================================================
-- Сповіщення «Почалась хвиля» (рішення PO 2026-11-15, ADR-015 §15.8 п.19)
--
--  * push_devices — токени FCM пристроїв користувача для сповіщень про ділянки
--    (окремо від пристроїв Наглядача: інша згода й інший зміст сповіщень);
--  * wave_alerts — що вже надіслано: одна хвиля виду в ділянці — одне сповіщення
--    (ключ — день її початку).
-- Розсилає Edge Function v1-wave-alerts раз на день (GitHub Actions за розкладом).
-- Доступ — лише service_role.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.push_devices (
  token TEXT PRIMARY KEY CHECK (char_length(token) BETWEEN 20 AND 4096),
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  wave_alerts BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS push_devices_user_idx ON public.push_devices (user_id);

ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_devices FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_devices FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.wave_alerts (
  area_id UUID NOT NULL REFERENCES public.analysis_areas (id) ON DELETE CASCADE,
  species TEXT NOT NULL,
  wave_start DATE NOT NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (area_id, species, wave_start)
);

ALTER TABLE public.wave_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wave_alerts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.wave_alerts FROM anon, authenticated;

-- Зареєструвати / оновити токен пристрою (токен міг перейти до іншого акаунта — переписуємо).
CREATE OR REPLACE FUNCTION public.register_push_device(p_user_id UUID, p_token TEXT, p_platform TEXT, p_wave_alerts BOOLEAN)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.push_devices AS d (token, user_id, platform, wave_alerts)
  VALUES (p_token, p_user_id, p_platform, COALESCE(p_wave_alerts, true))
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
        wave_alerts = EXCLUDED.wave_alerts, updated_at = now();
$$;

-- Ділянки, власники яких мають пристрій зі ввімкненими сповіщеннями про хвилі.
CREATE OR REPLACE FUNCTION public.wave_alert_targets()
RETURNS TABLE (user_id UUID, tokens TEXT[])
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT d.user_id, array_agg(d.token ORDER BY d.updated_at DESC)
  FROM public.push_devices d
  WHERE d.wave_alerts
    AND EXISTS (SELECT 1 FROM public.analysis_areas a WHERE a.user_id = d.user_id)
  GROUP BY d.user_id;
$$;

-- Позначити хвилю як надіслану; false — уже надсилали (не дублювати).
CREATE OR REPLACE FUNCTION public.claim_wave_alert(p_area_id UUID, p_species TEXT, p_wave_start DATE)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.wave_alerts (area_id, species, wave_start) VALUES (p_area_id, p_species, p_wave_start);
  RETURN true;
EXCEPTION WHEN unique_violation THEN
  RETURN false;
END;
$$;

-- Токен більше не дійсний (FCM: unregistered) — прибрати.
CREATE OR REPLACE FUNCTION public.drop_push_device(p_token TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  DELETE FROM public.push_devices WHERE token = p_token;
$$;

DO $$
DECLARE fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.register_push_device(UUID, TEXT, TEXT, BOOLEAN)',
    'public.wave_alert_targets()',
    'public.claim_wave_alert(UUID, TEXT, DATE)',
    'public.drop_push_device(TEXT)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
