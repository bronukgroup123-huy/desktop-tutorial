// ============================================================================
// Edge Function: test-telegram
// GET / — тестує інтеграцію з Telegram Bot API через sendTelegramAlert.
// ============================================================================
import { sendTelegramAlert } from "../_shared/telegram.ts";

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return json({ error: "method_not_allowed" }, 405);
  }

  await sendTelegramAlert(
    "Це тестове повідомлення з коду Supabase. Якщо ти це бачиш — інтеграція працює!",
    true
  );

  return json({ ok: true, message: "Спроба відправки" }, 200);
});
