-- ============================================================================
-- B3.10a: тести знань (міграція 20261127100000; ADR-023)
--   * модулі без питань — «скоро»; відкриваються по черзі; гість — лише тренування;
--   * спроба — без правильних відповідей; оцінка single / multi / order; поріг 80 %;
--   * бали — один раз (+ журнал рейтингу); повтор на бали після невдачі — через 24 год;
--   * критичне питання з помилкою — модуль не зараховано; здати двічі чи після строку — ні;
--   * 3 скарги — питання сховане; сертифікат — лише коли пройдено всі модулі; клієнту — без доступу;
--   * спроба бере питання порівну з кожної теми; якщо тема мала — решту добирають інші (20261128090000).
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email, is_anonymous) VALUES
  ('d1000000-0000-4000-8000-0000000091d1', 'q1@test.local', false),
  ('d2000000-0000-4000-8000-0000000091d2', 'q2@test.local', false),
  ('d3000000-0000-4000-8000-0000000091d3', 'q3@test.local', true),
  ('d4000000-0000-4000-8000-0000000091d4', 'q4@test.local', false);

SET LOCAL ROLE service_role;

-- тест механізму не залежить від справжнього змісту модулів (усе — в транзакції з ROLLBACK)
DELETE FROM public.quiz_questions;
UPDATE public.quiz_modules SET published = false, questions_per_attempt = 10;

-- тестовий зміст: 12 питань модуля app (single / multi / order) і 10 у forest (одне критичне)
DO $$
DECLARE i INT;
BEGIN
  FOR i IN 1..12 LOOP
    INSERT INTO public.quiz_questions (id, module_id, kind, prompt, options, correct, explanation, source)
    VALUES ('t_app_' || i, 'app',
      CASE WHEN i % 3 = 0 THEN 'multi' WHEN i % 4 = 0 THEN 'order' ELSE 'single' END,
      'Питання ' || i,
      '[{"id":"a","text":"А"},{"id":"b","text":"Б"},{"id":"c","text":"В"}]',
      CASE WHEN i % 3 = 0 THEN '["a","c"]' WHEN i % 4 = 0 THEN '["c","a","b"]' ELSE '["b"]' END::jsonb,
      'Пояснення ' || i, 'тест');
  END LOOP;
  FOR i IN 1..10 LOOP
    INSERT INTO public.quiz_questions (id, module_id, kind, prompt, options, correct, explanation, source, critical)
    VALUES ('t_forest_' || i, 'forest', 'single', 'Ліс ' || i,
      '[{"id":"a","text":"А"},{"id":"b","text":"Б"}]', '["a"]', 'Пояснення', 'тест', i = 1);
  END LOOP;
END $$;

-- правильні відповіді на спробу (як дав би людина, що все знає)
CREATE OR REPLACE FUNCTION pg_temp.right_answers(p_attempt UUID, p_wrong TEXT[] DEFAULT '{}') RETURNS JSONB
LANGUAGE sql AS $$
  SELECT jsonb_object_agg(q.id, CASE WHEN q.id = ANY (p_wrong) THEN '["zzz"]'::jsonb ELSE q.correct END)
  FROM public.quiz_attempts a JOIN public.quiz_questions q ON q.id = ANY (a.question_ids)
  WHERE a.id = p_attempt;
$$;

DO $$
DECLARE
  u1 CONSTANT UUID := 'd1000000-0000-4000-8000-0000000091d1';
  u2 CONSTANT UUID := 'd2000000-0000-4000-8000-0000000091d2';
  g  CONSTANT UUID := 'd3000000-0000-4000-8000-0000000091d3';
  ov JSONB;
  r JSONB;
  s JSONB;
  att UUID;
  ids TEXT[];
BEGIN
  -- до публікації — усе «скоро»
  ov := public.quiz_overview(u1);
  IF (ov->'modules'->0->>'status') <> 'soon' OR (ov->>'total')::int <> 7 THEN RAISE EXCEPTION 'Test 1 failed: %', ov; END IF;
  r := public.quiz_start(u1, false, 'app', false);
  IF r->>'code' <> 'module_soon' THEN RAISE EXCEPTION 'Test 1b failed: %', r; END IF;

  UPDATE public.quiz_modules SET published = true WHERE id IN ('app', 'forest');
  ov := public.quiz_overview(u1);
  IF ov->'modules'->0->>'status' <> 'open' OR ov->'modules'->1->>'status' <> 'locked' OR ov->'modules'->2->>'status' <> 'soon' THEN
    RAISE EXCEPTION 'Test 2 failed: %', ov->'modules';
  END IF;
  IF public.quiz_start(u1, false, 'forest', false)->>'code' <> 'module_locked' THEN RAISE EXCEPTION 'Test 2b failed'; END IF;

  -- гість: бали — ні, тренування — так
  IF public.quiz_start(g, true, 'app', false)->>'code' <> 'registration_required' THEN RAISE EXCEPTION 'Test 3 failed'; END IF;
  IF (public.quiz_start(g, true, 'app', true)->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Test 3b failed'; END IF;

  -- спроба на бали: 10 різних питань, без правильних відповідей
  r := public.quiz_start(u1, false, 'app', false);
  att := (r->>'attempt_id')::uuid;
  IF jsonb_array_length(r->'questions') <> 10 OR r::text LIKE '%"correct"%' OR r::text LIKE '%explanation%' THEN
    RAISE EXCEPTION 'Test 4 failed: %', r;
  END IF;
  SELECT question_ids INTO ids FROM public.quiz_attempts WHERE id = att;
  IF (SELECT count(DISTINCT x) FROM unnest(ids) x) <> 10 THEN RAISE EXCEPTION 'Test 4b failed: duplicates'; END IF;

  -- усе правильно → зараховано, +10 балів, у розборі — правильні відповіді й пояснення
  s := public.quiz_submit(u1, att, pg_temp.right_answers(att));
  IF (s->>'passed')::boolean IS NOT TRUE OR (s->>'percent')::int <> 100 OR (s->>'points_awarded')::int <> 10
     OR jsonb_array_length(s->'review') <> 10 OR s->'review'->0->>'explanation' IS NULL THEN
    RAISE EXCEPTION 'Test 5 failed: %', s - 'review';
  END IF;
  IF (SELECT rating FROM public.users WHERE id = u1) <> 10 THEN RAISE EXCEPTION 'Test 5b failed: rating'; END IF;
  IF public.quiz_submit(u1, att, pg_temp.right_answers(att))->>'code' <> 'already_submitted' THEN RAISE EXCEPTION 'Test 6 failed'; END IF;
  IF public.quiz_start(u1, false, 'app', false)->>'code' <> 'already_passed' THEN RAISE EXCEPTION 'Test 6b failed'; END IF;
  -- тренування після зарахування — так, але без балів
  r := public.quiz_start(u1, false, 'app', true);
  s := public.quiz_submit(u1, (r->>'attempt_id')::uuid, pg_temp.right_answers((r->>'attempt_id')::uuid));
  IF (s->>'points_awarded')::int <> 0 OR (SELECT rating FROM public.users WHERE id = u1) <> 10 THEN RAISE EXCEPTION 'Test 7 failed'; END IF;

  -- наступний модуль відкрився
  IF public.quiz_overview(u1)->'modules'->1->>'status' <> 'open' THEN RAISE EXCEPTION 'Test 8 failed'; END IF;

  -- forest: 9 з 10, але хибне критичне → не зараховано; повтор на бали — через добу
  r := public.quiz_start(u1, false, 'forest', false);
  att := (r->>'attempt_id')::uuid;
  s := public.quiz_submit(u1, att, pg_temp.right_answers(att, ARRAY['t_forest_1']));
  IF (s->>'passed')::boolean OR (s->>'percent')::int <> 90 OR (s->>'critical_failed')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'Test 9 failed: %', s - 'review';
  END IF;
  r := public.quiz_start(u1, false, 'forest', false);
  IF r->>'code' <> 'retry_later' OR r->>'next_scored_at' IS NULL THEN RAISE EXCEPTION 'Test 10 failed: %', r; END IF;
  IF (public.quiz_start(u1, false, 'forest', true)->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Test 10b failed'; END IF;

  -- u2: 7 з 10 (нижче 80 %) — не зараховано; часткова відповідь на multi — неправильна
  UPDATE public.quiz_modules SET questions_per_attempt = 12 WHERE id = 'app';
  r := public.quiz_start(u2, false, 'app', false);
  att := (r->>'attempt_id')::uuid;
  s := public.quiz_submit(u2, att, pg_temp.right_answers(att) || '{"t_app_3":["a"],"t_app_4":["a","b","c"],"t_app_1":["a"],"t_app_2":[]}'::jsonb);
  IF (s->>'correct')::int <> 8 OR (s->>'passed')::boolean THEN RAISE EXCEPTION 'Test 11 failed: %', s - 'review'; END IF;

  -- строк спроби минув
  UPDATE public.quiz_attempts SET submitted_at = NULL, expires_at = now() - INTERVAL '1 minute' WHERE id = att;
  IF public.quiz_submit(u2, att, '{}')->>'code' <> 'attempt_expired' THEN RAISE EXCEPTION 'Test 12 failed'; END IF;
  -- чужу спробу здати не можна
  IF public.quiz_submit(u1, att, '{}')->>'code' <> 'attempt_not_found' THEN RAISE EXCEPTION 'Test 12b failed'; END IF;
END $$;

-- скарги: три різні людини — питання сховане й не потрапляє в нові спроби
DO $$
DECLARE r JSONB;
BEGIN
  PERFORM public.quiz_report('d1000000-0000-4000-8000-0000000091d1', 't_app_1', 'Неточно');
  PERFORM public.quiz_report('d1000000-0000-4000-8000-0000000091d1', 't_app_1', 'Ще раз'); -- той самий — не рахується
  r := public.quiz_report('d2000000-0000-4000-8000-0000000091d2', 't_app_1', NULL);
  IF (r->>'hidden')::boolean THEN RAISE EXCEPTION 'Test 13 failed: hidden after 2'; END IF;
  r := public.quiz_report('d3000000-0000-4000-8000-0000000091d3', 't_app_1', NULL);
  IF (r->>'hidden')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Test 13b failed'; END IF;
  r := public.quiz_start('d4000000-0000-4000-8000-0000000091d4', false, 'app', true);
  IF r::text LIKE '%t_app_1"%' THEN RAISE EXCEPTION 'Test 13c failed: hidden question served'; END IF;
END $$;

-- сертифікат: лише коли пройдено всі сім модулів
DO $$
DECLARE
  u4 CONSTANT UUID := 'd4000000-0000-4000-8000-0000000091d4';
  r JSONB;
  s JSONB;
BEGIN
  UPDATE public.quiz_modules SET published = true;
  INSERT INTO public.quiz_questions (id, module_id, kind, prompt, options, correct, explanation, source)
  SELECT 't_' || m.id, m.id, 'single', 'Питання модуля ' || m.id, '[{"id":"a","text":"А"},{"id":"b","text":"Б"}]', '["a"]', 'Пояснення', 'тест'
  FROM public.quiz_modules m WHERE m.id NOT IN ('app', 'forest');
  -- шість модулів уже пройдено, сьомий — останній
  INSERT INTO public.quiz_results (user_id, module_id, best_percent, points_awarded)
  SELECT u4, id, 100, 0 FROM public.quiz_modules WHERE id <> 'twins';
  IF (SELECT knowledge_certified_at FROM public.users WHERE id = u4) IS NOT NULL THEN RAISE EXCEPTION 'Test 14 failed'; END IF;
  r := public.quiz_start(u4, false, 'twins', false);
  s := public.quiz_submit(u4, (r->>'attempt_id')::uuid, pg_temp.right_answers((r->>'attempt_id')::uuid));
  IF (s->>'certified_now')::boolean IS NOT TRUE
     OR (SELECT curriculum_version FROM public.users WHERE id = u4) <> 'adr-023-v1' THEN
    RAISE EXCEPTION 'Test 14b failed: %', s - 'review';
  END IF;
  IF public.quiz_overview(u4)->>'certified_at' IS NULL THEN RAISE EXCEPTION 'Test 14c failed'; END IF;
END $$;

-- Теми: спроба бере порівну з кожної теми, мала тема — скільки є, решту добирають інші
DO $$
DECLARE
  u4 UUID := 'd4000000-0000-4000-8000-0000000091d4';
  r JSONB; i INT; n_a INT; n_b INT; n_c INT;
BEGIN
  UPDATE public.quiz_questions SET published = false WHERE module_id = 'app';
  FOR i IN 1..12 LOOP
    INSERT INTO public.quiz_questions (id, module_id, topic, kind, prompt, options, correct, explanation, source)
    VALUES ('t_topic_' || i, 'app', CASE WHEN i <= 5 THEN 'ta' WHEN i <= 11 THEN 'tb' ELSE 'tc' END, 'single',
      'Тема ' || i, '[{"id":"a","text":"А"},{"id":"b","text":"Б"}]', '["a"]', 'Пояснення', 'тест');
  END LOOP;
  UPDATE public.quiz_modules SET questions_per_attempt = 7, published = true WHERE id = 'app';
  -- 7 питань на 3 теми, але в «tc» лише одне: tc = 1, а ta і tb добирають по 3
  FOR i IN 1..20 LOOP
    r := public.quiz_start(u4, false, 'app', true);
    IF r->>'ok' <> 'true' THEN RAISE EXCEPTION 'Test topics failed: %', r; END IF;
    SELECT count(*) FILTER (WHERE q.topic = 'ta'), count(*) FILTER (WHERE q.topic = 'tb'), count(*) FILTER (WHERE q.topic = 'tc')
      INTO n_a, n_b, n_c
    FROM jsonb_array_elements(r->'questions') x JOIN public.quiz_questions q ON q.id = x->>'id';
    IF jsonb_array_length(r->'questions') <> 7 OR n_c <> 1 OR n_a <> 3 OR n_b <> 3 THEN
      RAISE EXCEPTION 'Test topics failed: ta=% tb=% tc=% (очікувалось 3, 3, 1)', n_a, n_b, n_c;
    END IF;
  END LOOP;
  -- 9 на 3 теми, де в кожній вистачає: по 3
  UPDATE public.quiz_questions SET topic = 'tc' WHERE id IN ('t_topic_9', 't_topic_10', 't_topic_11');
  UPDATE public.quiz_modules SET questions_per_attempt = 9 WHERE id = 'app';
  FOR i IN 1..20 LOOP
    r := public.quiz_start(u4, false, 'app', true);
    SELECT count(*) FILTER (WHERE q.topic = 'ta'), count(*) FILTER (WHERE q.topic = 'tb'), count(*) FILTER (WHERE q.topic = 'tc')
      INTO n_a, n_b, n_c
    FROM jsonb_array_elements(r->'questions') x JOIN public.quiz_questions q ON q.id = x->>'id';
    IF n_a <> 3 OR n_b <> 3 OR n_c <> 3 THEN
      RAISE EXCEPTION 'Test topics failed: ta=% tb=% tc=% (очікувалось по 3)', n_a, n_b, n_c;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK теми: спроба порівну з кожної теми';
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.quiz_start('d1000000-0000-4000-8000-0000000091d1', false, 'app', true);
    RAISE EXCEPTION 'Test 15 failed: authenticated called quiz_start';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM public.quiz_questions;
    RAISE EXCEPTION 'Test 15b failed: authenticated read quiz_questions (answers!)';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;

ROLLBACK;
