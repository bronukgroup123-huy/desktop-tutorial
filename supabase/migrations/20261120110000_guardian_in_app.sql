-- ============================================================================
-- Наглядач у застосунку (ADR-022 §22.2, §22.5; BACKEND_PLAN B4.4, B4.7, B4.8, B4.9, B4.11)
--
-- Замість старих сесій із кодами-посиланнями (`guardian_sessions` / `guardians`, web-guardian)
-- — Наглядач лише серед друзів і лише в застосунку, під своїм акаунтом:
--  * guardian_links — «Олена просить бути її Наглядачем» → друг погоджується (один раз);
--    відмовитись чи прибрати — будь-коли; перестали бути друзями / блок — зв'язок зникає;
--  * hikes — похід (сесія): маршрут обов'язковий, час повернення; статуси
--      active → check («Все добре?» у час повернення) → alert (без відповіді 15 хв —
--      тривога Наглядачам); sos — тривога одразу; closed — «Я вдома» / автозакриття;
--    без порогів затримки 0 / +30 / +90 хв і без тривоги «стоїть на місці» (§22.5 п.3);
--  * hike_guardians — хто з Наглядачів дивиться цей похід (1 безкоштовно, до 3 — Pro);
--  * hike_points — живий трек; бачать лише Наглядачі цього походу, поки він триває;
--    після закриття трек видаляється (GPX-архів Pro — B4.6);
--  * guardian_telegram, telegram_link_codes — тривоги в Telegram (без координат, §22.2).
-- Доступ до таблиць — лише service_role (Edge Functions v1-guardian, v1-guardian-tick,
-- v1-telegram-webhook перевіряють акаунт, дружбу й участь у поході).
-- ============================================================================

-- ─── Зв'язок «грибник → Наглядач» ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.guardian_links (
  owner_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  guardian_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ,
  PRIMARY KEY (owner_id, guardian_id),
  CONSTRAINT guardian_links_not_self CHECK (owner_id <> guardian_id)
);
CREATE INDEX IF NOT EXISTS guardian_links_guardian_idx ON public.guardian_links (guardian_id, status);

-- ─── Похід ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hikes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  client_id TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'check', 'alert', 'sos', 'closed')),
  -- [{lat, lng, label}] — маршрут обов'язковий (§22.5 п.4)
  route JSONB NOT NULL CHECK (jsonb_typeof(route) = 'array' AND jsonb_array_length(route) BETWEEN 1 AND 50),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expected_return TIMESTAMPTZ NOT NULL,
  last_lat DOUBLE PRECISION,
  last_lng DOUBLE PRECISION,
  last_accuracy REAL,
  last_at TIMESTAMPTZ,
  last_signal_at TIMESTAMPTZ,
  battery SMALLINT CHECK (battery BETWEEN 0 AND 100),
  gps_issue_at TIMESTAMPTZ,
  check_sent_at TIMESTAMPTZ,
  alert_sent_at TIMESTAMPTZ,
  sos_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  closed_reason TEXT CHECK (closed_reason IS NULL OR closed_reason IN ('home', 'auto', 'account')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT hikes_closed CHECK ((status = 'closed') = (closed_at IS NOT NULL))
);
-- Один незакритий похід на людину; повтор «Почати» з тим самим client_id — без дубля.
CREATE UNIQUE INDEX IF NOT EXISTS hikes_one_open_uidx ON public.hikes (owner_id) WHERE status <> 'closed';
CREATE UNIQUE INDEX IF NOT EXISTS hikes_client_uidx ON public.hikes (owner_id, client_id) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS hikes_open_idx ON public.hikes (status, expected_return) WHERE status <> 'closed';

CREATE TABLE IF NOT EXISTS public.hike_guardians (
  hike_id UUID NOT NULL REFERENCES public.hikes (id) ON DELETE CASCADE,
  guardian_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  PRIMARY KEY (hike_id, guardian_id)
);
CREATE INDEX IF NOT EXISTS hike_guardians_guardian_idx ON public.hike_guardians (guardian_id);

CREATE TABLE IF NOT EXISTS public.hike_points (
  id BIGSERIAL PRIMARY KEY,
  hike_id UUID NOT NULL REFERENCES public.hikes (id) ON DELETE CASCADE,
  lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION NOT NULL CHECK (lng BETWEEN -180 AND 180),
  accuracy REAL,
  -- точність гірша за 100 м (глушіння / підміна GPS, §22.5 п.5): у треку позначено, у «останнє
  -- місце» не йде
  low_accuracy BOOLEAN NOT NULL DEFAULT false,
  recorded_at TIMESTAMPTZ NOT NULL,
  UNIQUE (hike_id, recorded_at)
);
CREATE INDEX IF NOT EXISTS hike_points_hike_idx ON public.hike_points (hike_id, recorded_at);

-- ─── Telegram (B4.11) ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.guardian_telegram (
  user_id UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  chat_id BIGINT NOT NULL UNIQUE,
  linked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.telegram_link_codes (
  code_hash TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS telegram_link_codes_user_idx ON public.telegram_link_codes (user_id);

ALTER TABLE public.guardian_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guardian_links FORCE ROW LEVEL SECURITY;
ALTER TABLE public.hikes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hikes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.hike_guardians ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hike_guardians FORCE ROW LEVEL SECURITY;
ALTER TABLE public.hike_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hike_points FORCE ROW LEVEL SECURITY;
ALTER TABLE public.guardian_telegram ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guardian_telegram FORCE ROW LEVEL SECURITY;
ALTER TABLE public.telegram_link_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.telegram_link_codes FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.guardian_links, public.hikes, public.hike_guardians, public.hike_points,
  public.guardian_telegram, public.telegram_link_codes FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.hike_points_id_seq FROM anon, authenticated;

-- Координати й трек — лише власнику і Наглядачам незакритого походу (зареєстрованим).
-- Клієнт ходить через Edge Function (service_role), політики — другий рубіж (B4.9).
DROP POLICY IF EXISTS hikes_owner_or_guardian_read ON public.hikes;
CREATE POLICY hikes_owner_or_guardian_read ON public.hikes
  FOR SELECT TO authenticated
  USING (
    public.is_registered() AND (
      owner_id = auth.uid()
      OR (status <> 'closed' AND EXISTS (
        SELECT 1 FROM public.hike_guardians g WHERE g.hike_id = hikes.id AND g.guardian_id = auth.uid()
      ))
    )
  );
DROP POLICY IF EXISTS hike_points_owner_or_guardian_read ON public.hike_points;
CREATE POLICY hike_points_owner_or_guardian_read ON public.hike_points
  FOR SELECT TO authenticated
  USING (
    public.is_registered() AND EXISTS (
      SELECT 1 FROM public.hikes h
      WHERE h.id = hike_points.hike_id
        AND (h.owner_id = auth.uid()
             OR (h.status <> 'closed' AND EXISTS (
               SELECT 1 FROM public.hike_guardians g WHERE g.hike_id = h.id AND g.guardian_id = auth.uid()
             )))
    )
  );
DROP POLICY IF EXISTS hike_guardians_member_read ON public.hike_guardians;
CREATE POLICY hike_guardians_member_read ON public.hike_guardians
  FOR SELECT TO authenticated
  USING (public.is_registered() AND guardian_id = auth.uid());
-- (Без рекурсії: власник бачить своїх Наглядачів через Edge Function.)
GRANT SELECT ON public.hikes, public.hike_points, public.hike_guardians TO authenticated;

-- ─── Перестали бути друзями / блок → Наглядач зникає (і з незакритого походу) ──
CREATE OR REPLACE FUNCTION public.guardian_links_on_unfriend()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  a UUID := COALESCE(OLD.user_a, NEW.user_a);
  b UUID := COALESCE(OLD.user_b, NEW.user_b);
BEGIN
  IF TG_OP = 'DELETE' OR NEW.status <> 'accepted' THEN
    DELETE FROM public.guardian_links l
    WHERE (l.owner_id = a AND l.guardian_id = b) OR (l.owner_id = b AND l.guardian_id = a);
    DELETE FROM public.hike_guardians g
    USING public.hikes h
    WHERE g.hike_id = h.id AND h.status <> 'closed'
      AND ((h.owner_id = a AND g.guardian_id = b) OR (h.owner_id = b AND g.guardian_id = a));
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS friendships_guardian_cleanup ON public.friendships;
CREATE TRIGGER friendships_guardian_cleanup
  AFTER DELETE OR UPDATE OF status ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.guardian_links_on_unfriend();

-- Наглядач перестав бути Наглядачем — і з незакритого походу теж.
CREATE OR REPLACE FUNCTION public.hike_guardians_on_unlink()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  DELETE FROM public.hike_guardians g
  USING public.hikes h
  WHERE g.hike_id = h.id AND h.status <> 'closed' AND h.owner_id = OLD.owner_id AND g.guardian_id = OLD.guardian_id;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS guardian_links_unlink ON public.guardian_links;
CREATE TRIGGER guardian_links_unlink
  AFTER DELETE ON public.guardian_links
  FOR EACH ROW EXECUTE FUNCTION public.hike_guardians_on_unlink();

-- Закритий похід: трек видаляється (Наглядач більше нічого не бачить; GPX Pro — B4.6).
CREATE OR REPLACE FUNCTION public.hikes_on_close()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.status = 'closed' AND OLD.status <> 'closed' THEN
    DELETE FROM public.hike_points p WHERE p.hike_id = NEW.id;
    NEW.last_lat := NULL;
    NEW.last_lng := NULL;
    NEW.last_accuracy := NULL;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS hikes_close ON public.hikes;
CREATE TRIGGER hikes_close
  BEFORE UPDATE ON public.hikes
  FOR EACH ROW EXECUTE FUNCTION public.hikes_on_close();

-- ─── Розклад: «Все добре?» → тривога, автозакриття ─────────────────────────
-- Повертає, кому що надіслати (надсилає v1-guardian-tick):
--   check     — грибнику «Все добре?» (настав час повернення);
--   alert     — Наглядачам: не відповів 15 хв;
--   autoclose — Наглядачам: похід закрито автоматично (48 год після часу повернення).
CREATE OR REPLACE FUNCTION public.hike_tick(p_now TIMESTAMPTZ DEFAULT now())
RETURNS TABLE (hike_id UUID, kind TEXT, owner_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  WITH c AS (
    UPDATE public.hikes h SET status = 'check', check_sent_at = p_now
    WHERE h.status = 'active' AND h.expected_return <= p_now
    RETURNING h.id, h.owner_id
  )
  SELECT c.id, 'check'::text, c.owner_id FROM c;

  RETURN QUERY
  WITH a AS (
    UPDATE public.hikes h SET status = 'alert', alert_sent_at = p_now
    WHERE h.status = 'check' AND h.check_sent_at <= p_now - interval '15 minutes'
    RETURNING h.id, h.owner_id
  )
  SELECT a.id, 'alert'::text, a.owner_id FROM a;

  RETURN QUERY
  WITH z AS (
    UPDATE public.hikes h SET status = 'closed', closed_at = p_now, closed_reason = 'auto'
    WHERE h.status <> 'closed' AND h.expected_return <= p_now - interval '48 hours'
    RETURNING h.id, h.owner_id
  )
  SELECT z.id, 'autoclose'::text, z.owner_id FROM z;

  DELETE FROM public.telegram_link_codes t WHERE t.expires_at < p_now;
END;
$$;

REVOKE ALL ON FUNCTION public.guardian_links_on_unfriend() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hike_guardians_on_unlink() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hikes_on_close() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hike_tick(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hike_tick(TIMESTAMPTZ) TO service_role;

-- ─── Cron: старий guardian-tick (пороги, посилання) → v1-guardian-tick щохвилини ──
DO $do$
DECLARE
  jid BIGINT;
  jname TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;
  FOREACH jname IN ARRAY ARRAY['guardian-tick-every-minute', 'guardian-retry-every-30s', 'guardian-retry-every-minute'] LOOP
    SELECT jobid INTO jid FROM cron.job WHERE jobname = jname;
    IF jid IS NOT NULL THEN
      PERFORM cron.unschedule(jid);
    END IF;
  END LOOP;
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'v1-guardian-tick';
  IF jid IS NOT NULL THEN
    PERFORM cron.unschedule(jid);
  END IF;
  PERFORM cron.schedule(
    'v1-guardian-tick',
    '* * * * *',
    $tick$
    SELECT net.http_post(
      url := (SELECT url FROM public.guardian_fn_config()) || '/functions/v1/v1-guardian-tick',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT service_key FROM public.guardian_fn_config())
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 20000
    )
    WHERE (SELECT service_key FROM public.guardian_fn_config()) IS NOT NULL
      AND (SELECT url FROM public.guardian_fn_config()) IS NOT NULL;
    $tick$
  );
END;
$do$;
