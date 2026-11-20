// Мережеві залежності Наглядача (push через Firebase, Telegram Bot API) — спільні для
// v1-guardian, v1-guardian-tick, v1-telegram-webhook. Логіка — `guardian.ts` (тестується з моками).
import { sendPush } from "../guardian/notifications/firebase.ts";
import type { PushMessage } from "./guardian.ts";

export async function sendGuardianPush(token: string, msg: PushMessage, urgent: boolean) {
  const r = await sendPush({ token, title: msg.title, body: msg.body, data: msg.data, priority: urgent ? "high" : "normal" });
  return { ok: r.success, unregistered: /registration-token-not-registered|not.?registered|invalid-registration/i.test(r.errorMessage ?? "") };
}

const BOT_TOKEN = Deno.env.get("GUARDIAN_TELEGRAM_BOT_TOKEN") ?? "";
export const TELEGRAM_BOT = BOT_TOKEN ? (Deno.env.get("GUARDIAN_TELEGRAM_BOT_USERNAME") ?? null) : null;
export const TELEGRAM_SECRET = Deno.env.get("GUARDIAN_TELEGRAM_WEBHOOK_SECRET") ?? "";

/** Текст у чат Telegram (без HTML-розмітки — ніби звичайне повідомлення). */
export async function sendTelegram(chatId: number, text: string): Promise<boolean> {
  if (!BOT_TOKEN) return false;
  try {
    const r = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
      signal: AbortSignal.timeout(8000),
    });
    await r.body?.cancel();
    return r.ok;
  } catch {
    return false;
  }
}
