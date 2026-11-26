-- ============================================================================
-- B3.8a: публічна точка сіра → підтверджена відповіддю знахідкою (ADR-019 §19.5)
-- ============================================================================
-- Окремої групи перевіряльників немає. Точку підтверджує ІНШИЙ грибник рівня «Лісовик»+, створивши
-- свою публічну точку-відповідь (фото камерою + повідомлення) того самого виду в межах 200 м від
-- справжнього місця. Відповідь — звичайна публічна точка: тижневий ліміт і всі перевірки створення.
--
-- Захист зсунутого місця (ADR-018 §18.5): чужим видно точку лише зі зсувом 300–500 м. Відстань
-- перевіряється вже ПІСЛЯ створення відповіді (кожна спроба витрачає публічну точку з тижневого
-- ліміту) і не більше 2 спроб на одну чужу точку — тож вгадати справжнє місце перебором не вийде.
--
-- Зарахування: фото з перевіреним місцем (EXIF), той самий вид, ≤ 200 м; взаємні підтвердження тих самих
-- двох людей — не більше 3 за 30 днів. Точка стає «Підтверджена» після 1 зарахованої відповіді;
-- з twin_alert (на телефоні видно отруйного двійника) — після 2.
-- Бали (ADR-012 №4, §19.5 п.7): тому, хто підтвердив, +3 (до 3 на добу); автору +2 (до 10 на добу).

ALTER TABLE public.mushroom_picks ADD COLUMN IF NOT EXISTS reply_to UUID
  REFERENCES public.mushroom_picks(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.pick_confirmations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pick_id       UUID NOT NULL REFERENCES public.mushroom_picks(id) ON DELETE CASCADE,
  confirmer_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  author_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reply_pick_id UUID NOT NULL UNIQUE REFERENCES public.mushroom_picks(id) ON DELETE CASCADE,
  counted       BOOLEAN NOT NULL,
  reason        TEXT,   -- чому не зараховано: too_far | exif_unverified | pair_limit | already_confirmed
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- одна зарахована відповідь людини на точку
CREATE UNIQUE INDEX IF NOT EXISTS pick_confirmations_counted_uniq
  ON public.pick_confirmations (pick_id, confirmer_id) WHERE counted;
CREATE INDEX IF NOT EXISTS pick_confirmations_pick_idx ON public.pick_confirmations (pick_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pick_confirmations_pair_idx ON public.pick_confirmations (confirmer_id, author_id, created_at DESC);
ALTER TABLE public.pick_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pick_confirmations FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pick_confirmations FROM anon, authenticated;

-- нові джерела балів (разом з усіма попередніми)
ALTER TABLE public.rating_events DROP CONSTRAINT IF EXISTS rating_events_reason_check;
ALTER TABLE public.rating_events ADD CONSTRAINT rating_events_reason_check
  CHECK (reason IN ('pick_exif', 'trip_feedback', 'pick_confirm', 'pick_confirmed'));

-- ─── Рання перевірка (до створення відповіді; без відстані) ────────────────
-- → { allowed, code?, message? }
CREATE OR REPLACE FUNCTION public.can_confirm_pick(p_user_id UUID, p_target_id UUID, p_species_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_max_attempts CONSTANT INT := 2;
  v_target public.mushroom_picks;
  v_name TEXT;
BEGIN
  SELECT * INTO v_target FROM public.mushroom_picks
  WHERE id = p_target_id AND deleted_at IS NULL AND pick_type = 'public' AND verification_status <> 'rejected';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'pick_not_found', 'message', 'Точку не знайдено');
  END IF;
  IF v_target.user_id = p_user_id THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'own_pick', 'message', 'Свою точку підтвердити не можна');
  END IF;
  IF v_target.species_id IS DISTINCT FROM p_species_id THEN
    SELECT c.name_ua INTO v_name FROM public.mushroom_catalog c WHERE c.id = v_target.species_id;
    RETURN jsonb_build_object('allowed', false, 'code', 'species_mismatch', 'message',
      format('Підтвердити можна знахідкою того самого виду: «%s»', coalesce(v_name, v_target.species_id)));
  END IF;
  IF EXISTS (SELECT 1 FROM public.pick_confirmations c
             WHERE c.pick_id = p_target_id AND c.confirmer_id = p_user_id AND c.counted) THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'already_confirmed', 'message', 'Ви вже підтвердили цю точку');
  END IF;
  IF (SELECT count(*) FROM public.pick_confirmations c
      WHERE c.pick_id = p_target_id AND c.confirmer_id = p_user_id) >= c_max_attempts THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'attempts_exhausted', 'message',
      'Спроби підтвердити цю точку вичерпано');
  END IF;
  RETURN jsonb_build_object('allowed', true);
END;
$$;
REVOKE ALL ON FUNCTION public.can_confirm_pick(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_confirm_pick(UUID, UUID, TEXT) TO service_role;

-- ─── Зарахувати відповідь (після створення точки-відповіді) ─────────────────
-- → { ok, counted, reason?, confirmations, verified, code?, message? }
CREATE OR REPLACE FUNCTION public.confirm_pick(p_user_id UUID, p_target_id UUID, p_reply_pick_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_radius_m CONSTANT INT := 200;
  c_pair_limit CONSTANT INT := 3;      -- взаємних зарахувань тих самих двох людей за 30 днів
  c_confirmer_daily CONSTANT INT := 3; -- +3 тому, хто підтвердив (ADR-012 №4)
  c_author_daily CONSTANT INT := 10;   -- +2 автору (ADR-019 §19.5 п.7)
  v_today_start TIMESTAMPTZ := date_trunc('day', now() AT TIME ZONE 'Europe/Kyiv') AT TIME ZONE 'Europe/Kyiv';
  v_check JSONB;
  v_target public.mushroom_picks;
  v_reply public.mushroom_picks;
  v_reason TEXT;
  v_count INT;
  v_needed INT;
  v_verified BOOLEAN := false;
BEGIN
  -- як і створення точок: послідовно для того, хто підтверджує (ліміти без гонок)
  PERFORM pg_advisory_xact_lock(hashtextextended('create_pick:' || p_user_id::TEXT, 0));

  SELECT * INTO v_reply FROM public.mushroom_picks
  WHERE id = p_reply_pick_id AND user_id = p_user_id AND deleted_at IS NULL AND pick_type = 'public';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'pick_not_found', 'message', 'Точку-відповідь не знайдено');
  END IF;
  v_check := public.can_confirm_pick(p_user_id, p_target_id, v_reply.species_id);
  IF NOT (v_check->>'allowed')::boolean THEN
    RETURN jsonb_build_object('ok', false, 'code', v_check->>'code', 'message', v_check->>'message');
  END IF;
  SELECT * INTO v_target FROM public.mushroom_picks WHERE id = p_target_id FOR UPDATE;

  IF NOT extensions.ST_DWithin(v_target.geom, v_reply.geom, c_radius_m) THEN
    v_reason := 'too_far';
  ELSIF coalesce((v_reply.ai_check->'exif'->>'verified')::boolean, false) IS NOT TRUE THEN
    v_reason := 'exif_unverified';
  ELSIF (SELECT count(*) FROM public.pick_confirmations c
         WHERE c.counted AND c.created_at > now() - INTERVAL '30 days'
           AND ((c.confirmer_id = p_user_id AND c.author_id = v_target.user_id)
             OR (c.confirmer_id = v_target.user_id AND c.author_id = p_user_id))) >= c_pair_limit THEN
    v_reason := 'pair_limit';
  END IF;

  INSERT INTO public.pick_confirmations (pick_id, confirmer_id, author_id, reply_pick_id, counted, reason)
  VALUES (p_target_id, p_user_id, v_target.user_id, p_reply_pick_id, v_reason IS NULL, v_reason);
  UPDATE public.mushroom_picks SET reply_to = p_target_id WHERE id = p_reply_pick_id;

  SELECT count(*) INTO v_count FROM public.pick_confirmations c WHERE c.pick_id = p_target_id AND c.counted;

  IF v_reason IS NULL THEN
    v_needed := CASE WHEN v_target.twin_alert THEN 2 ELSE 1 END;
    IF v_count >= v_needed AND v_target.verification_status = 'pending' THEN
      UPDATE public.mushroom_picks SET verification_status = 'verified', verified_by = p_user_id
      WHERE id = p_target_id;
      v_verified := true;
    END IF;
    -- бали: тому, хто підтвердив (+3, до 3 на добу), і автору (+2, до 10 на добу)
    IF (SELECT count(*) FROM public.rating_events e
        WHERE e.user_id = p_user_id AND e.reason = 'pick_confirm' AND e.created_at >= v_today_start) < c_confirmer_daily THEN
      INSERT INTO public.rating_events (user_id, delta, reason, pick_id)
      VALUES (p_user_id, 3, 'pick_confirm', p_reply_pick_id) ON CONFLICT DO NOTHING;
    END IF;
    IF (SELECT count(*) FROM public.rating_events e
        WHERE e.user_id = v_target.user_id AND e.reason = 'pick_confirmed' AND e.created_at >= v_today_start) < c_author_daily THEN
      INSERT INTO public.rating_events (user_id, delta, reason, pick_id)
      VALUES (v_target.user_id, 2, 'pick_confirmed', p_reply_pick_id) ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'counted', v_reason IS NULL, 'reason', v_reason,
    'confirmations', v_count,
    'verified', v_verified OR (SELECT verification_status = 'verified' FROM public.mushroom_picks WHERE id = p_target_id));
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_pick(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pick(UUID, UUID, UUID) TO service_role;

-- ─── Картка: «Підтвердили N грибників, останнє — <дата>» ────────────────────
CREATE OR REPLACE FUNCTION public.get_pick_card(p_user_id UUID, p_region_id INT, p_pick_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'id', s.id,
    'lat', extensions.ST_Y(s.place),
    'lng', extensions.ST_X(s.place),
    'is_exact', s.is_mine,
    'is_mine', s.is_mine,
    'pick_type', s.pick_type,
    'verification_status', s.verification_status,
    'species_id', s.species_id,
    'name_ua', c.name_ua,
    'description', s.description,
    'photo_path', s.photo_url,
    'taken_at', COALESCE(s.captured_at, s.created_at),
    'twin_alert', s.twin_alert,
    'confirmations', (SELECT count(*) FROM public.pick_confirmations pc WHERE pc.pick_id = s.id AND pc.counted),
    'last_confirmed_at', (SELECT max(pc.created_at) FROM public.pick_confirmations pc WHERE pc.pick_id = s.id AND pc.counted),
    'confirmed_by_me', EXISTS (SELECT 1 FROM public.pick_confirmations pc
                               WHERE pc.pick_id = s.id AND pc.counted AND pc.confirmer_id = p_user_id)
  )
  FROM (
    SELECT p.*,
      (p.user_id = p_user_id) AS is_mine,
      CASE WHEN p.user_id = p_user_id THEN p.geom ELSE p.display_geom END::extensions.geometry AS place
    FROM public.mushroom_picks p
    WHERE p.id = p_pick_id AND p.deleted_at IS NULL
  ) s
  LEFT JOIN public.mushroom_catalog c ON c.id = s.species_id
  WHERE s.place IS NOT NULL
    AND (
      s.is_mine
      OR (
        s.pick_type = 'public'
        AND s.verification_status <> 'rejected'
        AND EXISTS (
          SELECT 1 FROM public.regions r
          WHERE r.id = p_region_id AND extensions.ST_Intersects(r.polygon, s.place)
        )
      )
    );
$$;
COMMENT ON FUNCTION public.get_pick_card(UUID, INT, UUID)
  IS 'Картка точки: своя — з точними координатами; чужа публічна — лише display_geom; підтвердження (B3.8). Тільки service_role.';
REVOKE ALL ON FUNCTION public.get_pick_card(UUID, INT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pick_card(UUID, INT, UUID) TO service_role;
