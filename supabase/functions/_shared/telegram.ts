// ============================================================================
// supabase/functions/_shared/telegram.ts
// Відправка криттових алертів адміну у Telegram через Bot API.
// ============================================================================

export async function sendTelegramAlert(
  message: string,
  isCritical: boolean = false
): Promise<boolean> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const chatId = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID");

  if (!token || !chatId) {
    console.warn(
      "[telegram] TELEGRAM_BOT_TOKEN або TELEGRAM_ADMIN_CHAT_ID не задано — алерт не надіслано"
    );
    return false;
  }

  const text = isCritical ? `🚨 #КРИТИЧНО\n${message}` : message;

  try {
    const response = await fetch(
      `https://api.telegram.org/bot${token}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text,
          parse_mode: "HTML",
        }),
      }
    );

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      console.warn(
        `[telegram] Telegram API помилка ${response.status}: ${body}`
      );
      return false;
    }

    return true;
  } catch (err) {
    console.warn("[telegram] Не вдалося надіслати Telegram-алерт:", err);
    return false;
  }
}
