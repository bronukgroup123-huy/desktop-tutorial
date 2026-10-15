import type { SmsPayload, SendResult } from "./types.ts";
import { normalizePhone } from "./sms.ts";

// ============================================================================
// Textbee — open-source Android SMS gateway (https://textbee.dev)
// API verified against https://textbee.dev/openapi.json (2026-10)
// ============================================================================

const TEXTBEE_API_URL = "https://api.textbee.dev/api/v1/gateway/send-sms";
const TEXTBEE_TIMEOUT_MS = 10_000;

/**
 * Надсилає SMS через Textbee (Android-телефон як gateway).
 *
 * Важлива семантика Textbee: HTTP 200 означає «прийнято чергою», а НЕ
 * «доставлено» — телефон може бути офлайн. Тому успіх мапиться у
 * `queued: true`, і доставку потрібно підтверджувати окремо
 * (GET /gateway/devices/{id}/sms-batch/{smsBatchId} або webhook).
 */
export async function sendSmsViaTextbee(
  payload: SmsPayload
): Promise<SendResult> {
  if (Deno.env.get("TEXTBEE_ENABLED") !== "true") {
    // Грацефулна деградація — див. firebase.ts sendPush.
    return {
      success: false,
      queued: false,
      errorMessage: "textbee_disabled",
    };
  }

  const apiKey = Deno.env.get("TEXTBEE_API_KEY");
  if (!apiKey) {
    return { success: false, queued: false, errorMessage: "textbee_no_api_key" };
  }

  const phone = normalizePhone(payload.phone);
  if (!phone) {
    return {
      success: false,
      queued: false,
      errorMessage: `textbee_invalid_phone: ${payload.phone}`,
    };
  }

  const body: Record<string, unknown> = {
    message: payload.text.slice(0, 480),
    recipients: [phone],
  };

  // deviceId опційний: без нього Textbee бере default-пристрій або
  // enabled-пристрій з найсвіжішим heartbeat.
  const deviceId = Deno.env.get("TEXTBEE_DEVICE_ID");
  if (deviceId) body.deviceId = deviceId;

  try {
    const response = await fetch(TEXTBEE_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(TEXTBEE_TIMEOUT_MS),
    });

    if (response.ok) {
      const data = await response.json().catch(() => null);
      const result = data?.data;

      if (result?.success === true) {
        // smsBatchId використовуємо як provider id для подальшого
        // опитування статусу доставки.
        const batchId: string | undefined =
          result.smsBatchId ?? result.smsBatch?.id;

        return {
          success: true,
          queued: true,
          providerMessageId: batchId,
        };
      }

      return {
        success: false,
        queued: false,
        errorMessage: `textbee_rejected: ${result?.message ?? "unknown"}`,
      };
    }

    const errorText = await response.text().catch(() => "");
    return {
      success: false,
      queued: false,
      errorMessage: `textbee_http_${response.status}: ${errorText.slice(0, 200)}`,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    // Timeout → transient (варто ретраїти); мережеві збої — теж transient.
    return { success: false, queued: false, errorMessage: `textbee_network: ${message}` };
  }
}

/**
 * Постійні помилки — ретрай не допоможе:
 * 400 (немає enabled-пристрою / email не верифікований),
 * 401 (невалідний API key).
 */
export function isTextbeePermanentError(errorMessage: string): boolean {
  const msg = errorMessage.toLowerCase();
  if (msg.includes("textbee_http_400")) return true;
  if (msg.includes("textbee_http_401")) return true;
  if (msg.includes("textbee_http_404")) return true;
  if (msg.includes("textbee_no_api_key")) return true;
  if (msg.includes("textbee_invalid_phone")) return true;
  return false;
}

/**
 * Rate-limited (429 або текст про ліміт плану) — варто відкласти,
 * а не ретраїти негайно.
 */
export function isTextbeeRateLimited(errorMessage: string): boolean {
  const msg = errorMessage.toLowerCase();
  if (msg.includes("textbee_http_429")) return true;
  if (msg.includes("plan limit")) return true;
  if (msg.includes("daily limit")) return true;
  if (msg.includes("monthly limit")) return true;
  if (msg.includes("textbee_rate_limited")) return true;
  return false;
}
