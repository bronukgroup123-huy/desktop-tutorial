-- ============================================================================
-- CT-11: Cumulative GDD — gdd_state table + update function
-- Кумулятивний GDD (Growing Degree Days) з 1 січня по регіонах.
-- Таблиця наповнюється cron-джобою (щоденно) або вручну після оновлення погоди.
-- Wave detection використовує cumulative_gdd замість ковзного вікна computeGDD.
-- ============================================================================

-- ─── 1. Таблиця стану GDD ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gdd_state (
  region_id INT NOT NULL REFERENCES public.regions(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  cumulative_gdd NUMERIC(10,2) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (region_id, date)
);

CREATE INDEX IF NOT EXISTS gdd_state_region_idx
  ON public.gdd_state (region_id);
CREATE INDEX IF NOT EXISTS gdd_state_date_idx
  ON public.gdd_state (date);

ALTER TABLE public.gdd_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gdd_state_read ON public.gdd_state;
CREATE POLICY gdd_state_read ON public.gdd_state
  FOR SELECT USING (auth.role() = 'authenticated');

-- ─── 2. Функція оновлення gdd_state для одного регіону на одну дату ───────
-- Викликається з Edge Function (service_role) або cron після отримання
-- денної температури з Open-Meteo.
CREATE OR REPLACE FUNCTION public.upsert_gdd_state(
  p_region_id INT,
  p_date DATE,
  p_temp_max NUMERIC,
  p_temp_min NUMERIC,
  p_base_temp NUMERIC DEFAULT 5
) RETURNS NUMERIC
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_daily_gdd NUMERIC;
  v_prev_cumulative NUMERIC;
  v_new_cumulative NUMERIC;
BEGIN
  -- Денний GDD: max(0, (Tmax + Tmin)/2 - base_temp)
  v_daily_gdd := GREATEST(0, (p_temp_max + p_temp_min) / 2 - p_base_temp);

  -- Отримуємо кумулятивний GDD за попередній день
  SELECT cumulative_gdd INTO v_prev_cumulative
  FROM public.gdd_state
  WHERE region_id = p_region_id AND date = p_date - INTERVAL '1 day';

  IF v_prev_cumulative IS NULL THEN
    v_prev_cumulative := 0;
  END IF;

  v_new_cumulative := v_prev_cumulative + v_daily_gdd;

  -- Upsert
  INSERT INTO public.gdd_state (region_id, date, cumulative_gdd, updated_at)
  VALUES (p_region_id, p_date, v_new_cumulative, now())
  ON CONFLICT (region_id, date) DO UPDATE
    SET cumulative_gdd = EXCLUDED.cumulative_gdd,
        updated_at = now();

  RETURN v_new_cumulative;
END;
$fn$;

COMMENT ON FUNCTION public.upsert_gdd_state(INT, DATE, NUMERIC, NUMERIC, NUMERIC) IS
  'Обчислює денний GDD і оновлює кумулятивний GDD для регіону на дату. Повертає нове значення cumulative_gdd.';

-- ─── 3. Хелпер: отримати cumulative_gdd для регіону на дату ──────────────
CREATE OR REPLACE FUNCTION public.get_gdd_state(
  p_region_id INT,
  p_date DATE
) RETURNS NUMERIC
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_cumulative NUMERIC;
BEGIN
  SELECT cumulative_gdd INTO v_cumulative
  FROM public.gdd_state
  WHERE region_id = p_region_id AND date = p_date;

  IF v_cumulative IS NULL THEN
    RETURN 0;
  END IF;

  RETURN v_cumulative;
END;
$fn$;

COMMENT ON FUNCTION public.get_gdd_state(INT, DATE) IS
  'Повертає кумулятивний GDD для регіону на дату (або 0, якщо ще не обчислено).';

-- ─── 4. RLS trigger ───────────────────────────────────────────────────────
DO $do_gdd_trigger$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'gdd_state_updated_at'
      AND tgrelid = 'public.gdd_state'::regclass
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER gdd_state_updated_at
      BEFORE UPDATE ON public.gdd_state
      FOR EACH ROW
      EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END;
$do_gdd_trigger$;
