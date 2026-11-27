-- ============================================================================
-- Зміст тестів знань (ADR-023): опубліковані модулі цілісні
--   * опублікований модуль має щонайменше 20 питань (спроба — 10 випадкових);
--   * у кожного питання правильні відповіді — серед варіантів, single — рівно одна,
--     order — усі варіанти; є пояснення й джерело.
-- ============================================================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT m.id, count(q.*) AS n FROM public.quiz_modules m
    LEFT JOIN public.quiz_questions q ON q.module_id = m.id AND q.published
    WHERE m.published GROUP BY m.id
  LOOP
    IF r.n < 20 THEN RAISE EXCEPTION 'FAIL модуль % опубліковано з % питаннями (мінімум 20)', r.id, r.n; END IF;
  END LOOP;

  FOR r IN SELECT * FROM public.quiz_questions WHERE published LOOP
    IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(r.correct) c
               WHERE c NOT IN (SELECT o->>'id' FROM jsonb_array_elements(r.options) o)) THEN
      RAISE EXCEPTION 'FAIL %: правильна відповідь не серед варіантів', r.id;
    END IF;
    IF r.kind = 'single' AND jsonb_array_length(r.correct) <> 1 THEN
      RAISE EXCEPTION 'FAIL %: single має рівно одну правильну', r.id;
    END IF;
    IF r.kind = 'order' AND jsonb_array_length(r.correct) <> jsonb_array_length(r.options) THEN
      RAISE EXCEPTION 'FAIL %: order — усі варіанти в правильному порядку', r.id;
    END IF;
    IF btrim(r.explanation) = '' OR btrim(r.source) = '' THEN
      RAISE EXCEPTION 'FAIL %: немає пояснення чи джерела', r.id;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK зміст тестів знань цілісний';
END $$;

-- Модуль 1, версія 2: питання першої версії зняті з публікації, лишились тільки нові
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.quiz_questions WHERE id = 'app_honest_found' AND published) THEN
    RAISE EXCEPTION 'FAIL питання першої версії модуля 1 досі опубліковане';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quiz_questions WHERE id = 'app_press_confirm' AND published) THEN
    RAISE EXCEPTION 'FAIL нове питання модуля 1 не опубліковане';
  END IF;
  RAISE NOTICE 'OK модуль 1 оновлено до версії 2';
END $$;

-- Модуль 1: у спробі 15 питань, по 3 з кожної з 5 тем (тестовий гість — у транзакції з ROLLBACK)
BEGIN;
DO $$
DECLARE r JSONB; u UUID := 'c1000000-0000-4000-8000-00000000c0c1'; bad INT;
BEGIN
  INSERT INTO auth.users (id, email, is_anonymous) VALUES (u, 'content@test.local', true);
  r := public.quiz_start(u, true, 'app', true);
  IF r->>'ok' <> 'true' OR jsonb_array_length(r->'questions') <> 15 THEN
    RAISE EXCEPTION 'FAIL модуль 1: спроба має 15 питань: %', r;
  END IF;
  SELECT count(*) INTO bad FROM (
    SELECT q.topic, count(*) n FROM jsonb_array_elements(r->'questions') x
    JOIN public.quiz_questions q ON q.id = x->>'id' GROUP BY q.topic) t WHERE t.n <> 3;
  IF bad > 0 OR (SELECT count(DISTINCT topic) FROM public.quiz_questions WHERE module_id = 'app' AND published) <> 5 THEN
    RAISE EXCEPTION 'FAIL модуль 1: по 3 питання з кожної з 5 тем';
  END IF;
  RAISE NOTICE 'OK модуль 1: 15 питань, по 3 з кожної теми';
END $$;
ROLLBACK;

-- Модуль 2 «Ліс і гриб»: у спробі 15 питань, по 3 з кожної з 5 тем
BEGIN;
DO $$
DECLARE r JSONB; u UUID := 'c2000000-0000-4000-8000-00000000c0c2'; bad INT;
BEGIN
  INSERT INTO auth.users (id, email, is_anonymous) VALUES (u, 'content2@test.local', true);
  IF NOT (SELECT published FROM public.quiz_modules WHERE id = 'forest') THEN
    RAISE EXCEPTION 'FAIL модуль 2 не опубліковано';
  END IF;
  -- гість тренується; модуль 2 відкривається після модуля 1, тому позначаємо модуль 1 пройденим
  INSERT INTO public.quiz_results (user_id, module_id, best_percent, points_awarded)
  VALUES (u, 'app', 100, 0);
  r := public.quiz_start(u, true, 'forest', true);
  IF r->>'ok' <> 'true' OR jsonb_array_length(r->'questions') <> 15 THEN
    RAISE EXCEPTION 'FAIL модуль 2: спроба має 15 питань: %', r;
  END IF;
  SELECT count(*) INTO bad FROM (
    SELECT q.topic, count(*) n FROM jsonb_array_elements(r->'questions') x
    JOIN public.quiz_questions q ON q.id = x->>'id' GROUP BY q.topic) t WHERE t.n <> 3;
  IF bad > 0 OR (SELECT count(DISTINCT topic) FROM public.quiz_questions WHERE module_id = 'forest' AND published) <> 5 THEN
    RAISE EXCEPTION 'FAIL модуль 2: по 3 питання з кожної з 5 тем';
  END IF;
  RAISE NOTICE 'OK модуль 2: 15 питань, по 3 з кожної теми';
END $$;
ROLLBACK;
