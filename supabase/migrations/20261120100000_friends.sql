-- ============================================================================
-- Друзі (ADR-021 §21.1, §21.8; BACKEND_PLAN B9.2)
--
--  * friendships — одна пара користувачів — один рядок (user_a < user_b):
--      pending  — запит від requested_by, чекає відповіді;
--      accepted — друзі (взаємно);
--      declined — відхилено: повторний запит від того самого — не раніше ніж за 30 днів;
--      blocked  — blocked_by заблокував: усе зникає в обидва боки (профіль, пошук, запити).
--    Видалити з друзів / скасувати запит / розблокувати — рядок видаляється (без повідомлення).
--  * friend_request_log — коли надіслано запит (антиспам: до 20 нових запитів на добу);
--  * user_reports — скарги на користувача (розбирає підтримка).
-- Логіка й ліміти — у friend_action (атомарно, з блокуванням пари); доступ — лише service_role
-- (Edge Function v1-friends перевіряє акаунт і гостя). Клієнт напряму таблиць не читає й не пише.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.friendships (
  user_a UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  user_b UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'declined', 'blocked')),
  requested_by UUID NOT NULL,
  blocked_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_a, user_b),
  CONSTRAINT friendships_ordered CHECK (user_a < user_b),
  CONSTRAINT friendships_requester CHECK (requested_by IN (user_a, user_b)),
  CONSTRAINT friendships_blocker CHECK (
    (status = 'blocked') = (blocked_by IS NOT NULL) AND (blocked_by IS NULL OR blocked_by IN (user_a, user_b))
  )
);

CREATE INDEX IF NOT EXISTS friendships_b_idx ON public.friendships (user_b, status);
CREATE INDEX IF NOT EXISTS friendships_a_idx ON public.friendships (user_a, status);

CREATE TABLE IF NOT EXISTS public.friend_request_log (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS friend_request_log_user_idx ON public.friend_request_log (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.user_reports (
  id BIGSERIAL PRIMARY KEY,
  reporter_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  reason TEXT NOT NULL CHECK (reason IN ('spam', 'abuse', 'impersonation', 'inappropriate', 'other')),
  comment TEXT CHECK (comment IS NULL OR char_length(comment) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT user_reports_not_self CHECK (reporter_id <> target_id)
);
CREATE INDEX IF NOT EXISTS user_reports_target_idx ON public.user_reports (target_id, created_at DESC);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.friend_request_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_request_log FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_reports FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.friendships, public.friend_request_log, public.user_reports FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.friend_request_log_id_seq, public.user_reports_id_seq FROM anon, authenticated;

-- Учасник бачить свої пари, крім тих, де його заблокували (блок ховає все в обидва боки).
-- Запис — лише через friend_action (service_role).
DROP POLICY IF EXISTS friendships_member_read ON public.friendships;
CREATE POLICY friendships_member_read ON public.friendships
  FOR SELECT TO authenticated
  USING (
    public.is_registered()
    AND auth.uid() IN (user_a, user_b)
    AND (blocked_by IS NULL OR blocked_by = auth.uid())
  );
GRANT SELECT ON public.friendships TO authenticated;

-- ─── Ліміти (ADR-021 §21.1) ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.friend_limits()
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT '{"daily_requests": 20, "max_friends": 200, "retry_after_decline_days": 30}'::jsonb;
$$;

-- Чи заблоковано пару (в будь-який бік) — для пошуку й публічного профілю.
CREATE OR REPLACE FUNCTION public.is_blocked_between(p_a UUID, p_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.user_a = LEAST(p_a, p_b) AND f.user_b = GREATEST(p_a, p_b) AND f.status = 'blocked'
  );
$$;

-- Чи друзі (accepted) — для Наглядача, поділитися точкою, коментарів.
CREATE OR REPLACE FUNCTION public.are_friends(p_a UUID, p_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.user_a = LEAST(p_a, p_b) AND f.user_b = GREATEST(p_a, p_b) AND f.status = 'accepted'
  );
$$;

CREATE OR REPLACE FUNCTION public.friend_count(p_user UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::int FROM public.friendships f
  WHERE (f.user_a = p_user OR f.user_b = p_user) AND f.status = 'accepted';
$$;

-- ─── Дії ───────────────────────────────────────────────────────────────────
-- p_action: request | accept | decline | cancel | remove | block | unblock.
-- Відповідь: { ok: true, relation, notify } або { ok: false, code, message }.
--   relation — none | outgoing | incoming | friends | blocked (з погляду p_user);
--   notify   — кому що надіслати push: 'request' (запит отримувачу), 'accepted' (тому, хто
--              запитував), null — нічого (відхилення, видалення, блок — мовчки).
CREATE OR REPLACE FUNCTION public.friend_action(p_user UUID, p_target UUID, p_action TEXT, p_now TIMESTAMPTZ DEFAULT now())
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  lim CONSTANT JSONB := public.friend_limits();
  a UUID := LEAST(p_user, p_target);
  b UUID := GREATEST(p_user, p_target);
  r public.friendships%ROWTYPE;
  sent INT;
BEGIN
  IF p_user IS NULL OR p_target IS NULL OR p_user = p_target THEN
    RETURN jsonb_build_object('ok', false, 'code', 'invalid_target', 'message', 'Не можна додати себе');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_target) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'user_not_found', 'message', 'Користувача не знайдено');
  END IF;

  -- Одна пара — одна транзакція за раз (два зустрічні запити одночасно не створять двох рядків).
  PERFORM pg_advisory_xact_lock(hashtextextended(a::text || b::text, 0));
  SELECT * INTO r FROM public.friendships f WHERE f.user_a = a AND f.user_b = b;

  -- Мене заблокували — для мене цієї людини немає.
  IF FOUND AND r.status = 'blocked' AND r.blocked_by <> p_user THEN
    RETURN jsonb_build_object('ok', false, 'code', 'user_not_found', 'message', 'Користувача не знайдено');
  END IF;

  IF p_action = 'block' THEN
    INSERT INTO public.friendships (user_a, user_b, status, requested_by, blocked_by, updated_at)
    VALUES (a, b, 'blocked', p_user, p_user, p_now)
    ON CONFLICT (user_a, user_b) DO UPDATE
      SET status = 'blocked', blocked_by = p_user, updated_at = p_now;
    RETURN jsonb_build_object('ok', true, 'relation', 'blocked', 'notify', null);
  END IF;

  IF p_action = 'unblock' THEN
    IF FOUND AND r.status = 'blocked' THEN
      DELETE FROM public.friendships f WHERE f.user_a = a AND f.user_b = b;
    END IF;
    RETURN jsonb_build_object('ok', true, 'relation', 'none', 'notify', null);
  END IF;

  IF FOUND AND r.status = 'blocked' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'blocked_by_you', 'message', 'Ви заблокували цього користувача. Спершу розблокуйте');
  END IF;

  IF p_action = 'request' THEN
    IF FOUND AND r.status = 'accepted' THEN
      RETURN jsonb_build_object('ok', true, 'relation', 'friends', 'notify', null);
    END IF;
    IF FOUND AND r.status = 'pending' AND r.requested_by = p_user THEN
      RETURN jsonb_build_object('ok', true, 'relation', 'outgoing', 'notify', null);
    END IF;
    IF FOUND AND r.status = 'pending' THEN
      -- Зустрічний запит: людина вже просила дружити — це «Прийняти».
      p_action := 'accept';
    ELSE
      IF FOUND AND r.status = 'declined' AND r.requested_by = p_user
         AND r.responded_at > p_now - make_interval(days => (lim->>'retry_after_decline_days')::int) THEN
        RETURN jsonb_build_object('ok', false, 'code', 'request_cooldown', 'message',
          'Запит відхилено. Повторити можна з ' ||
          to_char((r.responded_at + make_interval(days => (lim->>'retry_after_decline_days')::int)) AT TIME ZONE 'Europe/Kyiv', 'DD.MM.YYYY'));
      END IF;
      SELECT count(*) INTO sent FROM public.friend_request_log l
      WHERE l.user_id = p_user AND l.created_at > p_now - interval '1 day';
      IF sent >= (lim->>'daily_requests')::int THEN
        RETURN jsonb_build_object('ok', false, 'code', 'daily_limit', 'message',
          'Забагато запитів за добу (до ' || (lim->>'daily_requests') || '). Спробуйте завтра');
      END IF;
      IF public.friend_count(p_user) >= (lim->>'max_friends')::int THEN
        RETURN jsonb_build_object('ok', false, 'code', 'friends_limit', 'message',
          'У вас уже ' || (lim->>'max_friends') || ' друзів — це максимум');
      END IF;
      INSERT INTO public.friendships (user_a, user_b, status, requested_by, created_at, updated_at, responded_at)
      VALUES (a, b, 'pending', p_user, p_now, p_now, NULL)
      ON CONFLICT (user_a, user_b) DO UPDATE
        SET status = 'pending', requested_by = p_user, created_at = p_now, updated_at = p_now, responded_at = NULL;
      INSERT INTO public.friend_request_log (user_id, created_at) VALUES (p_user, p_now);
      RETURN jsonb_build_object('ok', true, 'relation', 'outgoing', 'notify', 'request');
    END IF;
  END IF;

  IF p_action = 'accept' THEN
    IF NOT FOUND OR r.status <> 'pending' OR r.requested_by = p_user THEN
      IF FOUND AND r.status = 'accepted' THEN
        RETURN jsonb_build_object('ok', true, 'relation', 'friends', 'notify', null);
      END IF;
      RETURN jsonb_build_object('ok', false, 'code', 'no_request', 'message', 'Запиту в друзі немає');
    END IF;
    IF public.friend_count(p_user) >= (lim->>'max_friends')::int THEN
      RETURN jsonb_build_object('ok', false, 'code', 'friends_limit', 'message',
        'У вас уже ' || (lim->>'max_friends') || ' друзів — це максимум');
    END IF;
    IF public.friend_count(p_target) >= (lim->>'max_friends')::int THEN
      RETURN jsonb_build_object('ok', false, 'code', 'friends_limit_other', 'message',
        'У цього користувача вже максимум друзів');
    END IF;
    UPDATE public.friendships f SET status = 'accepted', responded_at = p_now, updated_at = p_now
    WHERE f.user_a = a AND f.user_b = b;
    RETURN jsonb_build_object('ok', true, 'relation', 'friends', 'notify', 'accepted');
  END IF;

  IF p_action = 'decline' THEN
    IF FOUND AND r.status = 'pending' AND r.requested_by <> p_user THEN
      UPDATE public.friendships f SET status = 'declined', responded_at = p_now, updated_at = p_now
      WHERE f.user_a = a AND f.user_b = b;
    END IF;
    RETURN jsonb_build_object('ok', true, 'relation', 'none', 'notify', null);
  END IF;

  IF p_action = 'cancel' THEN
    IF FOUND AND r.status = 'pending' AND r.requested_by = p_user THEN
      DELETE FROM public.friendships f WHERE f.user_a = a AND f.user_b = b;
    END IF;
    RETURN jsonb_build_object('ok', true, 'relation', 'none', 'notify', null);
  END IF;

  IF p_action = 'remove' THEN
    IF FOUND AND r.status = 'accepted' THEN
      DELETE FROM public.friendships f WHERE f.user_a = a AND f.user_b = b;
    END IF;
    RETURN jsonb_build_object('ok', true, 'relation', 'none', 'notify', null);
  END IF;

  RETURN jsonb_build_object('ok', false, 'code', 'invalid_action', 'message', 'Невідома дія');
END;
$$;

-- Стан пари з погляду p_user (для публічного профілю): none | outgoing | incoming | friends |
-- declined_by_them (як none, але повтор пізніше) | blocked (я заблокував) | hidden (мене заблокували).
CREATE OR REPLACE FUNCTION public.friend_relation(p_user UUID, p_target UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT CASE
      WHEN f.status = 'accepted' THEN 'friends'
      WHEN f.status = 'blocked' AND f.blocked_by = p_user THEN 'blocked'
      WHEN f.status = 'blocked' THEN 'hidden'
      WHEN f.status = 'pending' AND f.requested_by = p_user THEN 'outgoing'
      WHEN f.status = 'pending' THEN 'incoming'
      ELSE 'none'
    END
    FROM public.friendships f
    WHERE f.user_a = LEAST(p_user, p_target) AND f.user_b = GREATEST(p_user, p_target)
  ), 'none');
$$;

-- Мої друзі, запити й заблоковані — одним запитом (для екрана «Друзі»).
-- kind: friend | incoming | outgoing | blocked. Дані профілю — нік, ім'я, аватар, рейтинг.
CREATE OR REPLACE FUNCTION public.friend_list(p_user UUID)
RETURNS TABLE (kind TEXT, id UUID, handle TEXT, name TEXT, avatar JSONB, rating INT, since TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    CASE
      WHEN f.status = 'accepted' THEN 'friend'
      WHEN f.status = 'blocked' THEN 'blocked'
      WHEN f.requested_by = p_user THEN 'outgoing'
      ELSE 'incoming'
    END,
    u.id, u.handle, u.name, u.avatar, u.rating,
    COALESCE(f.responded_at, f.created_at)
  FROM public.friendships f
  JOIN public.users u ON u.id = CASE WHEN f.user_a = p_user THEN f.user_b ELSE f.user_a END
  WHERE (f.user_a = p_user OR f.user_b = p_user)
    AND (f.status IN ('accepted', 'pending') OR (f.status = 'blocked' AND f.blocked_by = p_user))
  ORDER BY 1, COALESCE(f.responded_at, f.created_at) DESC;
$$;

-- Пошук за @ніком (початок ніка, без урахування великих літер); без мене, без гостей і без
-- заблокованих у будь-який бік. Не за телефоном чи email (ADR-021 §21.1).
CREATE OR REPLACE FUNCTION public.search_users_by_handle(p_user UUID, p_prefix TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE (id UUID, handle TEXT, name TEXT, avatar JSONB, rating INT, relation TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.id, u.handle, u.name, u.avatar, u.rating, public.friend_relation(p_user, u.id)
  FROM public.users u
  WHERE u.handle_key IS NOT NULL
    AND u.handle_key LIKE replace(replace(replace(p_prefix, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    AND u.id <> p_user
    AND NOT public.is_blocked_between(p_user, u.id)
  ORDER BY (u.handle_key = p_prefix) DESC, char_length(u.handle_key), u.handle_key
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
$$;

CREATE INDEX IF NOT EXISTS users_handle_key_prefix_idx ON public.users (handle_key text_pattern_ops)
  WHERE handle_key IS NOT NULL;

REVOKE ALL ON FUNCTION public.friend_limits() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_blocked_between(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.are_friends(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.friend_count(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.friend_action(UUID, UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.friend_relation(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.friend_list(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.search_users_by_handle(UUID, TEXT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.friend_limits() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_blocked_between(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.are_friends(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.friend_count(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.friend_action(UUID, UUID, TEXT, TIMESTAMPTZ) TO service_role;
GRANT EXECUTE ON FUNCTION public.friend_relation(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.friend_list(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.search_users_by_handle(UUID, TEXT, INT) TO service_role;

-- Пристрій для сповіщень друзів і Наглядача (без зміни налаштування «Почалась хвиля»):
-- новий токен — без сповіщень про хвилі, наявний — лише прив'язка до акаунта.
CREATE OR REPLACE FUNCTION public.register_push_device_social(p_user_id UUID, p_token TEXT, p_platform TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.push_devices AS d (token, user_id, platform, wave_alerts)
  VALUES (p_token, p_user_id, p_platform, false)
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
        wave_alerts = CASE WHEN d.user_id = EXCLUDED.user_id THEN d.wave_alerts ELSE false END,
        updated_at = now();
$$;
REVOKE ALL ON FUNCTION public.register_push_device_social(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_device_social(UUID, TEXT, TEXT) TO service_role;

-- Токени пристроїв користувача (для push друзям і Наглядачам).
CREATE OR REPLACE FUNCTION public.push_tokens_of(p_user UUID)
RETURNS TEXT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(array_agg(d.token ORDER BY d.updated_at DESC), '{}') FROM public.push_devices d WHERE d.user_id = p_user;
$$;
REVOKE ALL ON FUNCTION public.push_tokens_of(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.push_tokens_of(UUID) TO service_role;
