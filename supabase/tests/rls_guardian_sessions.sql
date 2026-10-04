-- ============================================================================
-- RLS Tests for Guardian Module
-- ============================================================================

-- Припускаємо, що в тестовій базі є користувачі:
-- user_a_id та user_b_id

-- ============================================================================
-- 1. Користувач A не бачить сесію користувача B
-- ============================================================================
SELECT 'Test 1: User A cannot see User B session' AS test_name;

SET request.jwt.claim.sub = 'user_a_id';

SELECT count(*) AS visible_sessions
FROM guardian_sessions
WHERE user_id = 'user_b_id';

-- Очікується: 0

-- ============================================================================
-- 2. Користувач A не може вставити guardian_session з user_id = B
-- ============================================================================
SELECT 'Test 2: User A cannot insert session for User B' AS test_name;

SET request.jwt.claim.sub = 'user_a_id';

INSERT INTO guardian_sessions (user_id, expected_return, original_return)
VALUES ('user_b_id', now() + interval '1 hour', now() + interval '1 hour');

-- Очікується: ERROR (permission denied)

-- ============================================================================
-- 3. Користувач A не може оновити сесію користувача B
-- ============================================================================
SELECT 'Test 3: User A cannot update User B session' AS test_name;

SET request.jwt.claim.sub = 'user_a_id';

UPDATE guardian_sessions
SET status = 'active'
WHERE user_id = 'user_b_id';

-- Очікується: 0 rows affected (RLS блокує)

-- ============================================================================
-- 4. Користувач A бачить тільки свої сесії
-- ============================================================================
SELECT 'Test 4: User A sees only own sessions' AS test_name;

SET request.jwt.claim.sub = 'user_a_id';

SELECT id, user_id, status
FROM guardian_sessions;

-- Всі рядки мають user_id = user_a_id

-- ============================================================================
-- 5. Перевірка RLS на guardians
-- ============================================================================
SELECT 'Test 5: User A cannot see guardians of User B' AS test_name;

SET request.jwt.claim.sub = 'user_a_id';

SELECT count(*) AS visible_guardians
FROM guardians g
JOIN guardian_sessions s ON s.id = g.session_id
WHERE s.user_id = 'user_b_id';

-- Очікується: 0

-- ============================================================================
-- 6. Перевірка RLS на guardian_track
-- ============================================================================
SELECT 'Test 6: User A cannot see track of User B' AS test_name;

SET request.jwt.claim.sub = 'user_a_id';

SELECT count(*) AS visible_track_points
FROM guardian_track t
JOIN guardian_sessions s ON s.id = t.session_id
WHERE s.user_id = 'user_b_id';

-- Очікується: 0

-- ============================================================================
-- 7. Перевірка RLS на guardian_alerts
-- ============================================================================
SELECT 'Test 7: User A cannot see alerts of User B' AS test_name;

SET request.jwt.claim.sub = 'user_a_id';

SELECT count(*) AS visible_alerts
FROM guardian_alerts a
JOIN guardian_sessions s ON s.id = a.session_id
WHERE s.user_id = 'user_b_id';

-- Очікується: 0

-- ============================================================================
-- 8. Скидаємо JWT claim
-- ============================================================================
RESET request.jwt.claim.sub;
