-- ============================================================================
-- Регресія: лічильник ліміту запитів приймає всі v1-ендпоінти (інакше після SEC-003 кожен
-- запит застосунку отримує 503 rate_limit_unavailable).
-- ============================================================================
DO $$
DECLARE
  e text;
  n int;
  w timestamptz := date_trunc('minute', now());
BEGIN
  FOREACH e IN ARRAY ARRAY['forecast', 'picks', 'regions', 'catalog', 'v1-me', 'v1-analysis', 'v1-picks',
                           'v1-forecast', 'v1-forest-zones', 'v1-friends', 'v1-guardian', 'v1-regions',
                           'v1-app-config', 'v1-air-alerts']
  LOOP
    SELECT count INTO n FROM public.check_and_increment_ip_rate_limit('203.0.113.7', e, w, 60);
    IF n IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'FAIL перший запит до % — лічильник %, очікувалось 1', e, n;
    END IF;
    SELECT count INTO n FROM public.check_and_increment_ip_rate_limit('203.0.113.7', e, w, 60);
    IF n IS DISTINCT FROM 2 THEN
      RAISE EXCEPTION 'FAIL другий запит до % — лічильник %, очікувалось 2', e, n;
    END IF;
  END LOOP;
  -- довільний рядок у таблицю не потрапляє
  BEGIN
    PERFORM public.check_and_increment_ip_rate_limit('203.0.113.7', 'DROP TABLE x;', w, 60);
    RAISE EXCEPTION 'FAIL прийнято некоректну назву ендпоінта';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  DELETE FROM public.ip_rate_limit WHERE ip = '203.0.113.7';
  RAISE NOTICE 'OK ліміт запитів працює для старих і v1-ендпоінтів';
END;
$$;
