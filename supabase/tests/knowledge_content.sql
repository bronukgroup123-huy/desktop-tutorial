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
