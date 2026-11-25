-- ============================================================================
-- PROD-001a: джерела балів, рівні й ліміти точок (B3.7 + B3.2; ADR-012, ADR-013, ADR-019 §19.10)
-- Специфікація — docs/tasks/NEXT_TASK.md.
--
--  * rating_events — журнал балів; users.rating = сума журналу (не нижче 0), рахує тригер;
--  * users.knowledge_certified_at / curriculum_version — сертифікат знань (видаватиме B3.10);
--  * level_of(rating, certified) — рівень ADR-013 (ті самі межі, що levelOf у profile-rules.ts);
--  * перше джерело балів (ADR-012 №3): приватна точка з успішною перевіркою EXIF → +1, не більше
--    5 за 7 днів. Ознака EXIF — з ai_check, який будує сервер (v1-picks перезаписує ключ exif);
--  * can_create_pick за ADR-019 §19.10: публічні — з «Лісовика» (7 за 7 днів), «Хранитель лісу» і
--    вище — 15 за 7 днів; приватні — до 5 одночасно і не більше 10 нових за 7 днів.
-- Тиждень — ковзні 7 діб. Pro-ліміти — окремо (B6.3).
-- ============================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS knowledge_certified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS curriculum_version TEXT;

CREATE TABLE IF NOT EXISTS public.rating_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  delta INT NOT NULL CHECK (delta BETWEEN -1000 AND 1000 AND delta <> 0),
  reason TEXT NOT NULL CHECK (reason IN ('pick_exif')),
  pick_id UUID REFERENCES public.mushroom_picks (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rating_events_user_time_idx ON public.rating_events (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS rating_events_pick_reason_uniq ON public.rating_events (pick_id, reason)
  WHERE pick_id IS NOT NULL;

ALTER TABLE public.rating_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rating_events FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.rating_events FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rating_events FROM authenticated;
DROP POLICY IF EXISTS rating_events_read_own ON public.rating_events;
CREATE POLICY rating_events_read_own ON public.rating_events
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- users.rating = сума журналу, не нижче 0
CREATE OR REPLACE FUNCTION public.rating_events_apply()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  UPDATE public.users u
  SET rating = greatest(0, (SELECT coalesce(sum(e.delta), 0) FROM public.rating_events e WHERE e.user_id = NEW.user_id))
  WHERE u.id = NEW.user_id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS rating_events_apply ON public.rating_events;
CREATE TRIGGER rating_events_apply AFTER INSERT ON public.rating_events
  FOR EACH ROW EXECUTE FUNCTION public.rating_events_apply();
REVOKE ALL ON FUNCTION public.rating_events_apply() FROM PUBLIC, anon, authenticated;

-- Рівень ADR-013 §13.1 (межі — як levelOf у supabase/functions/_shared/v1/profile-rules.ts)
CREATE OR REPLACE FUNCTION public.level_of(p_rating INT, p_certified BOOLEAN DEFAULT false)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN coalesce(p_rating, 0) >= 1001 THEN CASE WHEN coalesce(p_certified, false) THEN 'master' ELSE 'keeper' END
    WHEN p_rating >= 501 THEN 'keeper'
    WHEN p_rating >= 201 THEN 'forester'
    WHEN p_rating >= 51 THEN CASE WHEN coalesce(p_certified, false) THEN 'expert' ELSE 'tracker' END
    ELSE 'traveler'
  END;
$$;

-- ─── Ліміти створення точок (ADR-019 §19.10) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.can_create_pick(p_user_id UUID, p_visibility TEXT)
RETURNS TABLE (allowed BOOLEAN, code TEXT, message TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_level TEXT;
  v_count INT;
  v_week_limit INT;
  c_private_at_once CONSTANT INT := 5;    -- приватних одночасно (free; Pro — 15, B6.3)
  c_private_new_week CONSTANT INT := 10;  -- нових приватних за 7 днів
BEGIN
  IF p_visibility IS NULL OR p_visibility NOT IN ('private', 'public') THEN
    RETURN QUERY SELECT false, 'validation_error'::TEXT, 'Видимість точки — private або public'::TEXT;
    RETURN;
  END IF;

  IF p_visibility = 'public' THEN
    SELECT public.level_of(u.rating, u.knowledge_certified_at IS NOT NULL) INTO v_level
    FROM public.users u WHERE u.id = p_user_id;
    v_week_limit := CASE coalesce(v_level, 'traveler')
      WHEN 'forester' THEN 7 WHEN 'keeper' THEN 15 WHEN 'master' THEN 15 ELSE 0 END;
    IF v_week_limit = 0 THEN
      RETURN QUERY SELECT false, 'level_required'::TEXT,
        'Публічні точки — з рівня «Лісовик». Поки що зробіть приватний тук-тук.'::TEXT;
      RETURN;
    END IF;
    -- рахуються й видалені: створив → видалив → створив не обходить ліміт
    SELECT count(*) INTO v_count FROM public.mushroom_picks p
    WHERE p.user_id = p_user_id AND p.pick_type = 'public' AND p.created_at > now() - INTERVAL '7 days';
    IF v_count >= v_week_limit THEN
      RETURN QUERY SELECT false, 'weekly_limit_reached'::TEXT,
        format('Ліміт — %s публічних точок за 7 днів. Спробуйте пізніше або зробіть приватний тук-тук.', v_week_limit);
      RETURN;
    END IF;
    RETURN QUERY SELECT true, NULL::TEXT, NULL::TEXT;
    RETURN;
  END IF;

  SELECT count(*) INTO v_count FROM public.mushroom_picks p
  WHERE p.user_id = p_user_id AND p.pick_type = 'private' AND p.deleted_at IS NULL;
  IF v_count >= c_private_at_once THEN
    RETURN QUERY SELECT false, 'private_limit_reached'::TEXT,
      format('У вас %s з %s приватних точок — видаліть одну, щоб додати нову.', v_count, c_private_at_once);
    RETURN;
  END IF;

  SELECT count(*) INTO v_count FROM public.mushroom_picks p
  WHERE p.user_id = p_user_id AND p.pick_type = 'private' AND p.created_at > now() - INTERVAL '7 days';
  IF v_count >= c_private_new_week THEN
    RETURN QUERY SELECT false, 'weekly_limit_reached'::TEXT,
      format('Ліміт — %s нових приватних точок за 7 днів. Спробуйте пізніше.', c_private_new_week);
    RETURN;
  END IF;

  RETURN QUERY SELECT true, NULL::TEXT, NULL::TEXT;
END;
$$;

-- ─── Атомарне створення точки + бал за EXIF (ADR-012 №3) ───────────────────
CREATE OR REPLACE FUNCTION public.create_pick(
  p_id UUID,
  p_user_id UUID,
  p_client_id UUID,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_photo_path TEXT,
  p_visibility TEXT,
  p_species_id TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_ai_check JSONB DEFAULT NULL,
  p_twin_alert BOOLEAN DEFAULT false,
  p_captured_at TIMESTAMPTZ DEFAULT NULL,
  p_display_lat DOUBLE PRECISION DEFAULT NULL,
  p_display_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pick public.mushroom_picks;
  v_limit RECORD;
  v_awarded INT;
  c_exif_points_week CONSTANT INT := 5;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('create_pick:' || p_user_id::TEXT, 0));

  SELECT * INTO v_pick
  FROM public.mushroom_picks
  WHERE user_id = p_user_id AND client_id = p_client_id;

  IF NOT FOUND THEN
    SELECT * INTO v_limit FROM public.can_create_pick(p_user_id, p_visibility);
    IF NOT v_limit.allowed THEN
      RETURN jsonb_build_object(
        'allowed', false, 'created', false, 'code', v_limit.code, 'message', v_limit.message
      );
    END IF;

    INSERT INTO public.mushroom_picks (
      id, user_id, client_id, geom, display_geom, photo_url,
      mushroom_type, species_id, description, ai_check, twin_alert,
      pick_type, verification_status, captured_at
    ) VALUES (
      p_id, p_user_id, p_client_id,
      extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography,
      CASE WHEN p_visibility = 'public' THEN
        extensions.ST_SetSRID(extensions.ST_MakePoint(p_display_lng, p_display_lat), 4326)::extensions.geography
      END,
      p_photo_path,
      COALESCE(p_species_id, 'unknown'),  -- сумісність зі старим кодом прогнозу
      p_species_id, p_description, p_ai_check, COALESCE(p_twin_alert, false),
      p_visibility, 'pending', p_captured_at
    )
    RETURNING * INTO v_pick;

    -- +1 за приватну точку з фото, знятим на місці (EXIF перевірив сервер), до 5 за 7 днів
    IF p_visibility = 'private' AND coalesce((p_ai_check -> 'exif' ->> 'verified')::boolean, false) THEN
      SELECT count(*) INTO v_awarded FROM public.rating_events e
      WHERE e.user_id = p_user_id AND e.reason = 'pick_exif' AND e.created_at > now() - INTERVAL '7 days';
      IF v_awarded < c_exif_points_week THEN
        INSERT INTO public.rating_events (user_id, delta, reason, pick_id) VALUES (p_user_id, 1, 'pick_exif', v_pick.id);
      END IF;
    END IF;

    RETURN jsonb_build_object('allowed', true, 'created', true, 'pick', jsonb_build_object(
      'id', v_pick.id, 'pick_type', v_pick.pick_type, 'verification_status', v_pick.verification_status
    ));
  END IF;

  RETURN jsonb_build_object('allowed', true, 'created', false, 'pick', jsonb_build_object(
    'id', v_pick.id, 'pick_type', v_pick.pick_type, 'verification_status', v_pick.verification_status
  ));
END;
$$;
