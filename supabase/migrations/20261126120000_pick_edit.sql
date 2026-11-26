-- ============================================================================
-- B3.4: автор змінює свою точку (видимість, опис) і видаляє її (soft delete)
-- ============================================================================
-- Фото й вид після створення не змінюються. Зміна видимості проходить ті самі правила, що й
-- створення (ADR-010/011/019 §19.10):
--   • private → public: потрібен вид (не «Не знаю»), рівень «Лісовик»+ і тижневий ліміт публічних;
--   • public → private: не більше 5 приватних одночасно.
-- Тижневий ліміт публічних рахується за датою ПУБЛІКАЦІЇ (`published_at`), а не створення —
-- інакше стару приватну точку можна було б зробити публічною в обхід ліміту. Повернення в
-- приватні дату публікації не стирає: «опублікував → сховав → опублікував» ліміт не обходить.

ALTER TABLE public.mushroom_picks ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;
UPDATE public.mushroom_picks SET published_at = created_at WHERE pick_type = 'public' AND published_at IS NULL;

-- Дата публікації ставиться автоматично: при створенні публічної точки і при перемиканні на public.
CREATE OR REPLACE FUNCTION public.mushroom_picks_set_published_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.pick_type = 'public' AND (TG_OP = 'INSERT' OR OLD.pick_type IS DISTINCT FROM 'public') THEN
    NEW.published_at := now();
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.mushroom_picks_set_published_at() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS mushroom_picks_published_at ON public.mushroom_picks;
CREATE TRIGGER mushroom_picks_published_at
  BEFORE INSERT OR UPDATE OF pick_type ON public.mushroom_picks
  FOR EACH ROW EXECUTE FUNCTION public.mushroom_picks_set_published_at();

-- ─── Ліміти: публічні — за датою публікації ────────────────────────────────
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
    -- за датою публікації; рахуються й видалені та знову сховані
    SELECT count(*) INTO v_count FROM public.mushroom_picks p
    WHERE p.user_id = p_user_id AND p.published_at > now() - INTERVAL '7 days';
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
REVOKE ALL ON FUNCTION public.can_create_pick(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_create_pick(UUID, TEXT) TO service_role;

-- ─── Зміна своєї точки ─────────────────────────────────────────────────────
-- p_visibility NULL — видимість не змінюється; p_set_description — чи змінювати опис (NULL = прибрати).
-- p_display_lat/lng — зсунуте місце для public (рахує сервер, ADR-018 §18.5).
CREATE OR REPLACE FUNCTION public.update_pick(
  p_user_id UUID,
  p_pick_id UUID,
  p_visibility TEXT DEFAULT NULL,
  p_set_description BOOLEAN DEFAULT false,
  p_description TEXT DEFAULT NULL,
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
  v_count INT;
  v_limit RECORD;
  c_private_at_once CONSTANT INT := 5;
BEGIN
  -- те саме блокування, що й у create_pick: ліміти рахуються без гонок
  PERFORM pg_advisory_xact_lock(hashtextextended('create_pick:' || p_user_id::TEXT, 0));

  SELECT * INTO v_pick FROM public.mushroom_picks
  WHERE id = p_pick_id AND user_id = p_user_id AND deleted_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'pick_not_found', 'message', 'Точку не знайдено');
  END IF;

  IF p_visibility IS NOT NULL AND p_visibility NOT IN ('private', 'public') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Видимість точки — private або public');
  END IF;

  IF p_visibility = 'public' AND v_pick.pick_type <> 'public' THEN
    IF v_pick.species_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'species_required', 'message',
        'Щоб зробити точку публічною, у неї має бути вид. «Не знаю» — лише для приватних точок.');
    END IF;
    IF p_display_lat IS NULL OR p_display_lng IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Немає зсунутого місця для публічної точки');
    END IF;
    SELECT * INTO v_limit FROM public.can_create_pick(p_user_id, 'public');
    IF NOT v_limit.allowed THEN
      RETURN jsonb_build_object('ok', false, 'code', v_limit.code, 'message', v_limit.message);
    END IF;
    UPDATE public.mushroom_picks SET
      pick_type = 'public',
      display_geom = extensions.ST_SetSRID(extensions.ST_MakePoint(p_display_lng, p_display_lat), 4326)::extensions.geography
    WHERE id = v_pick.id;
  ELSIF p_visibility = 'private' AND v_pick.pick_type <> 'private' THEN
    SELECT count(*) INTO v_count FROM public.mushroom_picks p
    WHERE p.user_id = p_user_id AND p.pick_type = 'private' AND p.deleted_at IS NULL;
    IF v_count >= c_private_at_once THEN
      RETURN jsonb_build_object('ok', false, 'code', 'private_limit_reached', 'message',
        format('У вас %s з %s приватних точок — видаліть одну, щоб сховати цю.', v_count, c_private_at_once));
    END IF;
    UPDATE public.mushroom_picks SET pick_type = 'private', display_geom = NULL WHERE id = v_pick.id;
  END IF;

  IF p_set_description THEN
    UPDATE public.mushroom_picks SET description = p_description WHERE id = v_pick.id;
  END IF;

  SELECT * INTO v_pick FROM public.mushroom_picks WHERE id = p_pick_id;
  RETURN jsonb_build_object('ok', true, 'pick', jsonb_build_object(
    'id', v_pick.id, 'pick_type', v_pick.pick_type, 'verification_status', v_pick.verification_status,
    'description', v_pick.description
  ));
END;
$$;
REVOKE ALL ON FUNCTION public.update_pick(UUID, UUID, TEXT, BOOLEAN, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_pick(UUID, UUID, TEXT, BOOLEAN, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)
  TO service_role;

-- ─── Видалення своєї точки (soft delete) ───────────────────────────────────
-- true — видалено зараз; false — немає такої своєї неудаленої точки.
CREATE OR REPLACE FUNCTION public.delete_pick(p_user_id UUID, p_pick_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.mushroom_picks SET deleted_at = now()
  WHERE id = p_pick_id AND user_id = p_user_id AND deleted_at IS NULL;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_pick(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_pick(UUID, UUID) TO service_role;
