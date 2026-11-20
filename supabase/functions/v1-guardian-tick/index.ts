// ============================================================================
// Edge Function: v1-guardian-tick — щохвилини з pg_cron (ADR-022 §22.5 п.3):
// «Все добре?» у час повернення → без відповіді 15 хв — тривога Наглядачам; автозакриття.
// POST з ключем service_role. Логіка — `_shared/v1/guardian.ts` (`handleGuardianTick`).
// ============================================================================

import { handle, serviceClient } from "../_shared/http.ts";
import { handleGuardianTick } from "../_shared/v1/guardian.ts";
import { sendGuardianPush, sendTelegram, TELEGRAM_BOT } from "../_shared/v1/guardian-io.ts";

Deno.serve(handle((req) =>
  handleGuardianTick(req, {
    db: serviceClient(),
    serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    send: sendGuardianPush,
    telegram: TELEGRAM_BOT ? sendTelegram : undefined,
    telegramBot: TELEGRAM_BOT,
  })
));
