// ============================================================================
// Edge Function: v1-guardian — Наглядач у застосунку (ADR-022; BACKEND_PLAN B4.4–B4.11)
// GET / POST /functions/v1/v1-guardian — логіка в `_shared/v1/guardian.ts`.
// ============================================================================

import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleGuardian } from "../_shared/v1/guardian.ts";
import { sendGuardianPush, sendTelegram, TELEGRAM_BOT } from "../_shared/v1/guardian-io.ts";

Deno.serve(handle((req) =>
  handleGuardian(req, {
    db: serviceClient(),
    verify: supabaseTokenVerifier,
    send: sendGuardianPush,
    telegram: TELEGRAM_BOT ? sendTelegram : undefined,
    telegramBot: TELEGRAM_BOT,
    // Pro (`guardians_3`) з'явиться з RevenueCat (B6.3); до того — 1 Наглядач у поході.
    hasGuardians3: () => Promise.resolve(false),
  })
));
