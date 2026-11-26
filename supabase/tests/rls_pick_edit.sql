-- ============================================================================
-- B3.4: зміна й видалення своєї точки (міграція 20261126120000). Транзакція з ROLLBACK.
-- ============================================================================
BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('bbbb0001-0000-4000-8000-00000000e001', 'owner@test.local'),
  ('bbbb0002-0000-4000-8000-00000000e002', 'stranger@test.local');
UPDATE public.users SET home_region_id = (SELECT min(id) FROM public.regions) WHERE id::text LIKE 'bbbb000%';
-- власник — Лісовик (публічні: 7 за тиждень)
INSERT INTO public.rating_events (user_id, delta, reason)
SELECT 'bbbb0001-0000-4000-8000-00000000e001', 1, 'pick_exif' FROM generate_series(1, 201);

SET LOCAL ROLE service_role;
DO $$
DECLARE
  owner CONSTANT uuid := 'bbbb0001-0000-4000-8000-00000000e001';
  stranger CONSTANT uuid := 'bbbb0002-0000-4000-8000-00000000e002';
  p_known uuid := gen_random_uuid();
  p_unknown uuid := gen_random_uuid();
  res jsonb;
  i int;
BEGIN
  PERFORM public.create_pick(p_known, owner, gen_random_uuid(), 50.4, 30.5, 'picks/k.jpg', 'private', 'boletus_edulis', 'старий опис');
  PERFORM public.create_pick(p_unknown, owner, gen_random_uuid(), 50.4, 30.5, 'picks/u.jpg', 'private', NULL);

  -- чужий не змінює й не видаляє
  res := public.update_pick(stranger, p_known, 'public', true, 'чужий', 50.41, 30.51);
  IF res->>'code' <> 'pick_not_found' THEN RAISE EXCEPTION 'FAIL чужий змінив точку: %', res; END IF;
  IF public.delete_pick(stranger, p_known) THEN RAISE EXCEPTION 'FAIL чужий видалив точку'; END IF;
  IF (SELECT description FROM public.mushroom_picks WHERE id = p_known) <> 'старий опис' THEN
    RAISE EXCEPTION 'FAIL чужий змінив опис';
  END IF;

  -- «Не знаю» не стає публічною
  res := public.update_pick(owner, p_unknown, 'public', false, NULL, 50.41, 30.51);
  IF res->>'code' <> 'species_required' THEN RAISE EXCEPTION 'FAIL «Не знаю» стала публічною: %', res; END IF;

  -- опис і публікація: зсунуте місце, дата публікації
  res := public.update_pick(owner, p_known, 'public', true, 'новий опис', 50.41, 30.51);
  IF (res->>'ok')::boolean IS NOT TRUE OR res->'pick'->>'pick_type' <> 'public' THEN RAISE EXCEPTION 'FAIL публікація: %', res; END IF;
  IF (SELECT published_at IS NULL OR display_geom IS NULL OR description <> 'новий опис' FROM public.mushroom_picks WHERE id = p_known) THEN
    RAISE EXCEPTION 'FAIL після публікації немає дати, зсунутого місця чи опису';
  END IF;

  -- назад у приватні: зсунуте місце прибрано, дата публікації лишається (рахується в ліміт)
  res := public.update_pick(owner, p_known, 'private');
  IF res->'pick'->>'pick_type' <> 'private' THEN RAISE EXCEPTION 'FAIL сховати: %', res; END IF;
  IF (SELECT display_geom IS NOT NULL OR published_at IS NULL FROM public.mushroom_picks WHERE id = p_known) THEN
    RAISE EXCEPTION 'FAIL після приховування лишилось зсунуте місце або зникла дата публікації';
  END IF;

  -- «опублікував → сховав → опублікував» не обходить тижневий ліміт (Лісовик: 7)
  FOR i IN 1..6 LOOP
    PERFORM public.create_pick(gen_random_uuid(), owner, gen_random_uuid(), 50.4, 30.5, 'picks/p.jpg', 'public', 'boletus_edulis',
      NULL, NULL, false, NULL, 50.41, 30.51);
  END LOOP;
  res := public.update_pick(owner, p_known, 'public', false, NULL, 50.41, 30.51);
  IF res->>'code' <> 'weekly_limit_reached' THEN RAISE EXCEPTION 'FAIL перемикання обійшло тижневий ліміт: %', res; END IF;

  -- soft delete: точка лишається в таблиці, але її не змінити й не видалити вдруге
  IF NOT public.delete_pick(owner, p_unknown) THEN RAISE EXCEPTION 'FAIL власник не видалив'; END IF;
  IF (SELECT deleted_at IS NULL FROM public.mushroom_picks WHERE id = p_unknown) THEN RAISE EXCEPTION 'FAIL не soft delete'; END IF;
  IF public.delete_pick(owner, p_unknown) THEN RAISE EXCEPTION 'FAIL видалено двічі'; END IF;
  res := public.update_pick(owner, p_unknown, NULL, true, 'після видалення');
  IF res->>'code' <> 'pick_not_found' THEN RAISE EXCEPTION 'FAIL змінено видалену точку'; END IF;

  RAISE NOTICE 'OK зміна й видалення своєї точки: лише автор, правила видимості, ліміт за датою публікації';
END $$;
RESET ROLE;

-- клієнт напряму функції не викликає
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.delete_pick('bbbb0001-0000-4000-8000-00000000e001', gen_random_uuid());
    RAISE EXCEPTION 'FAIL authenticated викликав delete_pick';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK update_pick / delete_pick — лише сервер';
END $$;
RESET ROLE;

ROLLBACK;
