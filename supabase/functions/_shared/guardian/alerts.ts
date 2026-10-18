import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { AlertType } from "./types.ts";
import { sendTelegramAlert } from "../telegram.ts";

/**
 * Cooldown-вікна для дедуплікації алертів (у хвилинах).
 * 0 — без cooldown (кожен алерт унікальний, напр. SOS).
 * Типи, що не перелічені, отримують DEFAULT_COOLDOWN_MINUTES.
 */
const ALERT_COOLDOWN_MINUTES: Partial<Record<AlertType, number>> = {
  overdue_soft: 360,   // 6h
  overdue_medium: 360, // 6h
  overdue_hard: 60,    // 1h
  offline: 30,         // 30 min
  sos: 0,              // кожен SOS унікальний — без cooldown
  config_missing: 60,  // 1h — не спамити адміна
  tick_errors_high: 60, // 1h — не спамити адміна
};

const DEFAULT_COOLDOWN_MINUTES = 60;

export async function createAlertOnce(
  db: SupabaseClient,
  sessionId: string,
  alertType: AlertType,
  payload: Record<string, unknown> = {}
): Promise<boolean> {
  const cooldownMin = ALERT_COOLDOWN_MINUTES[alertType] ?? DEFAULT_COOLDOWN_MINUTES;

  // cooldown 0 → завжди створюємо (перевірка наявності непотрібна)
  if (cooldownMin > 0) {
    const cutoff = new Date(
      Date.now() - cooldownMin * 60 * 1000
    ).toISOString();

    const { data: existing } = await db
      .from("guardian_alerts")
      .select("id")
      .eq("session_id", sessionId)
      .eq("alert_type", alertType)
      .gte("created_at", cutoff)
      .limit(1)
      .maybeSingle();

    if (existing) return false;
  }

  const { error } = await db.from("guardian_alerts").insert({
    session_id: sessionId,
    alert_type: alertType,
    payload,
  });

  if (error) {
    console.error(`[alerts] Failed to create alert ${alertType}:`, error);
    return false;
  }

  // Надсилаємо Telegram-алерт адміну (не блокуючи основний потік критично)
  try {
    const isCritical =
      alertType === "config_missing" || alertType === "tick_errors_high";
    const payloadText =
      payload && typeof payload === "object" && Object.keys(payload).length > 0
        ? `\n\nДеталі: ${JSON.stringify(payload)}`
        : "";
    await sendTelegramAlert(
      `Алерт <b>${alertType}</b> для сесії <code>${sessionId}</code>${payloadText}`,
      isCritical
    );
  } catch {
    // sendTelegramAlert вже сам обробляє помилки і ніколи не кидає виключення
  }

  return true;
}

/**
 * Годин з моменту останнього алерта даного типу для сесії.
 * null — такого алерта ще не було.
 */
export async function getHoursSinceLastAlert(
  db: SupabaseClient,
  sessionId: string,
  alertType: AlertType
): Promise<number | null> {
  const { data } = await db
    .from("guardian_alerts")
    .select("created_at")
    .eq("session_id", sessionId)
    .eq("alert_type", alertType)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!data?.created_at) return null;

  const ms = Date.now() - new Date(data.created_at).getTime();
  return ms / (1000 * 60 * 60);
}
