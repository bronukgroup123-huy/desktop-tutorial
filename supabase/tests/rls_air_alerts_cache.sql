-- ============================================================================
-- Спільний кеш повітряних тривог (міграція 20261118120000)
--   * оренду оновлення бере лише одна копія функції; повторно — ні, поки оренда триває;
--   * клієнтам (anon, authenticated) — ні таблиці, ні функції.
-- Самодостатній тест: усе в транзакції, наприкінці ROLLBACK.
-- ============================================================================

BEGIN;

SET LOCAL ROLE service_role;

DO $$
BEGIN
  UPDATE public.air_alerts_cache SET fetched_at = NULL, refreshing_until = NULL, backoff_until = NULL WHERE id = 1;
  IF NOT public.air_alerts_claim_refresh(45, 15) THEN
    RAISE EXCEPTION 'Test 1 failed: stale cache must be claimable';
  END IF;
  IF public.air_alerts_claim_refresh(45, 15) THEN
    RAISE EXCEPTION 'Test 2 failed: second copy must not claim while the lease is held';
  END IF;
  UPDATE public.air_alerts_cache SET fetched_at = now(), refreshing_until = NULL WHERE id = 1;
  IF public.air_alerts_claim_refresh(45, 15) THEN
    RAISE EXCEPTION 'Test 3 failed: fresh cache must not be claimed';
  END IF;
  UPDATE public.air_alerts_cache SET fetched_at = now() - interval '1 minute', backoff_until = now() + interval '2 minutes' WHERE id = 1;
  IF public.air_alerts_claim_refresh(45, 15) THEN
    RAISE EXCEPTION 'Test 4 failed: no refresh during a 429 pause';
  END IF;
END $$;

RESET ROLE;
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.air_alerts_cache;
    RAISE EXCEPTION 'Test 5 failed: anon can read air_alerts_cache';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.air_alerts_claim_refresh(45, 15);
    RAISE EXCEPTION 'Test 6 failed: anon can claim the refresh';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.air_alerts_cache;
    RAISE EXCEPTION 'Test 7 failed: authenticated can read air_alerts_cache';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;
ROLLBACK;
