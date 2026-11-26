-- ============================================================================
-- B6.1: export_user_data (міграція 20261126130000) — GDPR-експорт своїх даних
--   * свої точки (і видалені), друзі, Наглядачі, походи з треком, ділянки — є;
--   * чужі точки — немає; блокування ІНШИМ користувачем — не видно;
--   * токени push і коди Telegram — не віддаються;
--   * неіснуючий користувач → NULL; викликає лише service_role.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('e1000000-0000-4000-8000-0000000061e1', 'exp1@test.local'),
  ('e2000000-0000-4000-8000-0000000061e2', 'exp2@test.local'),
  ('e3000000-0000-4000-8000-0000000061e3', 'exp3@test.local');

UPDATE public.users SET handle = 'Мама_ліс', handle_key = 'мама_ліс', name = 'Мама' WHERE id = 'e2000000-0000-4000-8000-0000000061e2';
UPDATE public.users SET handle = 'Сусід', handle_key = 'сусід', name = 'Сусід' WHERE id = 'e3000000-0000-4000-8000-0000000061e3';

INSERT INTO public.mushroom_picks (id, user_id, geom, mushroom_type, species_id, pick_type, verification_status, deleted_at, description)
VALUES
  ('e1000000-0000-4000-8000-0000000061a1', 'e1000000-0000-4000-8000-0000000061e1', 'SRID=4326;POINT(28.6 50.4)',
   'boletus_edulis', 'boletus_edulis', 'private', 'pending', NULL, 'Під дубом'),
  ('e1000000-0000-4000-8000-0000000061a2', 'e1000000-0000-4000-8000-0000000061e1', 'SRID=4326;POINT(28.7 50.5)',
   'unknown', NULL, 'private', 'pending', now(), NULL),
  ('e1000000-0000-4000-8000-0000000061a3', 'e2000000-0000-4000-8000-0000000061e2', 'SRID=4326;POINT(28.8 50.6)',
   'unknown', NULL, 'private', 'pending', NULL, 'Чужа');

-- друг (прийнято), і ще один, який заблокував користувача — цей рядок не віддається
INSERT INTO public.friendships (user_a, user_b, status, requested_by, blocked_by) VALUES
  ('e1000000-0000-4000-8000-0000000061e1', 'e2000000-0000-4000-8000-0000000061e2', 'accepted',
   'e1000000-0000-4000-8000-0000000061e1', NULL),
  ('e1000000-0000-4000-8000-0000000061e1', 'e3000000-0000-4000-8000-0000000061e3', 'blocked',
   'e1000000-0000-4000-8000-0000000061e1', 'e3000000-0000-4000-8000-0000000061e3');

INSERT INTO public.guardian_links (owner_id, guardian_id, status)
VALUES ('e1000000-0000-4000-8000-0000000061e1', 'e2000000-0000-4000-8000-0000000061e2', 'accepted');
INSERT INTO public.hikes (id, owner_id, route, started_at, expected_return)
VALUES ('e1000000-0000-4000-8000-0000000061b1', 'e1000000-0000-4000-8000-0000000061e1',
        '[{"lat":50.4,"lng":28.6,"label":"Старт"}]', '2026-11-20 08:00+00', '2026-11-20 14:00+00');
INSERT INTO public.hike_guardians (hike_id, guardian_id)
VALUES ('e1000000-0000-4000-8000-0000000061b1', 'e2000000-0000-4000-8000-0000000061e2');
INSERT INTO public.hike_points (hike_id, lat, lng, accuracy, recorded_at) VALUES
  ('e1000000-0000-4000-8000-0000000061b1', 50.41, 28.61, 8, '2026-11-20 09:00+00'),
  ('e1000000-0000-4000-8000-0000000061b1', 50.42, 28.62, 9, '2026-11-20 10:00+00');

INSERT INTO public.push_devices (token, user_id, platform)
VALUES ('secret-push-token-61', 'e1000000-0000-4000-8000-0000000061e1', 'android');
INSERT INTO public.user_push_tokens (user_id, fcm_token, platform)
VALUES ('e1000000-0000-4000-8000-0000000061e1', 'secret-fcm-token-61', 'android');

SET LOCAL ROLE service_role;

DO $$
DECLARE
  u1 CONSTANT UUID := 'e1000000-0000-4000-8000-0000000061e1';
  j JSONB;
  pick JSONB;
BEGIN
  j := public.export_user_data(u1);

  IF j->>'format_version' <> '1' OR j->'profile'->>'id' <> u1::TEXT THEN
    RAISE EXCEPTION 'Test 1 failed: header/profile %', j->'profile';
  END IF;

  -- свої точки — обидві (і видалена), чужої немає
  IF jsonb_array_length(j->'picks') <> 2 THEN
    RAISE EXCEPTION 'Test 2 failed: picks %', j->'picks';
  END IF;
  IF j->'picks' @> '[{"description":"Чужа"}]' THEN
    RAISE EXCEPTION 'Test 2b failed: foreign pick exported';
  END IF;
  SELECT p INTO pick FROM jsonb_array_elements(j->'picks') p WHERE p->>'description' = 'Під дубом';
  IF abs((pick->>'lat')::float - 50.4) > 1e-9 OR abs((pick->>'lng')::float - 28.6) > 1e-9 THEN
    RAISE EXCEPTION 'Test 3 failed: coordinates %', pick;
  END IF;
  IF NOT j->'picks' @> '[{"species_id":null}]' OR (SELECT count(*) FROM jsonb_array_elements(j->'picks') p
      WHERE p->>'deleted_at' IS NOT NULL) <> 1 THEN
    RAISE EXCEPTION 'Test 3b failed: deleted pick missing';
  END IF;

  -- друзі: лише прийнятий, заблокованого іншим немає
  IF jsonb_array_length(j->'friends') <> 1 OR j->'friends'->0->>'handle' <> 'Мама_ліс'
     OR (j->'friends'->0->>'requested_by_me')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'Test 4 failed: friends %', j->'friends';
  END IF;

  IF NOT j->'guardian_links' @> '[{"role":"my_guardian","handle":"Мама_ліс"}]' THEN
    RAISE EXCEPTION 'Test 5 failed: guardian links %', j->'guardian_links';
  END IF;

  IF jsonb_array_length(j->'hikes') <> 1 OR jsonb_array_length(j->'hikes'->0->'track') <> 2
     OR j->'hikes'->0->'guardians' <> '["Мама_ліс"]'::jsonb THEN
    RAISE EXCEPTION 'Test 6 failed: hikes %', j->'hikes';
  END IF;

  -- ключі доставки не віддаються, лише платформа
  IF j::TEXT LIKE '%secret-push-token-61%' OR j::TEXT LIKE '%secret-fcm-token-61%' THEN
    RAISE EXCEPTION 'Test 7 failed: push token exported';
  END IF;
  IF jsonb_array_length(j->'devices') <> 2 THEN
    RAISE EXCEPTION 'Test 7b failed: devices %', j->'devices';
  END IF;

  -- порожні розділи — порожні масиви, не NULL
  IF j->'trophies' <> '[]'::jsonb OR j->'analysis_areas' <> '[]'::jsonb OR j->'reports_sent' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'Test 8 failed: empty sections %', j;
  END IF;

  IF public.export_user_data('00000000-0000-4000-8000-000000000000') IS NOT NULL THEN
    RAISE EXCEPTION 'Test 9 failed: unknown user returned data';
  END IF;
END $$;

-- доповнення (міграція 20261126170000): відгуки «Знайшли?» і підтвердження точок знахідкою
DO $$
DECLARE
  u1 CONSTANT UUID := 'e1000000-0000-4000-8000-0000000061e1';
  u2 CONSTANT UUID := 'e2000000-0000-4000-8000-0000000061e2';
  j JSONB;
BEGIN
  INSERT INTO public.trip_feedback (user_id, trip_day, source, answer, predicted_level, points)
  VALUES (u1, current_date, 'hike', 'found', NULL, 'none');
  -- u1 підтвердив чужу точку u2 своєю (видаленою — не важливо) точкою; u2 — автор
  INSERT INTO public.pick_confirmations (pick_id, confirmer_id, author_id, reply_pick_id, counted, reason)
  VALUES ('e1000000-0000-4000-8000-0000000061a3', u1, u2, 'e1000000-0000-4000-8000-0000000061a1', true, NULL);

  j := public.export_user_data(u1);
  IF jsonb_array_length(j->'trip_feedback') <> 1 OR j->'trip_feedback'->0->>'answer' <> 'found'
     OR (j->'feedback_trust')::numeric <> 1 THEN
    RAISE EXCEPTION 'Test 11 failed: trip_feedback %', j->'trip_feedback';
  END IF;
  IF jsonb_array_length(j->'pick_confirmations') <> 1 OR (j->'pick_confirmations'->0->>'counted')::boolean IS NOT TRUE
     OR j->'pick_confirmations'->0 ? 'pick_id' THEN
    RAISE EXCEPTION 'Test 12 failed: pick_confirmations %', j->'pick_confirmations';
  END IF;
  IF j->'my_picks_confirmed' <> '[]'::jsonb THEN RAISE EXCEPTION 'Test 13 failed: %', j->'my_picks_confirmed'; END IF;

  -- автор бачить лише факт і дату підтвердження своєї точки — без того, хто підтвердив
  j := public.export_user_data(u2);
  IF jsonb_array_length(j->'my_picks_confirmed') <> 1 OR j::TEXT LIKE '%' || u1::TEXT || '%' THEN
    RAISE EXCEPTION 'Test 14 failed: %', j->'my_picks_confirmed';
  END IF;
END $$;

-- клієнт напряму викликати не може (ні гість, ні акаунт)
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM public.export_user_data('e1000000-0000-4000-8000-0000000061e1');
    RAISE EXCEPTION 'Test 10 failed: authenticated called export_user_data';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

ROLLBACK;
