-- ============================================================================
-- B3.11: «Знайшли?» — чесний відгук після походу (ADR-014; уточнення ADR-019 §19.9)
-- ============================================================================
-- Коли питаємо: лише після реального походу — людина натиснула «Я вдома». Застосунок передає місце
-- походу (середину треку) і день; сервер сам шукає зв'язок (ADR-014 §14.2):
--   • прогноз ділянки, який людина отримала на цей день (forecast_views), і похід — у межах 5 км від
--     ділянки (від її краю: 5 км + половина сторони від центру); або
--   • завершений похід із Наглядачем (hikes) за останні 12 год, трек якого проходить у межах 5 км.
-- Без зв'язку — `no_trip_context`, відгук не приймаємо. Місце походу НЕ зберігаємо — лише перевіряємо.
--
-- Бали (ADR-012 №2): +2, не більше одного відгуку з балами на добу, лише акаунту (у гостя балів
-- немає, ADR-001), нараховуються через 24 год (cron), якщо довіра не впала нижче порогу.
-- Довіра users.feedback_trust (0…1): «не знайшов» там, де людина того ж дня поставила свою точку з
-- фото, — суперечність: −0,25 і без балів; «знайшов» поруч зі своєю точкою — +0,05.
-- Калібрування: лише «знайшов» (ADR-019 §19.9) з вагою = довіра (calibration_weight); «не знайшов»
-- лишається для людини — у підсумку «Прогноз для вас збувся N з M».

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS feedback_trust NUMERIC(3,2) NOT NULL DEFAULT 1
  CHECK (feedback_trust >= 0 AND feedback_trust <= 1);

-- ─── Які прогнози людина отримала ──────────────────────────────────────────
-- Пише save_analysis_result: кожен результат аналізу ділянки = прогноз, який людина бачила.
CREATE TABLE IF NOT EXISTS public.forecast_views (
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  area_id   UUID NOT NULL REFERENCES public.analysis_areas(id) ON DELETE CASCADE,
  viewed_on DATE NOT NULL,
  center    extensions.geography(Point, 4326) NOT NULL,
  size_km   SMALLINT NOT NULL,
  title     TEXT,
  -- [{ date, level, species }] — рівень і головний вид на кожен день горизонту
  days      JSONB NOT NULL DEFAULT '[]'::jsonb,
  PRIMARY KEY (user_id, area_id, viewed_on)
);
CREATE INDEX IF NOT EXISTS forecast_views_user_day_idx ON public.forecast_views (user_id, viewed_on DESC);
ALTER TABLE public.forecast_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forecast_views FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.forecast_views FROM anon, authenticated;

-- ─── Відгуки ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.trip_feedback (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  trip_day           DATE NOT NULL,
  source             TEXT NOT NULL CHECK (source IN ('forecast', 'hike')),
  area_id            UUID REFERENCES public.analysis_areas(id) ON DELETE SET NULL,
  hike_id            UUID REFERENCES public.hikes(id) ON DELETE SET NULL,
  answer             TEXT NOT NULL CHECK (answer IN ('found', 'not_found')),
  predicted_level    TEXT,
  predicted_species  TEXT,
  calibration_weight NUMERIC(3,2) NOT NULL DEFAULT 0,
  points             TEXT NOT NULL CHECK (points IN ('pending', 'awarded', 'none')),
  points_reason      TEXT,
  award_after        TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- один відгук на похід: на день — за ділянку, за похід із Наглядачем — раз
CREATE UNIQUE INDEX IF NOT EXISTS trip_feedback_user_day_area_uniq
  ON public.trip_feedback (user_id, trip_day, area_id) WHERE source = 'forecast';
CREATE UNIQUE INDEX IF NOT EXISTS trip_feedback_user_hike_uniq
  ON public.trip_feedback (user_id, hike_id) WHERE source = 'hike';
CREATE INDEX IF NOT EXISTS trip_feedback_user_time_idx ON public.trip_feedback (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS trip_feedback_pending_idx ON public.trip_feedback (award_after) WHERE points = 'pending';
ALTER TABLE public.trip_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_feedback FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.trip_feedback FROM anon, authenticated;

-- нове джерело балів у журналі
ALTER TABLE public.rating_events DROP CONSTRAINT IF EXISTS rating_events_reason_check;
ALTER TABLE public.rating_events ADD CONSTRAINT rating_events_reason_check
  CHECK (reason IN ('pick_exif', 'trip_feedback'));
ALTER TABLE public.rating_events ADD COLUMN IF NOT EXISTS feedback_id UUID
  REFERENCES public.trip_feedback(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS rating_events_feedback_uniq ON public.rating_events (feedback_id)
  WHERE feedback_id IS NOT NULL;

-- ─── Результат аналізу → прогноз, який людина бачила ──────────────────────
CREATE OR REPLACE FUNCTION public.save_analysis_result(p_user_id UUID, p_area_id UUID, p_result JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_area public.analysis_areas;
BEGIN
  UPDATE public.analysis_areas
  SET last_result = p_result, last_analyzed_at = now(), updated_at = now()
  WHERE id = p_area_id AND user_id = p_user_id
  RETURNING * INTO v_area;
  IF NOT FOUND THEN RETURN; END IF;

  INSERT INTO public.forecast_views (user_id, area_id, viewed_on, center, size_km, title, days)
  VALUES (
    p_user_id, p_area_id, (now() AT TIME ZONE 'Europe/Kyiv')::date, v_area.center, v_area.size_km,
    coalesce(v_area.label, p_result->'area'->>'title'),
    coalesce((
      SELECT jsonb_agg(jsonb_build_object('date', d->>'date', 'level', d->>'level',
        'species', d->'top1'->>'mushroom_type'))
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_result->'days') = 'array' THEN p_result->'days' ELSE '[]'::jsonb END) d
      WHERE d ? 'date'
    ), '[]'::jsonb)
  )
  ON CONFLICT (user_id, area_id, viewed_on) DO UPDATE
    SET days = EXCLUDED.days, title = EXCLUDED.title, center = EXCLUDED.center, size_km = EXCLUDED.size_km;
END;
$$;
REVOKE ALL ON FUNCTION public.save_analysis_result(UUID, UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_analysis_result(UUID, UUID, JSONB) TO service_role;

-- ─── Зв'язок походу з прогнозом / Наглядачем ───────────────────────────────
-- Найкращий зв'язок для походу в точці (lat, lng) дня p_day: прогноз ділянки (найсвіжіший перегляд
-- до дня походу, не старший за 3 дні, з цим днем у горизонті) або похід із Наглядачем.
CREATE OR REPLACE FUNCTION public.trip_feedback_context(
  p_user_id UUID, p_day DATE, p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION
)
RETURNS TABLE (source TEXT, area_id UUID, hike_id UUID, title TEXT, predicted_level TEXT, predicted_species TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH here AS (
    SELECT extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography AS g
  ),
  fv AS (
    SELECT 'forecast'::TEXT AS source, v.area_id, NULL::UUID AS hike_id, v.title,
           d->>'level' AS predicted_level, d->>'species' AS predicted_species, 1 AS prio, v.viewed_on
    FROM public.forecast_views v
    CROSS JOIN here
    CROSS JOIN LATERAL jsonb_array_elements(v.days) d
    WHERE v.user_id = p_user_id
      AND v.viewed_on BETWEEN p_day - 3 AND p_day
      AND d->>'date' = p_day::TEXT
      AND extensions.ST_DWithin(v.center, here.g, 5000 + v.size_km * 500)
  ),
  hk AS (
    SELECT 'hike'::TEXT, NULL::UUID, h.id, NULL::TEXT, NULL::TEXT, NULL::TEXT, 2, p_day
    FROM public.hikes h CROSS JOIN here
    WHERE h.owner_id = p_user_id
      AND h.status = 'closed'
      AND h.closed_at > now() - INTERVAL '12 hours'
      AND EXISTS (
        SELECT 1 FROM public.hike_points pt
        WHERE pt.hike_id = h.id
          AND extensions.ST_DWithin(
            extensions.ST_SetSRID(extensions.ST_MakePoint(pt.lng, pt.lat), 4326)::extensions.geography, here.g, 5000)
      )
  )
  SELECT source, area_id, hike_id, title, predicted_level, predicted_species
  FROM (SELECT * FROM fv UNION ALL SELECT * FROM hk) c
  ORDER BY prio, viewed_on DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.trip_feedback_context(UUID, DATE, DOUBLE PRECISION, DOUBLE PRECISION)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trip_feedback_context(UUID, DATE, DOUBLE PRECISION, DOUBLE PRECISION)
  TO service_role;

-- ─── «Прогноз для вас збувся N з M» ────────────────────────────────────────
-- Збувся: прогноз «є шанс» (середня, висока, пік) і знайшли, або «мало / немає даних» і не знайшли.
CREATE OR REPLACE FUNCTION public.trip_feedback_accuracy(p_user_id UUID)
RETURNS TABLE (hits INT, total INT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    count(*) FILTER (WHERE (f.predicted_level IN ('medium', 'high', 'peak')) = (f.answer = 'found'))::INT,
    count(*)::INT
  FROM public.trip_feedback f
  WHERE f.user_id = p_user_id AND f.predicted_level IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.trip_feedback_accuracy(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trip_feedback_accuracy(UUID) TO service_role;

-- ─── Прийняти відгук ───────────────────────────────────────────────────────
-- → { ok, code?, message?, points: pending|none, points_reason, source, predicted_level }
CREATE OR REPLACE FUNCTION public.submit_trip_feedback(
  p_user_id UUID,
  p_is_guest BOOLEAN,
  p_day DATE,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_answer TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_trust_min CONSTANT NUMERIC := 0.5;
  v_today DATE := (now() AT TIME ZONE 'Europe/Kyiv')::date;
  v_ctx RECORD;
  v_trust NUMERIC;
  v_own_pick BOOLEAN;
  v_points TEXT := 'none';
  v_reason TEXT;
  v_id UUID;
BEGIN
  IF p_answer IS NULL OR p_answer NOT IN ('found', 'not_found') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Відповідь — found або not_found');
  END IF;
  IF p_day IS NULL OR p_day > v_today OR p_day < v_today - 1 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Відгук — за сьогодні або вчора');
  END IF;

  -- як і бали за точки: послідовно для одного користувача (ліміт «один на добу» без гонок)
  PERFORM pg_advisory_xact_lock(hashtextextended('trip_feedback:' || p_user_id::TEXT, 0));

  SELECT * INTO v_ctx FROM public.trip_feedback_context(p_user_id, p_day, p_lat, p_lng);
  IF v_ctx.source IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'no_trip_context', 'message',
      'Цей похід не біля жодної вашої ділянки прогнозу, тож відповідь не врахуємо. Наступного разу перед виходом подивіться прогноз ділянки поруч.');
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.trip_feedback f
    WHERE f.user_id = p_user_id
      AND ((v_ctx.source = 'forecast' AND f.source = 'forecast' AND f.trip_day = p_day AND f.area_id = v_ctx.area_id)
        OR (v_ctx.source = 'hike' AND f.source = 'hike' AND f.hike_id = v_ctx.hike_id))
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'already_answered', 'message', 'Ви вже відповіли про цей похід. Дякуємо!');
  END IF;

  -- своя точка з фото того ж дня поруч — перевірка чесності
  SELECT EXISTS (
    SELECT 1 FROM public.mushroom_picks p
    WHERE p.user_id = p_user_id
      AND p.captured_at IS NOT NULL
      AND (p.captured_at AT TIME ZONE 'Europe/Kyiv')::date = p_day
      AND extensions.ST_DWithin(p.geom,
        extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography, 5000)
  ) INTO v_own_pick;

  SELECT u.feedback_trust INTO v_trust FROM public.users u WHERE u.id = p_user_id FOR UPDATE;
  IF v_trust IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Профіль не знайдено');
  END IF;
  IF v_own_pick AND p_answer = 'not_found' THEN
    v_trust := greatest(0, v_trust - 0.25);
    v_reason := 'contradiction';
  ELSIF v_own_pick AND p_answer = 'found' THEN
    v_trust := least(1, v_trust + 0.05);
  END IF;
  UPDATE public.users SET feedback_trust = v_trust WHERE id = p_user_id;

  IF v_reason IS NULL THEN
    IF p_is_guest THEN
      v_reason := 'guest';
    ELSIF v_trust < c_trust_min THEN
      v_reason := 'low_trust';
    ELSIF EXISTS (
      SELECT 1 FROM public.trip_feedback f
      WHERE f.user_id = p_user_id AND f.points IN ('pending', 'awarded')
        AND (f.created_at AT TIME ZONE 'Europe/Kyiv')::date = v_today
    ) THEN
      v_reason := 'daily_limit';
    ELSE
      v_points := 'pending';
    END IF;
  END IF;

  INSERT INTO public.trip_feedback (user_id, trip_day, source, area_id, hike_id, answer, predicted_level,
    predicted_species, calibration_weight, points, points_reason, award_after)
  VALUES (p_user_id, p_day, v_ctx.source, v_ctx.area_id, v_ctx.hike_id, p_answer, v_ctx.predicted_level,
    v_ctx.predicted_species, CASE WHEN p_answer = 'found' THEN v_trust ELSE 0 END, v_points, v_reason,
    CASE WHEN v_points = 'pending' THEN now() + INTERVAL '24 hours' END)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'source', v_ctx.source, 'title', v_ctx.title,
    'predicted_level', v_ctx.predicted_level, 'points', v_points, 'points_reason', v_reason);
END;
$$;
REVOKE ALL ON FUNCTION public.submit_trip_feedback(UUID, BOOLEAN, DATE, DOUBLE PRECISION, DOUBLE PRECISION, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_trip_feedback(UUID, BOOLEAN, DATE, DOUBLE PRECISION, DOUBLE PRECISION, TEXT)
  TO service_role;

-- ─── Відкладене нарахування (+2 через 24 год) ──────────────────────────────
-- Довіра впала нижче порогу за цю добу — балів немає. Повертає кількість нарахованих.
CREATE OR REPLACE FUNCTION public.award_due_trip_feedback()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_trust_min CONSTANT NUMERIC := 0.5;
  r RECORD;
  n INT := 0;
BEGIN
  FOR r IN
    SELECT f.id, f.user_id, u.feedback_trust
    FROM public.trip_feedback f JOIN public.users u ON u.id = f.user_id
    WHERE f.points = 'pending' AND f.award_after <= now()
    ORDER BY f.award_after
    LIMIT 1000
    FOR UPDATE OF f SKIP LOCKED
  LOOP
    IF r.feedback_trust >= c_trust_min THEN
      INSERT INTO public.rating_events (user_id, delta, reason, feedback_id)
      VALUES (r.user_id, 2, 'trip_feedback', r.id)
      ON CONFLICT DO NOTHING;
      UPDATE public.trip_feedback SET points = 'awarded' WHERE id = r.id;
      n := n + 1;
    ELSE
      UPDATE public.trip_feedback SET points = 'none', points_reason = 'low_trust' WHERE id = r.id;
    END IF;
  END LOOP;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.award_due_trip_feedback() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.award_due_trip_feedback() TO service_role;

DO $$
BEGIN
  PERFORM cron.unschedule('trip-feedback-award');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
SELECT cron.schedule('trip-feedback-award', '23 * * * *', $$ SELECT public.award_due_trip_feedback(); $$);
