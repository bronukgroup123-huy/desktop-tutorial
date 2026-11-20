// ============================================================================
// Edge Function: v1-telegram-webhook — бот тривог Наглядача (ADR-022 §22.2, B4.11).
// Telegram надсилає сюди повідомлення бота з секретом у заголовку
// X-Telegram-Bot-Api-Secret-Token. /start <код> — прив'язати чат, /stop — відв'язати.
// ============================================================================

import { handle, serviceClient } from "../_shared/http.ts";
import { handleTelegramWebhook } from "../_shared/v1/guardian.ts";
import { sendTelegram, TELEGRAM_SECRET } from "../_shared/v1/guardian-io.ts";

Deno.serve(handle((req) =>
  handleTelegramWebhook(req, { db: serviceClient(), secret: TELEGRAM_SECRET, telegram: sendTelegram })
));
