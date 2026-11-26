-- ============================================================================
-- B3.8b: підтвердження відповіддю знахідкою — не зараховується, якщо місце підмінене програмою
-- ============================================================================
-- Застосунок передає з точкою ознаку Android «mock location» (Position.isMocked). confirm_pick зараховує
-- відповідь, лише коли телефон прямо сказав, що місце справжнє (mocked = false):
--   • mocked = true  → mock_location (знахідку збережено як звичайну точку, підтвердження немає);
--   • ознаки немає  → location_unknown (старий застосунок).
-- Решта правил — як у 20261126150000_pick_confirmations.

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
  -- B3.8b: телефон має прямо сказати, що місце НЕ підмінене (Android mock location); не сказав — не зараховуємо
  ELSIF (v_reply.ai_check->'location'->>'mocked') = 'true' THEN
    v_reason := 'mock_location';
  ELSIF (v_reply.ai_check->'location'->>'mocked') IS DISTINCT FROM 'false' THEN
    v_reason := 'location_unknown';
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

