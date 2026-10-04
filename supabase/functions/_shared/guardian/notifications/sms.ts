import type { SmsPayload, SendResult } from "./types.ts";

const TURBOSMS_API_URL = "https://api.turbosms.ua/message/send.json";

export async function sendSms(payload: SmsPayload): Promise<SendResult> {
  const token = Deno.env.get("TURBOSMS_TOKEN");
  const sender = Deno.env.get("TURBOSMS_SENDER") ?? "MushroomRadar";

  if (!token) {
    return {
      success: false,
      errorMessage: "TURBOSMS_TOKEN not set",
    };
  }

  const phone = normalizePhone(payload.phone);
  if (!phone) {
    return {
      success: false,
      errorMessage: `Invalid phone: ${payload.phone}`,
    };
  }

  const text = payload.text.slice(0, 480);

  try {
    const response = await fetch(TURBOSMS_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${btoa(token)}`,
      },
      body: JSON.stringify({
        recipients: [phone],
        sms: {
          sender,
          text,
        },
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      return {
        success: false,
        errorMessage: `TurboSMS HTTP ${response.status}: ${JSON.stringify(data)}`,
      };
    }

    const result = data?.response_result?.[0];

    if (result?.response_status === "OK") {
      return {
        success: true,
        providerMessageId: result?.response_code ?? result?.message_id,
      };
    }

    return {
      success: false,
      errorMessage: `TurboSMS error: ${result?.response_status ?? "unknown"}`,
    };
  } catch (err) {
    return {
      success: false,
      errorMessage: err instanceof Error ? err.message : String(err),
    };
  }
}

export function normalizePhone(phone: string): string | null {
  const cleaned = phone.replace(/[^\d+]/g, "");

  if (/^\+380\d{9}$/.test(cleaned)) return cleaned;
  if (/^380\d{9}$/.test(cleaned)) return `+${cleaned}`;
  if (/^0\d{9}$/.test(cleaned)) return `+38${cleaned}`;

  return null;
}

export function buildSmsText(
  rendered: { title: string; body: string; url?: string },
  pickerName: string
): string {
  const parts = [
    rendered.title,
    rendered.body,
  ];

  if (rendered.url) {
    parts.push(rendered.url);
  }

  return parts.join("\n").slice(0, 480);
}
