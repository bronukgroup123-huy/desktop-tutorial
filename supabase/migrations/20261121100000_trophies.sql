-- ============================================================================
-- Трофеї-медальйони (ADR-021 §21.2.2, §21.10; рішення PO 2026-11-21)
--
--  * user_trophies — отримані трофеї (раз отримане не забирається, навіть якщо точку видалили);
--  * trophy_stats(user) — показники, з яких сервер рахує 24 трофеї (каталог і пороги —
--    `supabase/functions/_shared/v1/trophy-catalog.ts`): підтверджені знахідки, види за сезон,
--    окремі види, Червона книга, походи з Наглядачем, Наглядач для друзів, друзі;
--  * hikes.checklist_done / hikes.used_home_nav — позначки походу з телефону: перед стартом
--    пройдено чек-лист; повернулися за допомогою «Додому».
-- «Підтверджена знахідка» — тук-тук із фото, що пройшло перевірку місця й часу зйомки (EXIF,
-- ai_check.exif.verified, ADR-012 №3), не відхилений і не видалений.
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
  ADD COLUMN IF NOT EXISTS used_home_nav BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.trophy_stats(p_user UUID, p_now TIMESTAMPTZ DEFAULT now())
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH finds AS (
    SELECT p.species_id,
           p.pick_type,
           p.ai_check,
           (COALESCE(p.captured_at, p.created_at) AT TIME ZONE 'Europe/Kyiv') AS local_at
    FROM public.mushroom_picks p
    WHERE p.user_id = p_user
      AND p.deleted_at IS NULL
      AND p.verification_status <> 'rejected'
      AND COALESCE((p.ai_check -> 'exif' ->> 'verified')::boolean, false)
  ),
  season AS (
    SELECT * FROM finds
    WHERE species_id IS NOT NULL AND species_id <> 'unknown'
      AND extract(year FROM local_at) = extract(year FROM (p_now AT TIME ZONE 'Europe/Kyiv'))
  ),
  my_hikes AS (
    SELECT h.* FROM public.hikes h WHERE h.owner_id = p_user AND h.status = 'closed' AND h.closed_reason = 'home'
  )
  SELECT jsonb_build_object(
    'finds', (SELECT count(*) FROM finds),
    'species_season', (SELECT count(DISTINCT species_id) FROM season),
    'porcini', (SELECT count(*) FROM finds WHERE species_id = 'boletus_edulis'),
    'chanterelle', (SELECT count(*) FROM finds WHERE species_id LIKE 'cantharellus\_%'),
    'red_book_private', (
      SELECT count(*) FROM finds f JOIN public.mushroom_catalog c ON c.id = f.species_id
      WHERE c.red_listed AND f.pick_type = 'private'
    ),
    'ai_match', (SELECT count(*) FROM finds WHERE species_id IS NOT NULL AND ai_check -> 'top' -> 0 ->> 'species_id' = species_id),
    'morels_spring', (SELECT count(*) FROM finds WHERE species_id LIKE 'morchella\_%' AND extract(month FROM local_at) BETWEEN 3 AND 5),
    'winter_honey', (SELECT count(*) FROM finds WHERE species_id = 'flammulina_velutipes' AND extract(month FROM local_at) IN (12, 1, 2)),
    'hikes_safe', (SELECT count(*) FROM my_hikes),
    'hikes_on_time', (SELECT count(*) FROM my_hikes WHERE closed_at <= expected_return AND alert_sent_at IS NULL),
    'hikes_checklist', (SELECT count(*) FROM my_hikes WHERE checklist_done),
    'hikes_home_nav', (SELECT count(*) FROM my_hikes WHERE used_home_nav),
    'has_guardian', (SELECT count(*) FROM public.guardian_links l WHERE l.owner_id = p_user AND l.status = 'accepted'),
    'guarded_hikes', (
      SELECT count(*) FROM public.hike_guardians g JOIN public.hikes h ON h.id = g.hike_id
      WHERE g.guardian_id = p_user AND h.owner_id <> p_user AND h.status = 'closed'
    ),
    'friends', public.friend_count(p_user)
  );
$$;

REVOKE ALL ON FUNCTION public.trophy_stats(UUID, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trophy_stats(UUID, TIMESTAMPTZ) TO service_role;
