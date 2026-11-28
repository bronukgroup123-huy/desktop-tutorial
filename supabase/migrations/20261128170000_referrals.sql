-- ============================================================================
-- B9.5a: запрошення в застосунок (ADR-021 §21.4, ADR-012 №5)
-- ============================================================================
-- * У кожного акаунта з ніком — свій код (8 символів без схожих 0/O, 1/I). Посилання веде лише в
--   Google Play; код приходить у застосунок через Play Install Referrer (без вебсторінок і даних).
-- * Код активують у перші 14 днів акаунта, один раз; свій код — ні; між заблокованими — ні.
--   Активувати може й гість (Install Referrer приходить при першому запуску, до входу).
-- * Запрошений автоматично стає другом запрошувача, щойно має акаунт (не гість), — без запиту.
-- * Бонус +10 балів ОБОМ — коли запрошений має акаунт і завершив перший похід (закритий похід
--   «Я вдома» або відгук «Знайшли?» після походу), а не за встановлення — проти накруток.
--   Запрошувач отримує бонус щонайбільше 5 разів за весь час; запрошений — один раз.
-- * «Спори» за запрошення (+50 обом, §21.6) — разом із B9.6.
-- * Друзів і бали нараховує cron `award_due_referrals` (щогодини).

CREATE TABLE IF NOT EXISTS public.referral_codes (
  user_id    UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  code       TEXT NOT NULL UNIQUE CHECK (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.referrals (
  invitee_id  UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  inviter_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  friended_at TIMESTAMPTZ,
  rewarded_at TIMESTAMPTZ,
  CHECK (inviter_id <> invitee_id)
);
CREATE INDEX IF NOT EXISTS referrals_inviter_idx ON public.referrals (inviter_id);
CREATE INDEX IF NOT EXISTS referrals_pending_idx ON public.referrals (created_at) WHERE rewarded_at IS NULL;

ALTER TABLE public.referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.referral_codes, public.referrals FROM anon, authenticated;

-- бали за запрошення — у журналі рейтингу, один раз на пару «хто отримує → за кого»
ALTER TABLE public.rating_events DROP CONSTRAINT IF EXISTS rating_events_reason_check;
ALTER TABLE public.rating_events ADD CONSTRAINT rating_events_reason_check
  CHECK (reason IN ('pick_exif', 'trip_feedback', 'pick_confirm', 'pick_confirmed', 'quiz_module', 'referral'));
ALTER TABLE public.rating_events ADD COLUMN IF NOT EXISTS referral_invitee_id UUID
  REFERENCES public.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS rating_events_referral_uniq ON public.rating_events (user_id, referral_invitee_id)
  WHERE referral_invitee_id IS NOT NULL;

-- ─── Друзі за запрошенням: одразу accepted, якщо пари ще немає, ніхто не заблокований і є місце ──
CREATE OR REPLACE FUNCTION public.referral_make_friends(p_inviter UUID, p_invitee UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE c_max_friends CONSTANT INT := 200;
BEGIN
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = p_invitee AND coalesce(is_anonymous, false)) THEN
    RETURN false; -- у гостя немає друзів (ADR-001) — після входу
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.friendships f
       WHERE f.user_a = LEAST(p_inviter, p_invitee) AND f.user_b = GREATEST(p_inviter, p_invitee))
     AND public.friend_count(p_inviter) < c_max_friends
     AND public.friend_count(p_invitee) < c_max_friends THEN
    INSERT INTO public.friendships (user_a, user_b, status, requested_by, responded_at)
    VALUES (LEAST(p_inviter, p_invitee), GREATEST(p_inviter, p_invitee), 'accepted', p_inviter, now())
    ON CONFLICT DO NOTHING;
  END IF;
  UPDATE public.referrals SET friended_at = now() WHERE invitee_id = p_invitee AND friended_at IS NULL;
  RETURN true;
END;
$$;

-- ─── Мій код (створюється за потреби) і підсумок ───────────────────────────
CREATE OR REPLACE FUNCTION public.my_referral_code(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_alphabet CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c_max_bonuses CONSTANT INT := 5;
  v_code TEXT;
  v_try INT := 0;
  v_invited INT;
  v_rewarded INT;
BEGIN
  SELECT code INTO v_code FROM public.referral_codes WHERE user_id = p_user_id;
  WHILE v_code IS NULL AND v_try < 20 LOOP
    v_try := v_try + 1;
    SELECT string_agg(substr(c_alphabet, 1 + floor(random() * length(c_alphabet))::int, 1), '')
      INTO v_code FROM generate_series(1, 8);
    BEGIN
      INSERT INTO public.referral_codes (user_id, code) VALUES (p_user_id, v_code);
    EXCEPTION WHEN unique_violation THEN
      SELECT code INTO v_code FROM public.referral_codes WHERE user_id = p_user_id; -- паралельний запит або колізія
    END;
  END LOOP;
  IF v_code IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'code_unavailable', 'message', 'Не вдалося створити код — спробуйте пізніше');
  END IF;
  SELECT count(*), count(*) FILTER (WHERE rewarded_at IS NOT NULL) INTO v_invited, v_rewarded
  FROM public.referrals WHERE inviter_id = p_user_id;
  RETURN jsonb_build_object('ok', true, 'code', v_code, 'invited', v_invited, 'rewarded', v_rewarded,
    'bonuses_left', greatest(0, c_max_bonuses - v_rewarded));
END;
$$;

-- ─── Активувати код запрошення ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.redeem_referral(p_invitee_id UUID, p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_window CONSTANT INTERVAL := INTERVAL '14 days';
  v_inviter UUID;
  v_handle TEXT;
  v_created TIMESTAMPTZ;
BEGIN
  SELECT rc.user_id, u.handle INTO v_inviter, v_handle
  FROM public.referral_codes rc JOIN public.users u ON u.id = rc.user_id
  WHERE rc.code = upper(btrim(p_code));
  IF v_inviter IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'invalid_code', 'message', 'Код запрошення не знайдено');
  END IF;
  IF v_inviter = p_invitee_id THEN
    RETURN jsonb_build_object('ok', false, 'code', 'own_code', 'message', 'Це ваш власний код');
  END IF;
  IF EXISTS (SELECT 1 FROM public.referrals WHERE invitee_id = p_invitee_id) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'already_redeemed', 'message', 'Запрошення вже прийнято раніше');
  END IF;
  SELECT created_at INTO v_created FROM auth.users WHERE id = p_invitee_id;
  IF v_created IS NULL OR v_created < now() - c_window THEN
    RETURN jsonb_build_object('ok', false, 'code', 'too_late', 'message',
      'Код запрошення діє лише в перші 14 днів після встановлення');
  END IF;
  IF public.is_blocked_between(v_inviter, p_invitee_id) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'invalid_code', 'message', 'Код запрошення не знайдено');
  END IF;

  INSERT INTO public.referrals (invitee_id, inviter_id) VALUES (p_invitee_id, v_inviter)
  ON CONFLICT (invitee_id) DO NOTHING;
  -- уже з акаунтом — друзі одразу; гість — після входу (cron)
  RETURN jsonb_build_object('ok', true, 'inviter_handle', v_handle,
    'friends_now', public.referral_make_friends(v_inviter, p_invitee_id));
END;
$$;

-- ─── Друзі й бонуси (cron) ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.award_due_referrals()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_bonus CONSTANT INT := 10;
  c_max_bonuses CONSTANT INT := 5;
  r RECORD;
  n INT := 0;
  v_registered BOOLEAN;
  v_hiked BOOLEAN;
BEGIN
  FOR r IN
    SELECT rf.invitee_id, rf.inviter_id, rf.friended_at, rf.rewarded_at
    FROM public.referrals rf
    WHERE rf.friended_at IS NULL OR rf.rewarded_at IS NULL
    ORDER BY rf.created_at
    LIMIT 1000
    FOR UPDATE OF rf SKIP LOCKED
  LOOP
    SELECT NOT coalesce(au.is_anonymous, false) INTO v_registered FROM auth.users au WHERE au.id = r.invitee_id;
    CONTINUE WHEN NOT coalesce(v_registered, false);

    -- 1) автоматично друзі (без запиту)
    IF r.friended_at IS NULL THEN
      PERFORM public.referral_make_friends(r.inviter_id, r.invitee_id);
    END IF;

    -- 2) бонус обом — після першого походу запрошеного
    IF r.rewarded_at IS NULL THEN
      SELECT EXISTS (SELECT 1 FROM public.hikes h
                     WHERE h.owner_id = r.invitee_id AND h.status = 'closed' AND h.closed_reason IN ('home', 'auto'))
          OR EXISTS (SELECT 1 FROM public.trip_feedback tf WHERE tf.user_id = r.invitee_id)
        INTO v_hiked;
      IF v_hiked AND NOT public.is_blocked_between(r.inviter_id, r.invitee_id) THEN
        INSERT INTO public.rating_events (user_id, delta, reason, referral_invitee_id)
        VALUES (r.invitee_id, c_bonus, 'referral', r.invitee_id)
        ON CONFLICT DO NOTHING;
        IF (SELECT count(*) FROM public.rating_events e
            WHERE e.user_id = r.inviter_id AND e.reason = 'referral') < c_max_bonuses THEN
          INSERT INTO public.rating_events (user_id, delta, reason, referral_invitee_id)
          VALUES (r.inviter_id, c_bonus, 'referral', r.invitee_id)
          ON CONFLICT DO NOTHING;
        END IF;
        UPDATE public.referrals SET rewarded_at = now() WHERE invitee_id = r.invitee_id;
        n := n + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN n;
END;
$$;

DO $$
DECLARE f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY['referral_make_friends(uuid, uuid)', 'my_referral_code(uuid)', 'redeem_referral(uuid, text)', 'award_due_referrals()'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role', f);
  END LOOP;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('referrals-award');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
SELECT cron.schedule('referrals-award', '41 * * * *', $$ SELECT public.award_due_referrals(); $$);
