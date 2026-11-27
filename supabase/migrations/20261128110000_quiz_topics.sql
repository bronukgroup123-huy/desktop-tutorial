-- ============================================================================
-- Тести знань: теми питань і спроба «порівну з кожної теми» (ADR-023, рішення власника 27.11)
-- ============================================================================
-- * quiz_questions.topic — тема питання в межах модуля (напр. forecast, picks, safety);
-- * quiz_start бере питання порівну з усіх тем модуля (15 питань і 5 тем → по 3),
--   щоб кожна спроба торкалась усіх основних тем, а не лише випадкових;
-- * кількість питань у спробі задає вміст модуля (questions_per_attempt), а не цей файл.

ALTER TABLE public.quiz_questions
  ADD COLUMN IF NOT EXISTS topic TEXT CHECK (topic IS NULL OR topic ~ '^[a-z0-9_]{1,40}$');

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

  -- Порівну з кожної теми: у кожній теми питання нумеруються випадково (1, 2, 3…),
  -- спершу беруться всі «перші», потім «другі»… — так 15 питань на 5 тем дають по 3.
  -- Якщо в темі питань забракне, решту доберуть інші теми. Без тем — просто випадкові.
  -- Порядок показу — знову випадковий, щоб теми не йшли «по колу».
  SELECT array_agg(id ORDER BY random()) INTO v_ids FROM (
    SELECT t.id FROM (
      SELECT q.id,
             row_number() OVER (PARTITION BY coalesce(q.topic, '') ORDER BY random()) AS rn,
             random() AS tie
      FROM public.quiz_questions q
      WHERE q.module_id = p_module_id AND q.published AND NOT q.hidden_by_reports
    ) t
    ORDER BY t.rn, t.tie LIMIT v_m.questions_per_attempt
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

REVOKE ALL ON FUNCTION public.quiz_start(uuid, boolean, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.quiz_start(uuid, boolean, text, boolean) TO service_role;
