import { initializeApp, cert, getApps } from "npm:firebase-admin@12/app";
import { getMessaging } from "npm:firebase-admin@12/messaging";
import type { PushPayload, SendResult } from "./types.ts";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let initialized = false;

function ensureInitialized(): void {
  if (initialized) return;

  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON not set");
  }

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(raw);
  } catch {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is invalid JSON");
  }

  if (getApps().length === 0) {
    initializeApp({
      credential: cert({
        projectId: sa.project_id,
        clientEmail: sa.client_email,
        privateKey: sa.private_key.replace(/\\n/g, "\n"),
      }),
    });
  }

  initialized = true;
}

export async function sendPush(payload: PushPayload): Promise<SendResult> {
  try {
    ensureInitialized();
  } catch (err) {
    return {
      success: false,
      errorMessage: err instanceof Error ? err.message : "Firebase init failed",
    };
  }

  try {
    const response = await getMessaging().send({
      token: payload.token,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data ?? {},
      webpush: {
        fcmOptions: {
          link: payload.data?.url,
        },
        notification: {
          icon: "/icon-192.png",
          badge: "/badge-72.png",
          requireInteraction: payload.priority === "high",
        },
      },
      android: {
        priority: payload.priority === "high" ? "high" : "normal",
      },
      apns: {
        headers: {
          "apns-priority": payload.priority === "high" ? "10" : "5",
        },
      },
    });

    return {
      success: true,
      providerMessageId: response,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      success: false,
      errorMessage: message,
    };
  }
}

export async function sendPushMulti(
  tokens: string[],
  notification: { title: string; body: string; data?: Record<string, string>; priority: "high" | "normal" }
): Promise<Array<{ token: string; result: SendResult }>> {
  if (tokens.length === 0) return [];

  try {
    ensureInitialized();
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Firebase init failed";
    return tokens.map((t) => ({
      token: t,
      result: { success: false, errorMessage: msg },
    }));
  }

  try {
    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data ?? {},
      webpush: {
        fcmOptions: {
          link: notification.data?.url,
        },
      },
    });

    return response.responses.map((r, i) => ({
      token: tokens[i],
      result: r.success
        ? { success: true, providerMessageId: r.messageId }
        : { success: false, errorMessage: r.error?.message ?? "Unknown error" },
    }));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return tokens.map((t) => ({
      token: t,
      result: { success: false, errorMessage: msg },
    }));
  }
}

export function isTokenInvalidError(errorMessage: string): boolean {
  const invalidPatterns = [
    "registration-token-not-registered",
    "invalid-registration-token",
    "invalid-argument",
    "mismatched-credential",
  ];
  return invalidPatterns.some((p) => errorMessage.toLowerCase().includes(p));
}
