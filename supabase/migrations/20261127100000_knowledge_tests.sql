-- ============================================================================
-- B3.10a: тести знань (ADR-023; бали й сертифікат — ADR-012/013)
-- ============================================================================
-- Сім модулів від «Як працює Грибний Радар» до «Отруйних двійників», відкриваються по черзі.
-- Питання й правильні відповіді — лише в БД; клієнт отримує питання без відповідей, перевірка тут.
-- Спроба — 10 випадкових питань, поріг 80 % і жодного хибного критичного (модулі 6–7).
-- Бали за модуль — один раз; повтор на бали після невдачі — через 24 год; тренування — без обмежень,
-- гість — лише тренування. Сертифікат знань — коли пройдено всі сім модулів програми.
-- Зміст модулів додають окремі міграції (кожен модуль власник читає перед публікацією, ADR-023 §23.3).

CREATE TABLE IF NOT EXISTS public.quiz_modules (
  id                    TEXT PRIMARY KEY CHECK (id ~ '^[a-z0-9_]{1,40}$'),
  position              SMALLINT NOT NULL UNIQUE CHECK (position BETWEEN 1 AND 50),
  title                 TEXT NOT NULL,
  summary               TEXT NOT NULL,
  points                SMALLINT NOT NULL CHECK (points BETWEEN 1 AND 100),
  questions_per_attempt SMALLINT NOT NULL DEFAULT 10 CHECK (questions_per_attempt BETWEEN 1 AND 30),
  pass_percent          SMALLINT NOT NULL DEFAULT 80 CHECK (pass_percent BETWEEN 1 AND 100),
  published             BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.quiz_questions (
  id                TEXT PRIMARY KEY CHECK (id ~ '^[a-z0-9_]{1,60}$'),
  module_id         TEXT NOT NULL REFERENCES public.quiz_modules(id) ON DELETE CASCADE,
  -- single — одна правильна; multi — оберіть усі правильні; order — розставте по порядку
  kind              TEXT NOT NULL CHECK (kind IN ('single', 'multi', 'order')),
  prompt            TEXT NOT NULL CHECK (char_length(prompt) BETWEEN 5 AND 800),
  options           JSONB NOT NULL CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 8),
  correct           JSONB NOT NULL CHECK (jsonb_typeof(correct) = 'array' AND jsonb_array_length(correct) >= 1),
  explanation       TEXT NOT NULL CHECK (char_length(explanation) >= 5),
  source            TEXT NOT NULL CHECK (char_length(source) >= 3),
  critical          BOOLEAN NOT NULL DEFAULT false,
  published         BOOLEAN NOT NULL DEFAULT true,
  hidden_by_reports BOOLEAN NOT NULL DEFAULT false,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS quiz_questions_module_idx ON public.quiz_questions (module_id) WHERE published AND NOT hidden_by_reports;

CREATE TABLE IF NOT EXISTS public.quiz_attempts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  module_id    TEXT NOT NULL REFERENCES public.quiz_modules(id) ON DELETE CASCADE,
  practice     BOOLEAN NOT NULL,
  question_ids TEXT[] NOT NULL,
  started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ NOT NULL,
  submitted_at TIMESTAMPTZ,
  correct      SMALLINT,
  total        SMALLINT,
  passed       BOOLEAN
);
CREATE INDEX IF NOT EXISTS quiz_attempts_user_idx ON public.quiz_attempts (user_id, module_id, submitted_at DESC);

CREATE TABLE IF NOT EXISTS public.quiz_results (
  user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  module_id      TEXT NOT NULL REFERENCES public.quiz_modules(id) ON DELETE CASCADE,
  passed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  best_percent   SMALLINT NOT NULL,
  points_awarded SMALLINT NOT NULL,
  PRIMARY KEY (user_id, module_id)
);

CREATE TABLE IF NOT EXISTS public.quiz_reports (
  question_id TEXT NOT NULL REFERENCES public.quiz_questions(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  comment     TEXT CHECK (comment IS NULL OR char_length(comment) <= 500),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (question_id, user_id)
);

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['quiz_modules', 'quiz_questions', 'quiz_attempts', 'quiz_results', 'quiz_reports'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
  END LOOP;
END $$;

-- бали за модуль — у журналі рейтингу, один раз на модуль
ALTER TABLE public.rating_events DROP CONSTRAINT IF EXISTS rating_events_reason_check;
ALTER TABLE public.rating_events ADD CONSTRAINT rating_events_reason_check
  CHECK (reason IN ('pick_exif', 'trip_feedback', 'pick_confirm', 'pick_confirmed', 'quiz_module'));
ALTER TABLE public.rating_events ADD COLUMN IF NOT EXISTS quiz_module_id TEXT
  REFERENCES public.quiz_modules(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS rating_events_quiz_uniq ON public.rating_events (user_id, quiz_module_id)
  WHERE quiz_module_id IS NOT NULL;

-- Програма (ADR-023 §23.1). Модулі публікуються разом зі змістом — окремими міграціями.
INSERT INTO public.quiz_modules (id, position, title, summary, points) VALUES
  ('app',      1, 'Як працює Грибний Радар', 'Звідки прогноз і чому чесні відповіді роблять його точнішим саме для вас', 10),
  ('forest',   2, 'Ліс і гриб', 'Грибниця, союз грибів із деревами, чому вид росте не будь-де', 10),
  ('weather',  3, 'Погода, сезони, хвилі', 'Як дощ і тепло із запізненням дають хвилю — і коли її не буде', 15),
  ('ethics',   4, 'Етика й закон', 'Червона книга, заповідники, як не шкодити грибниці', 15),
  ('safety',   5, 'Безпека в лісі', 'Рішення в ситуаціях: заблукав, сідає телефон, темніє', 20),
  ('myths',    6, 'Міфи, які вбивають', 'Народні «перевірки» й поради, через які труяться', 25),
  ('twins',    7, 'Отруйні двійники', 'Як розрізняти, коли однієї ознаки замало', 25)
ON CONFLICT (id) DO NOTHING;

-- ─── Стан модулів для людини ───────────────────────────────────────────────
-- status: soon (ще не опубліковано) | locked (спершу попередній) | open | passed
CREATE OR REPLACE FUNCTION public.quiz_overview(p_user_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH m AS (
    SELECT q.*, r.passed_at, r.best_percent, r.points_awarded,
      (SELECT a.submitted_at + INTERVAL '24 hours' FROM public.quiz_attempts a
       WHERE a.user_id = p_user_id AND a.module_id = q.id AND NOT a.practice AND a.passed = false
         AND a.submitted_at > now() - INTERVAL '24 hours'
       ORDER BY a.submitted_at DESC LIMIT 1) AS next_scored_at,
      lag(r.passed_at IS NOT NULL, 1, true) OVER (ORDER BY q.position) AS prev_passed,
      (SELECT count(*) FROM public.quiz_questions qq WHERE qq.module_id = q.id AND qq.published AND NOT qq.hidden_by_reports) AS questions
    FROM public.quiz_modules q
    LEFT JOIN public.quiz_results r ON r.module_id = q.id AND r.user_id = p_user_id
  )
  SELECT jsonb_build_object(
    'modules', coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'position', m.position, 'title', m.title, 'summary', m.summary, 'points', m.points,
      'status', CASE
        WHEN m.passed_at IS NOT NULL THEN 'passed'
        WHEN NOT m.published OR m.questions = 0 THEN 'soon'
        WHEN NOT m.prev_passed THEN 'locked'
        ELSE 'open' END,
      'best_percent', m.best_percent, 'passed_at', m.passed_at,
      'next_scored_at', m.next_scored_at,
      'questions_per_attempt', m.questions_per_attempt, 'pass_percent', m.pass_percent
    ) ORDER BY m.position), '[]'::jsonb),
    'passed_count', (SELECT count(*) FROM m WHERE m.passed_at IS NOT NULL),
    'total', (SELECT count(*) FROM m),
    'certified_at', (SELECT u.knowledge_certified_at FROM public.users u WHERE u.id = p_user_id)
  )
  FROM m;
$$;

-- ─── Почати спробу ─────────────────────────────────────────────────────────
-- → { ok, code?, message?, attempt_id, practice, expires_at, questions: [{ id, kind, prompt, options }] }
CREATE OR REPLACE FUNCTION public.quiz_start(p_user_id UUID, p_is_guest BOOLEAN, p_module_id TEXT, p_practice BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ov JSONB := public.quiz_overview(p_user_id);
  v_mod JSONB;
  v_m public.quiz_modules;
  v_ids TEXT[];
  v_id UUID;
  v_exp TIMESTAMPTZ := now() + INTERVAL '2 hours';
BEGIN
  SELECT x INTO v_mod FROM jsonb_array_elements(v_ov->'modules') x WHERE x->>'id' = p_module_id;
  SELECT * INTO v_m FROM public.quiz_modules WHERE id = p_module_id;
  IF v_mod IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'module_not_found', 'message', 'Такого модуля немає');
  END IF;
  IF v_mod->>'status' = 'soon' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'module_soon', 'message', 'Цей модуль ще готується');
  END IF;
  IF v_mod->>'status' = 'locked' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'module_locked', 'message', 'Спершу пройдіть попередній модуль');
  END IF;
  IF NOT p_practice THEN
    IF p_is_guest THEN
      RETURN jsonb_build_object('ok', false, 'code', 'registration_required', 'message',
        'Бали за тести — після входу через Google або Apple. Тренуватися можна й так');
    END IF;
    IF v_mod->>'status' = 'passed' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_passed', 'message',
        'Модуль уже зараховано. Можна тренуватися без балів');
    END IF;
    IF v_mod->>'next_scored_at' IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'retry_later', 'message',
        'Наступна спроба на бали — через добу після попередньої. Поки можна тренуватися',
        'next_scored_at', v_mod->'next_scored_at');
    END IF;
  END IF;

  SELECT array_agg(id) INTO v_ids FROM (
    SELECT q.id FROM public.quiz_questions q
    WHERE q.module_id = p_module_id AND q.published AND NOT q.hidden_by_reports
    ORDER BY random() LIMIT v_m.questions_per_attempt
  ) s;

  INSERT INTO public.quiz_attempts (user_id, module_id, practice, question_ids, expires_at)
  VALUES (p_user_id, p_module_id, p_practice, v_ids, v_exp) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'attempt_id', v_id, 'practice', p_practice, 'expires_at', v_exp,
    'questions', (
      SELECT jsonb_agg(jsonb_build_object(
          'id', q.id, 'kind', q.kind, 'prompt', q.prompt,
          -- варіанти в довільному порядку; правильних відповідей тут немає
          'options', (SELECT jsonb_agg(o ORDER BY random()) FROM jsonb_array_elements(q.options) o))
        ORDER BY array_position(v_ids, q.id))
      FROM public.quiz_questions q WHERE q.id = ANY (v_ids)));
END;
$$;

-- ─── Здати спробу ──────────────────────────────────────────────────────────
-- p_answers: { "<question_id>": ["<option_id>", …] } (для order — у вибраному порядку)
CREATE OR REPLACE FUNCTION public.quiz_submit(p_user_id UUID, p_attempt_id UUID, p_answers JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_a public.quiz_attempts;
  v_m public.quiz_modules;
  v_review JSONB := '[]'::jsonb;
  v_ok INT := 0;
  v_total INT := 0;
  v_critical_failed BOOLEAN := false;
  v_passed BOOLEAN;
  v_percent INT;
  v_points INT := 0;
  v_certified BOOLEAN := false;
  q RECORD;
  v_chosen JSONB;
  v_right BOOLEAN;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('quiz:' || p_user_id::TEXT, 0));
  SELECT * INTO v_a FROM public.quiz_attempts WHERE id = p_attempt_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'attempt_not_found', 'message', 'Спробу не знайдено');
  END IF;
  IF v_a.submitted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'already_submitted', 'message', 'Цю спробу вже здано');
  END IF;
  IF v_a.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'code', 'attempt_expired', 'message', 'Час спроби минув — почніть нову');
  END IF;
  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'validation_error', 'message', 'Відповіді — об''єкт { питання: [варіанти] }');
  END IF;
  SELECT * INTO v_m FROM public.quiz_modules WHERE id = v_a.module_id;

  FOR q IN SELECT * FROM public.quiz_questions WHERE id = ANY (v_a.question_ids)
           ORDER BY array_position(v_a.question_ids, id) LOOP
    v_total := v_total + 1;
    v_chosen := CASE WHEN jsonb_typeof(p_answers->q.id) = 'array' THEN p_answers->q.id ELSE '[]'::jsonb END;
    v_right := CASE q.kind
      WHEN 'order' THEN v_chosen = q.correct
      ELSE (SELECT coalesce(array_agg(DISTINCT x ORDER BY x), '{}') FROM jsonb_array_elements_text(v_chosen) x)
         = (SELECT array_agg(DISTINCT x ORDER BY x) FROM jsonb_array_elements_text(q.correct) x)
      END;
    IF v_right THEN v_ok := v_ok + 1; ELSIF q.critical THEN v_critical_failed := true; END IF;
    v_review := v_review || jsonb_build_array(jsonb_build_object(
      'id', q.id, 'kind', q.kind, 'prompt', q.prompt, 'options', q.options, 'chosen', v_chosen,
      'correct', q.correct, 'is_correct', v_right, 'critical', q.critical,
      'explanation', q.explanation, 'source', q.source));
  END LOOP;

  v_percent := CASE WHEN v_total = 0 THEN 0 ELSE (v_ok * 100) / v_total END;
  v_passed := v_total > 0 AND v_percent >= v_m.pass_percent AND NOT v_critical_failed;
  UPDATE public.quiz_attempts SET submitted_at = now(), correct = v_ok, total = v_total, passed = v_passed
  WHERE id = v_a.id;

  IF NOT v_a.practice AND v_passed THEN
    INSERT INTO public.quiz_results (user_id, module_id, best_percent, points_awarded)
    VALUES (p_user_id, v_a.module_id, v_percent, v_m.points)
    ON CONFLICT (user_id, module_id) DO NOTHING;
    IF FOUND THEN
      INSERT INTO public.rating_events (user_id, delta, reason, quiz_module_id)
      VALUES (p_user_id, v_m.points, 'quiz_module', v_a.module_id) ON CONFLICT DO NOTHING;
      v_points := v_m.points;
    END IF;
    -- сертифікат: пройдено всі модулі програми (ADR-013, ADR-023 §23.4)
    IF (SELECT count(*) FROM public.quiz_results r WHERE r.user_id = p_user_id)
       = (SELECT count(*) FROM public.quiz_modules) THEN
      UPDATE public.users SET knowledge_certified_at = now(), curriculum_version = 'adr-023-v1'
      WHERE id = p_user_id AND knowledge_certified_at IS NULL;
      v_certified := FOUND;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'module_id', v_a.module_id, 'practice', v_a.practice,
    'correct', v_ok, 'total', v_total, 'percent', v_percent, 'pass_percent', v_m.pass_percent,
    'critical_failed', v_critical_failed, 'passed', v_passed, 'points_awarded', v_points,
    'certified_now', v_certified, 'review', v_review);
END;
$$;

-- ─── «Помилка в питанні» ───────────────────────────────────────────────────
-- 3 скарги від різних людей — питання ховається до перевірки (ADR-023 §23.3).
CREATE OR REPLACE FUNCTION public.quiz_report(p_user_id UUID, p_question_id TEXT, p_comment TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_n INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.quiz_questions WHERE id = p_question_id) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'question_not_found', 'message', 'Питання не знайдено');
  END IF;
  INSERT INTO public.quiz_reports (question_id, user_id, comment)
  VALUES (p_question_id, p_user_id, nullif(btrim(p_comment), '')) ON CONFLICT DO NOTHING;
  SELECT count(*) INTO v_n FROM public.quiz_reports WHERE question_id = p_question_id;
  IF v_n >= 3 THEN
    UPDATE public.quiz_questions SET hidden_by_reports = true, updated_at = now()
    WHERE id = p_question_id AND NOT hidden_by_reports;
  END IF;
  RETURN jsonb_build_object('ok', true, 'hidden', v_n >= 3);
END;
$$;

DO $$
DECLARE f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY['quiz_overview(uuid)', 'quiz_start(uuid, boolean, text, boolean)',
                           'quiz_submit(uuid, uuid, jsonb)', 'quiz_report(uuid, text, text)'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role', f);
  END LOOP;
END $$;
