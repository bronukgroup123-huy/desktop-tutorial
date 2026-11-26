-- ============================================================================
-- Ліміт запитів для v1-ендпоінтів: прибрати застарілий перелік у CHECK
-- ============================================================================
-- ip_rate_limit.endpoint дозволяв лише ('forecast', 'picks', 'regions', 'catalog') — ендпоінти
-- вересня. Усі v1-* (v1-me, v1-analysis, v1-picks, …) викликають check_and_increment_ip_rate_limit
-- зі своєю назвою, вставка порушувала CHECK, RPC падав. Поки лімітер був fail-open, запит
-- просто пропускався без ліміту; після SEC-003 (fail closed) кожен такий запит отримує
-- 503 rate_limit_unavailable — застосунок «без інтернету».
--
-- Замість переліку — перевірка формату назви: нові ендпоінти не потребують міграції, а в
-- таблицю не потрапить довільний рядок.
ALTER TABLE public.ip_rate_limit DROP CONSTRAINT IF EXISTS ip_rate_limit_endpoint_check;
ALTER TABLE public.ip_rate_limit
  ADD CONSTRAINT ip_rate_limit_endpoint_check CHECK (endpoint ~ '^[a-z0-9][a-z0-9-]{0,63}$');
