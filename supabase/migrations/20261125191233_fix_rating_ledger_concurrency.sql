-- SEC-007: serialize per-user ledger recomputation.
--
-- Without the row lock, two concurrent INSERT statements can each calculate
-- the sum before the other transaction commits. The second UPDATE then wins
-- with a stale total even though both immutable ledger events remain stored.
CREATE OR REPLACE FUNCTION public.rating_events_apply()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- Lock before reading the ledger. Under READ COMMITTED, the following
  -- statement receives a fresh snapshot after a concurrent writer commits.
  PERFORM 1
  FROM public.users u
  WHERE u.id = NEW.user_id
  FOR UPDATE;

  UPDATE public.users u
  SET rating = greatest(
    0,
    (SELECT coalesce(sum(e.delta), 0) FROM public.rating_events e WHERE e.user_id = NEW.user_id)
  )
  WHERE u.id = NEW.user_id;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.rating_events_apply() FROM PUBLIC, anon, authenticated;
