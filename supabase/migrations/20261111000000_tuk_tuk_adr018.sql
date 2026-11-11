-- ============================================================================
-- B3.0 + B3.1 — бекенд «Тук-тук» (ADR-002, ADR-018; ліміти ADR-010/011/013)
--
--  1. Видимість точки — лише private / public (friends і shared_with скасовано).
--  2. Нові колонки: client_id (ідемпотентність офлайн-черги), species_id (вид із
--     довідника; NULL = «Не знаю»), description, ai_check (підказка ШІ з телефону),
--     twin_alert, display_geom (зсунуте місце для чужих очей), captured_at, deleted_at.
--  3. Закрито витік точних координат (ADR-018 §18.5): через RLS видно тільки власні
--     точки. Чужі public віддає лише Edge Function (service_role) і лише display_geom.
--  4. Запис у mushroom_picks — тільки через Edge Functions (service_role): інакше
--     ліміти й правило «публічні — з рівня Лісовик» обходились би прямим INSERT.
--  5. can_create_pick() — ліміти до появи Pro і рівнів; create_pick() — атомарна
--     вставка (перевірка client_id і ліміту без гонок між паралельними запитами).
-- ============================================================================

-- ─── 1. Видимість: тільки private / public ─────────────────────────────────
UPDATE public.mushroom_picks SET pick_type = 'private' WHERE pick_type = 'friends';
UPDATE public.mushroom_picks SET shared_with = '{}' WHERE shared_with <> '{}';

-- Старий CHECK був безіменним (ім'я згенерував Postgres) — знаходимо його за змістом.
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.mushroom_picks'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%pick_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.mushroom_picks DROP CONSTRAINT %I', c.conname);
  END LOOP;
END
$$;

COMMENT ON COLUMN public.mushroom_picks.shared_with IS
  'Застаріло (ADR-018): друзів немає, колонка завжди порожня. Поширення точок — у груповій поїздці (ADR-017 §17.7).';

-- ─── 2. Нові колонки ───────────────────────────────────────────────────────
ALTER TABLE public.mushroom_picks
  ADD COLUMN IF NOT EXISTS client_id UUID,
  ADD COLUMN IF NOT EXISTS species_id TEXT
    REFERENCES public.mushroom_catalog (id) ON UPDATE CASCADE,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS ai_check JSONB,
  ADD COLUMN IF NOT EXISTS twin_alert BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS display_geom extensions.geography(Point, 4326),
  ADD COLUMN IF NOT EXISTS captured_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.mushroom_picks.client_id IS
  'UUID від клієнта — ключ ідемпотентності офлайн-черги (унікальний у межах user_id).';
COMMENT ON COLUMN public.mushroom_picks.species_id IS
  'Вид із довідника. NULL = «Не знаю, що це» (така точка може бути лише приватною).';
COMMENT ON COLUMN public.mushroom_picks.ai_check IS
  'Підказка локального ШІ з телефону (не доказ) + результат серверної перевірки EXIF.';
COMMENT ON COLUMN public.mushroom_picks.twin_alert IS
  'ШІ на телефоні побачив отруйного двійника — точка ніколи не підтверджується автоматично.';
COMMENT ON COLUMN public.mushroom_picks.display_geom IS
  'Місце публічної точки для чужих очей: стабільний зсув 300–500 м (ADR-018 §18.5). Точний geom — лише автору.';
COMMENT ON COLUMN public.mushroom_picks.captured_at IS
  'Час зйомки на пристрої (created_at — час, коли точка дійшла до сервера).';
COMMENT ON COLUMN public.mushroom_picks.deleted_at IS
  'М''яке видалення. Видалені точки не враховуються в лімітах і не показуються.';

-- ─── 3. Наявні дані приводимо до нових правил ──────────────────────────────
-- Вид: старі точки зберігали id виду в mushroom_type.
UPDATE public.mushroom_picks p
SET species_id = p.mushroom_type
WHERE p.species_id IS NULL
  AND EXISTS (SELECT 1 FROM public.mushroom_catalog c WHERE c.id = p.mushroom_type);

-- Публічна точка без виду з довідника неможлива (ADR-018 §18.3) → стає приватною.
UPDATE public.mushroom_picks
SET pick_type = 'private'
WHERE pick_type = 'public' AND species_id IS NULL;

-- Старі публічні точки отримують зсунуте місце (зсув випадковий і зберігається назавжди).
UPDATE public.mushroom_picks
SET display_geom = extensions.ST_Project(geom, 303 + random() * 194, radians(random() * 360))
WHERE pick_type = 'public' AND display_geom IS NULL;

-- ─── 4. Обмеження ──────────────────────────────────────────────────────────
ALTER TABLE public.mushroom_picks
  DROP CONSTRAINT IF EXISTS mushroom_picks_pick_type_check,
  DROP CONSTRAINT IF EXISTS mushroom_picks_description_length_check,
  DROP CONSTRAINT IF EXISTS mushroom_picks_public_species_check,
  DROP CONSTRAINT IF EXISTS mushroom_picks_public_display_check,
  DROP CONSTRAINT IF EXISTS mushroom_picks_user_client_key;

ALTER TABLE public.mushroom_picks
  ADD CONSTRAINT mushroom_picks_pick_type_check
    CHECK (pick_type IN ('private', 'public')),
  ADD CONSTRAINT mushroom_picks_description_length_check
    CHECK (description IS NULL OR char_length(description) <= 500),
  -- «Не знаю, що це» — лише приватна точка.
  ADD CONSTRAINT mushroom_picks_public_species_check
    CHECK (pick_type <> 'public' OR species_id IS NOT NULL),
  -- У публічної точки завжди є зсунуте місце: коду ніколи не треба показувати чужим geom.
  ADD CONSTRAINT mushroom_picks_public_display_check
    CHECK (pick_type <> 'public' OR display_geom IS NOT NULL),
  -- Повтор запиту з офлайн-черги не створює дубль (індекс на user_id, client_id).
  ADD CONSTRAINT mushroom_picks_user_client_key UNIQUE (user_id, client_id);

-- ─── 5. Індекси ────────────────────────────────────────────────────────────
-- Добові ліміти: «скільки точок цієї видимості користувач створив за 24 год».
CREATE INDEX IF NOT EXISTS mushroom_picks_limits_idx
  ON public.mushroom_picks (user_id, pick_type, created_at DESC)
  WHERE deleted_at IS NULL;

-- Стрічка / карта публічних точок.
CREATE INDEX IF NOT EXISTS mushroom_picks_public_feed_idx
  ON public.mushroom_picks (created_at DESC)
  WHERE pick_type = 'public' AND deleted_at IS NULL;

-- Зовнішній ключ на довідник.
CREATE INDEX IF NOT EXISTS mushroom_picks_species_idx
  ON public.mushroom_picks (species_id)
  WHERE species_id IS NOT NULL;

-- ─── 6. RLS: читати можна тільки власні точки ──────────────────────────────
-- Раніше чужі public-точки читались напряму разом із точним geom. Тепер їх віддає
-- лише Edge Function (service_role) з явним фільтром і тільки display_geom.
DROP POLICY IF EXISTS mushroom_picks_read ON public.mushroom_picks;
CREATE POLICY mushroom_picks_read ON public.mushroom_picks
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- Запис — лише через Edge Functions (service_role): там перевіряються область, вид,
-- фото і ліміти. Політики на INSERT/UPDATE лишаються як другий рубіж.
REVOKE ALL ON public.mushroom_picks FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.mushroom_picks FROM authenticated;

-- ─── 7. Ліміти створення точок ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_create_pick(p_user_id UUID, p_visibility TEXT)
RETURNS TABLE (allowed BOOLEAN, code TEXT, message TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_rating INT;
  v_count INT;
  -- TODO(B3.7, B6.3): Pro-ліміти й рівні за ADR-010/013
  c_daily_limit CONSTANT INT := 5;       -- приватні (ADR-011) і публічні free-Лісовика (ADR-013 §13.5)
  c_lisovyk_min CONSTANT INT := 201;     -- поріг рівня «Лісовик» (ADR-013 §13.1)
BEGIN
  IF p_visibility IS NULL OR p_visibility NOT IN ('private', 'public') THEN
    RETURN QUERY SELECT false, 'validation_error'::TEXT, 'Видимість точки — private або public'::TEXT;
    RETURN;
  END IF;

  IF p_visibility = 'public' THEN
    SELECT u.rating INTO v_rating FROM public.users u WHERE u.id = p_user_id;
    IF COALESCE(v_rating, 0) < c_lisovyk_min THEN
      RETURN QUERY SELECT false, 'level_required'::TEXT,
        'Публічні точки — з рівня Лісовик. Поки що зробіть приватний тук-тук.'::TEXT;
      RETURN;
    END IF;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.mushroom_picks p
  WHERE p.user_id = p_user_id
    AND p.pick_type = p_visibility
    AND p.deleted_at IS NULL
    AND p.created_at > now() - INTERVAL '24 hours';

  IF v_count >= c_daily_limit THEN
    RETURN QUERY SELECT false, 'daily_limit_reached'::TEXT,
      CASE WHEN p_visibility = 'public'
        THEN 'Ліміт — 5 публічних точок на добу. Спробуйте пізніше або зробіть приватний тук-тук.'
        ELSE 'Ліміт — 5 приватних точок на добу. Спробуйте пізніше.'
      END::TEXT;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, NULL::TEXT, NULL::TEXT;
END;
$$;

COMMENT ON FUNCTION public.can_create_pick(UUID, TEXT) IS
  'Чи може користувач створити точку цієї видимості (ADR-010/011/013). Тільки service_role.';

REVOKE ALL ON FUNCTION public.can_create_pick(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_create_pick(UUID, TEXT) TO service_role;

-- ─── 8. Атомарне створення точки ───────────────────────────────────────────
-- Перевірка client_id, ліміту і вставка — під одним блокуванням на користувача,
-- тож паралельні запити не створять дубль і не перевищать ліміт.
-- Статус перевірки завжди 'pending' (ADR-018: підтверджують люди, не EXIF і не ШІ).
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

    RETURN jsonb_build_object('allowed', true, 'created', true, 'pick', jsonb_build_object(
      'id', v_pick.id, 'pick_type', v_pick.pick_type, 'verification_status', v_pick.verification_status
    ));
  END IF;

  RETURN jsonb_build_object('allowed', true, 'created', false, 'pick', jsonb_build_object(
    'id', v_pick.id, 'pick_type', v_pick.pick_type, 'verification_status', v_pick.verification_status
  ));
END;
$$;

COMMENT ON FUNCTION public.create_pick(
  UUID, UUID, UUID, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, TEXT, JSONB, BOOLEAN,
  TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION
) IS 'Атомарне створення тук-тука для POST v1-picks: ідемпотентність за client_id + ліміти. Тільки service_role.';

REVOKE ALL ON FUNCTION public.create_pick(
  UUID, UUID, UUID, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, TEXT, JSONB, BOOLEAN,
  TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_pick(
  UUID, UUID, UUID, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, TEXT, JSONB, BOOLEAN,
  TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION
) TO service_role;
