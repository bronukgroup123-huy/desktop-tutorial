-- ============================================================================
-- Трофеї-медальйони (ADR-021 §21.2.2, §21.10; рішення PO 2026-11-21)
--
--  * user_trophies — отримані трофеї (раз отримане не забирається);
--  * trophy_finds(user) — підтверджені фото знахідки користувача (сирі рядки): що саме з них
--    зараховувати (одне місце за день, вид підтвердило розпізнавання чи модератор, ліміт на
--    добу) — вирішує сервер у `_shared/v1/trophy-catalog.ts`;
--  * trophy_stats(user) — походи, Наглядач і друзі (рахуються лише справжні походи);
--  * hikes.walked_m / hikes.points_count — підсумок походу, який лишається після закриття
--    (сам трек видаляється, ADR-022 §22.2); hikes.checklist_done / hikes.used_home_nav —
--    позначки з телефону: перед стартом пройдено чек-лист; повернулися за допомогою «Додому».
-- «Підтверджена фото знахідка» — тук-тук із фото, що пройшло перевірку місця й часу зйомки
-- (EXIF ≤ 1 км і ≤ 24 год, ai_check.exif.verified, ADR-012 №3), не відхилений і не видалений.
-- Доступ — лише service_role (Edge Functions v1-me, v1-friends).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_trophies (
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  trophy_id TEXT NOT NULL CHECK (trophy_id ~ '^[a-z0-9_]{2,40}$'),
  earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, trophy_id)
);
ALTER TABLE public.user_trophies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_trophies FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_trophies FROM anon, authenticated;

ALTER TABLE public.hikes
  ADD COLUMN IF NOT EXISTS checklist_done BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS used_home_nav BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS walked_m INT,
  ADD COLUMN IF NOT EXISTS points_count INT;

-- Закритий похід: спершу підсумок (пройдено метрів за точками з доброю точністю GPS, скільки
-- точок), потім трек видаляється — Наглядач більше нічого не бачить (ADR-022 §22.2).
CREATE OR REPLACE FUNCTION public.hikes_on_close()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.status = 'closed' AND OLD.status <> 'closed' THEN
    SELECT COALESCE(round(sum(d)), 0)::int, count(*)::int + CASE WHEN count(*) > 0 THEN 1 ELSE 0 END
      INTO NEW.walked_m, NEW.points_count
    FROM (
      SELECT 2 * 6371000 * asin(sqrt(
               power(sin(radians(s.lat - s.plat) / 2), 2) +
               cos(radians(s.plat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - s.plng) / 2), 2))) AS d
      FROM (
        SELECT p.lat, p.lng,
               lag(p.lat) OVER (ORDER BY p.recorded_at) AS plat,
               lag(p.lng) OVER (ORDER BY p.recorded_at) AS plng
        FROM public.hike_points p
        WHERE p.hike_id = NEW.id AND NOT p.low_accuracy
      ) s
      WHERE s.plat IS NOT NULL
    ) x;
    DELETE FROM public.hike_points p WHERE p.hike_id = NEW.id;
    NEW.last_lat := NULL;
    NEW.last_lng := NULL;
    NEW.last_accuracy := NULL;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Підтверджені фото знахідки (сирі рядки, найстаріші перші): вид, приватна чи публічна,
-- координати (лише для «одне місце за день» на сервері — назовні не віддаються), місцевий час,
-- перша підказка розпізнавання з телефону, чи перевірив модератор, чи вид із Червоної книги.
CREATE OR REPLACE FUNCTION public.trophy_finds(p_user UUID)
RETURNS TABLE (
  species_id TEXT, pick_type TEXT, lat DOUBLE PRECISION, lng DOUBLE PRECISION, local_at TIMESTAMP,
  ai_species TEXT, ai_level TEXT, moderated BOOLEAN, red_listed BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p.species_id,
         p.pick_type,
         extensions.ST_Y(p.geom::extensions.geometry),
         extensions.ST_X(p.geom::extensions.geometry),
         COALESCE(p.captured_at, p.created_at) AT TIME ZONE 'Europe/Kyiv',
         p.ai_check -> 'top' -> 0 ->> 'species_id',
         p.ai_check -> 'top' -> 0 ->> 'level',
         p.verification_status = 'verified',
         COALESCE(c.red_listed, false)
  FROM public.mushroom_picks p
  LEFT JOIN public.mushroom_catalog c ON c.id = p.species_id
  WHERE p.user_id = p_user
    AND p.deleted_at IS NULL
    AND p.verification_status <> 'rejected'
    AND COALESCE((p.ai_check -> 'exif' ->> 'verified')::boolean, false)
  ORDER BY 5
  LIMIT 5000;
$$;

-- Походи, Наглядач, друзі. Справжній похід — з Наглядачем, завершений «Я вдома», не коротший
-- за 30 хв, пройдено ≥ 1 км (≥ 10 точок треку); у залік — один похід на день (за Києвом).
CREATE OR REPLACE FUNCTION public.trophy_stats(p_user UUID, p_now TIMESTAMPTZ DEFAULT now())
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH real_hikes AS (
    SELECT h.*, (h.started_at AT TIME ZONE 'Europe/Kyiv')::date AS day
    FROM public.hikes h
    WHERE h.status = 'closed' AND h.closed_reason = 'home'
      AND h.closed_at - h.started_at >= interval '30 minutes'
      AND COALESCE(h.walked_m, 0) >= 1000
      AND COALESCE(h.points_count, 0) >= 10
  ),
  mine AS (SELECT * FROM real_hikes WHERE owner_id = p_user)
  SELECT jsonb_build_object(
    'hikes_safe', (SELECT count(DISTINCT day) FROM mine),
    -- вчасно: повернувся не пізніше запланованого й не раніше ніж за 1,5 год до нього, без тривог
    'hikes_on_time', (
      SELECT count(DISTINCT day) FROM mine
      WHERE closed_at <= expected_return AND closed_at >= expected_return - interval '90 minutes'
        AND alert_sent_at IS NULL AND sos_at IS NULL
    ),
    'hikes_checklist', (SELECT count(DISTINCT day) FROM mine WHERE checklist_done),
    'hikes_home_nav', (SELECT count(DISTINCT day) FROM mine WHERE used_home_nav),
    'has_guardian', (SELECT count(*) FROM public.guardian_links l WHERE l.owner_id = p_user AND l.status = 'accepted'),
    -- Наглядач у справжніх походах друзів: одного друга — не частіше одного походу на день
    'guarded_hikes', (
      SELECT count(DISTINCT (h.owner_id, h.day)) FROM public.hike_guardians g JOIN real_hikes h ON h.id = g.hike_id
      WHERE g.guardian_id = p_user AND h.owner_id <> p_user
    ),
    'friends', public.friend_count(p_user)
  );
$$;

REVOKE ALL ON FUNCTION public.trophy_finds(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trophy_stats(UUID, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trophy_finds(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.trophy_stats(UUID, TIMESTAMPTZ) TO service_role;
