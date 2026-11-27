-- ============================================================================
-- B9.4a: поділитися приватною точкою з другом (ADR-021 §21.5, §21.8)
-- ============================================================================
-- * Автор ділиться СВОЄЮ приватною точкою з вибраними друзями (accepted). Друг бачить її з точним
--   місцем, фото й описом і підписом «від @нік». Видимості `friends` у точок немає (ADR-018).
-- * Відкликати — будь-коли (одному другу або всім). Переслати далі друг не може: ділитися можна
--   лише своєю точкою.
-- * Доступ діє, поки: поширення не відкликане, точка не видалена й лишається приватною, автор і
--   отримувач — друзі. Видалив з друзів чи заблокував — поширення між ними відкликаються назавжди
--   (тригер на friendships): повторна дружба доступ сама не повертає.
-- * Публічну точку не поширюють: її й так бачать усі (зі зсувом).
-- * Ліміт: до 20 активних отримувачів на точку — подарунок друзям, а не розсилка.

CREATE TABLE IF NOT EXISTS public.point_shares (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pick_id      UUID NOT NULL REFERENCES public.mushroom_picks(id) ON DELETE CASCADE,
  owner_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at   TIMESTAMPTZ,
  CHECK (owner_id <> recipient_id)
);
COMMENT ON TABLE public.point_shares IS
  'Поширення приватної точки другу (ADR-021 §21.5). Активне — revoked_at IS NULL. Пише лише service_role через share_pick / revoke_pick_share.';

-- одне активне поширення на пару «точка → друг»
CREATE UNIQUE INDEX IF NOT EXISTS point_shares_active_uq
  ON public.point_shares (pick_id, recipient_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS point_shares_recipient_idx
  ON public.point_shares (recipient_id) WHERE revoked_at IS NULL;

-- RLS: читати — лише власник і отримувач (§21.8); писати — лише сервер.
ALTER TABLE public.point_shares ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.point_shares FROM anon, authenticated;
GRANT SELECT ON public.point_shares TO authenticated;
DROP POLICY IF EXISTS point_shares_select_party ON public.point_shares;
CREATE POLICY point_shares_select_party ON public.point_shares
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) IN (owner_id, recipient_id));

-- ─── Кінець дружби — поширення між двома людьми відкликаються ──────────────
CREATE OR REPLACE FUNCTION public.revoke_shares_on_unfriend()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF OLD.status = 'accepted' AND (TG_OP = 'DELETE' OR NEW.status <> 'accepted') THEN
    UPDATE public.point_shares SET revoked_at = now()
    WHERE revoked_at IS NULL
      AND ((owner_id = OLD.user_a AND recipient_id = OLD.user_b)
        OR (owner_id = OLD.user_b AND recipient_id = OLD.user_a));
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS friendships_revoke_point_shares ON public.friendships;
CREATE TRIGGER friendships_revoke_point_shares
  AFTER UPDATE OF status OR DELETE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.revoke_shares_on_unfriend();

-- ─── Чи бачить отримувач точку зараз ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pick_shared_with(p_pick_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.point_shares s
    JOIN public.mushroom_picks p ON p.id = s.pick_id
    WHERE s.pick_id = p_pick_id AND s.recipient_id = p_user_id AND s.revoked_at IS NULL
      AND p.deleted_at IS NULL AND p.pick_type = 'private'
      AND public.are_friends(s.owner_id, s.recipient_id)
  );
$$;

-- ─── Поділитися ────────────────────────────────────────────────────────────
-- → { ok, shared: <нових>, recipients: <усього активних> } або { ok: false, code, message }
CREATE OR REPLACE FUNCTION public.share_pick(p_user_id UUID, p_pick_id UUID, p_recipient_ids UUID[])
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_max_recipients CONSTANT INT := 20;
  v_pick public.mushroom_picks;
  v_ids UUID[];
  v_new INT := 0;
  v_total INT;
  r UUID;
BEGIN
  SELECT * INTO v_pick FROM public.mushroom_picks
  WHERE id = p_pick_id AND user_id = p_user_id AND deleted_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'pick_not_found', 'message', 'Точку не знайдено');
  END IF;
  IF v_pick.pick_type <> 'private' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_private', 'message',
      'Публічну точку й так бачать усі. Поділитися можна приватною');
  END IF;

  SELECT coalesce(array_agg(DISTINCT x), '{}') INTO v_ids FROM unnest(p_recipient_ids) x WHERE x IS NOT NULL;
  IF cardinality(v_ids) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Оберіть друзів');
  END IF;
  FOREACH r IN ARRAY v_ids LOOP
    IF r = p_user_id OR NOT public.are_friends(p_user_id, r) THEN
      RETURN jsonb_build_object('ok', false, 'code', 'not_friend', 'message',
        'Поділитися можна лише з друзями');
    END IF;
  END LOOP;

  SELECT count(*) INTO v_total FROM public.point_shares s
  WHERE s.pick_id = p_pick_id AND s.revoked_at IS NULL AND NOT (s.recipient_id = ANY (v_ids));
  IF v_total + cardinality(v_ids) > c_max_recipients THEN
    RETURN jsonb_build_object('ok', false, 'code', 'share_limit', 'message',
      format('Точкою можна поділитися щонайбільше з %s друзями', c_max_recipients));
  END IF;

  FOREACH r IN ARRAY v_ids LOOP
    INSERT INTO public.point_shares (pick_id, owner_id, recipient_id)
    VALUES (p_pick_id, p_user_id, r)
    ON CONFLICT (pick_id, recipient_id) WHERE revoked_at IS NULL DO NOTHING;
    IF FOUND THEN v_new := v_new + 1; END IF;
  END LOOP;

  SELECT count(*) INTO v_total FROM public.point_shares s WHERE s.pick_id = p_pick_id AND s.revoked_at IS NULL;
  RETURN jsonb_build_object('ok', true, 'shared', v_new, 'recipients', v_total);
END;
$$;

-- ─── Відкликати: одному другу (p_recipient_id) або всім (NULL) ─────────────
CREATE OR REPLACE FUNCTION public.revoke_pick_share(p_user_id UUID, p_pick_id UUID, p_recipient_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_n INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.mushroom_picks WHERE id = p_pick_id AND user_id = p_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'pick_not_found', 'message', 'Точку не знайдено');
  END IF;
  UPDATE public.point_shares SET revoked_at = now()
  WHERE pick_id = p_pick_id AND owner_id = p_user_id AND revoked_at IS NULL
    AND (p_recipient_id IS NULL OR recipient_id = p_recipient_id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'revoked', v_n);
END;
$$;

-- ─── З ким поділився автор (для картки своєї точки) ────────────────────────
CREATE OR REPLACE FUNCTION public.pick_share_list(p_user_id UUID, p_pick_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'user_id', u.id, 'handle', u.handle, 'avatar', u.avatar,
      'active', public.are_friends(s.owner_id, s.recipient_id)
    ) ORDER BY s.created_at), '[]'::jsonb)
  FROM public.point_shares s
  JOIN public.users u ON u.id = s.recipient_id
  WHERE s.pick_id = p_pick_id AND s.owner_id = p_user_id AND s.revoked_at IS NULL;
$$;

-- ─── Точки, якими поділились зі мною (список, без прив'язки до області) ─────
CREATE OR REPLACE FUNCTION public.picks_shared_with_me(p_user_id UUID, p_limit INT DEFAULT 200)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_agg(x.j ORDER BY x.shared_at DESC), '[]'::jsonb)
  FROM (
    SELECT s.created_at AS shared_at, jsonb_build_object(
      'id', p.id,
      'lat', extensions.ST_Y(p.geom::extensions.geometry),
      'lng', extensions.ST_X(p.geom::extensions.geometry),
      'species_id', p.species_id,
      'name_ua', c.name_ua,
      'from_handle', u.handle,
      'shared_at', s.created_at
    ) AS j
    FROM public.point_shares s
    JOIN public.mushroom_picks p ON p.id = s.pick_id
    JOIN public.users u ON u.id = s.owner_id
    LEFT JOIN public.mushroom_catalog c ON c.id = p.species_id
    WHERE s.recipient_id = p_user_id AND s.revoked_at IS NULL
      AND p.deleted_at IS NULL AND p.pick_type = 'private' AND p.geom IS NOT NULL
      AND public.are_friends(s.owner_id, s.recipient_id)
    ORDER BY s.created_at DESC
    LIMIT LEAST(GREATEST(coalesce(p_limit, 200), 1), 500)
  ) x;
$$;

-- ─── Карта: + точки, якими поділились зі мною (точне місце, «від @нік») ────
CREATE OR REPLACE FUNCTION public.get_picks_map(
  p_user_id UUID,
  p_region_id INT,
  p_min_lng DOUBLE PRECISION DEFAULT NULL,
  p_min_lat DOUBLE PRECISION DEFAULT NULL,
  p_max_lng DOUBLE PRECISION DEFAULT NULL,
  p_max_lat DOUBLE PRECISION DEFAULT NULL,
  p_include_private BOOLEAN DEFAULT false,
  p_limit INT DEFAULT 500
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH region AS (
    SELECT r.polygon FROM public.regions r WHERE r.id = p_region_id
  ),
  bbox AS (
    SELECT CASE WHEN p_min_lng IS NULL THEN NULL
      ELSE extensions.ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326) END AS env
  ),
  shown AS (
    -- Місце, яке бачить саме цей користувач: своє й поширене мені — точне, чуже публічне — зсунуте.
    SELECT
      p.id, p.user_id, p.pick_type, p.verification_status, p.species_id, p.created_at,
      (p.user_id = p_user_id) AS is_mine,
      sh.from_handle,
      CASE WHEN p.user_id = p_user_id OR sh.from_handle IS NOT NULL THEN p.geom ELSE p.display_geom END
        ::extensions.geometry AS place
    FROM public.mushroom_picks p
    LEFT JOIN LATERAL (
      SELECT u.handle AS from_handle
      FROM public.point_shares s JOIN public.users u ON u.id = s.owner_id
      WHERE s.pick_id = p.id AND s.recipient_id = p_user_id AND s.revoked_at IS NULL
        AND p.pick_type = 'private' AND public.are_friends(s.owner_id, s.recipient_id)
      LIMIT 1
    ) sh ON true
    WHERE p.deleted_at IS NULL
      AND (
        (p.user_id = p_user_id AND (p.pick_type = 'public' OR p_include_private))
        OR (p.user_id <> p_user_id AND p.pick_type = 'public' AND p.verification_status <> 'rejected')
        OR (p.user_id <> p_user_id AND sh.from_handle IS NOT NULL)
      )
  ),
  picked AS (
    SELECT s.*
    FROM shown s, region, bbox
    WHERE s.place IS NOT NULL
      AND extensions.ST_Intersects(region.polygon, s.place)
      AND (bbox.env IS NULL OR s.place OPERATOR(extensions.&&) bbox.env)
    ORDER BY s.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 2000) + 1
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', k.id,
    'lat', extensions.ST_Y(k.place),
    'lng', extensions.ST_X(k.place),
    'is_exact', k.is_mine OR k.from_handle IS NOT NULL,
    'is_mine', k.is_mine,
    'pick_type', k.pick_type,
    'verification_status', k.verification_status,
    'species_id', k.species_id,
    'name_ua', c.name_ua,
    'shared_from', k.from_handle
  ) ORDER BY k.created_at DESC), '[]'::jsonb)
  FROM picked k
  LEFT JOIN public.mushroom_catalog c ON c.id = k.species_id;
$$;

-- ─── Картка: поширена мені — точне місце, фото, опис, «від @нік»; будь-яка область ──
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
    'is_exact', s.is_mine OR s.from_handle IS NOT NULL,
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
                               WHERE pc.pick_id = s.id AND pc.counted AND pc.confirmer_id = p_user_id),
    'shared_from', s.from_handle,
    'shared_with', CASE WHEN s.is_mine AND s.pick_type = 'private'
                        THEN public.pick_share_list(p_user_id, s.id) END
  )
  FROM (
    SELECT p.*,
      (p.user_id = p_user_id) AS is_mine,
      sh.from_handle,
      CASE WHEN p.user_id = p_user_id OR sh.from_handle IS NOT NULL THEN p.geom ELSE p.display_geom END
        ::extensions.geometry AS place
    FROM public.mushroom_picks p
    LEFT JOIN LATERAL (
      SELECT u.handle AS from_handle
      FROM public.point_shares ps JOIN public.users u ON u.id = ps.owner_id
      WHERE ps.pick_id = p.id AND ps.recipient_id = p_user_id AND ps.revoked_at IS NULL
        AND p.pick_type = 'private' AND public.are_friends(ps.owner_id, ps.recipient_id)
      LIMIT 1
    ) sh ON true
    WHERE p.id = p_pick_id AND p.deleted_at IS NULL
  ) s
  LEFT JOIN public.mushroom_catalog c ON c.id = s.species_id
  WHERE s.place IS NOT NULL
    AND (
      s.is_mine
      OR s.from_handle IS NOT NULL
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

DO $$
DECLARE f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'revoke_shares_on_unfriend()', 'pick_shared_with(uuid, uuid)', 'share_pick(uuid, uuid, uuid[])', 'revoke_pick_share(uuid, uuid, uuid)',
    'pick_share_list(uuid, uuid)', 'picks_shared_with_me(uuid, integer)',
    'get_picks_map(uuid, integer, double precision, double precision, double precision, double precision, boolean, integer)',
    'get_pick_card(uuid, integer, uuid)'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role', f);
  END LOOP;
END $$;
