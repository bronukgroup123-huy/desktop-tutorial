import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { GuardianSession, GuardianAlert, Guardian } from "../types.ts";
import { renderNotification, getTemplate } from "./templates.ts";
import { sendPush, isTokenInvalidError } from "./firebase.ts";
import { sendSms, buildSmsText } from "./sms.ts";
import type { DispatchTarget, DispatchResult, RenderedNotification } from "./types.ts";

const CRITICAL_ALERT_TYPES: Set<string> = new Set([
  "sos",
  "overdue_hard",
]);

export async function dispatchAlert(
  db: SupabaseClient,
  alert: GuardianAlert,
  session: GuardianSession
): Promise<DispatchResult> {
  const result: DispatchResult = {
    alert_id: alert.id,
    notifications_created: 0,
    push_attempted: 0,
    sms_attempted: 0,
    skipped: 0,
  };

  const targets = await loadTargets(db, session.id, alert.alert_type);
  if (targets.length === 0) {
    await markAlertDelivered(db, alert.id);
    return result;
  }

  const pickerName = await getPickerName(db, session.user_id);

  const context = {
    picker_name: pickerName,
    session_url: buildSessionUrl(session.id),
    guardian_url: "",
    coords: session.last_known_coords
      ? {
          lat: (session.last_known_coords as any).coordinates?.[1] ?? 0,
          lng: (session.last_known_coords as any).coordinates?.[0] ?? 0,
        }
      : null,
    expected_return: session.expected_return,
  };

  const baseRendered = renderNotification(alert.alert_type, {
    ...alert.payload,
    session_id: session.id,
  }, context);

  const template = getTemplate(alert.alert_type);

  for (const target of targets) {
    const rendered: RenderedNotification = {
      ...baseRendered,
      url: buildGuardianUrl(target.guardian_id),
    };

    if (target.fcm_tokens.length > 0) {
      for (const token of target.fcm_tokens) {
        const { data: notif, error } = await db
          .from("guardian_notifications")
          .insert({
            guardian_id: target.guardian_id,
            alert_id: alert.id,
            channel: "push",
            status: "queued",
          })
          .select("id")
          .single();

        if (error) {
          console.error("[dispatcher] Failed to create push notification:", error);
          continue;
        }

        result.notifications_created++;

        const sendResult = await sendPush({
          token,
          title: rendered.title,
          body: rendered.body,
          data: { ...rendered.data, url: rendered.url },
          priority: template.priority <= 2 ? "high" : "normal",
        });

        await updateNotificationStatus(
          db,
          notif.id,
          sendResult.success ? "sent" : "failed",
          sendResult
        );

        if (sendResult.success) {
          result.push_attempted++;
        } else {
          if (sendResult.errorMessage && isTokenInvalidError(sendResult.errorMessage)) {
            await db
              .from("guardian_push_tokens")
              .update({ revoked_at: new Date().toISOString() })
              .eq("fcm_token", token);
          }
        }
      }
    }

    const needsSms =
      template.requiresSms ||
      target.fcm_tokens.length === 0;

    if (needsSms && target.phone) {
      const { data: notif, error } = await db
        .from("guardian_notifications")
        .insert({
          guardian_id: target.guardian_id,
          alert_id: alert.id,
          channel: "sms",
          status: "queued",
        })
        .select("id")
        .single();

      if (error) {
        console.error("[dispatcher] Failed to create sms notification:", error);
        continue;
      }

      result.notifications_created++;

      if (template.requiresSms) {
        const smsResult = await sendSms({
          phone: target.phone,
          text: buildSmsText(rendered, pickerName),
        });

        await updateNotificationStatus(
          db,
          notif.id,
          smsResult.success ? "sent" : "failed",
          smsResult
        );

        if (smsResult.success) {
          result.sms_attempted++;
        }
      }
    } else if (!target.phone && target.fcm_tokens.length === 0) {
      result.skipped++;
    }
  }

  if (result.notifications_created > 0) {
    await markAlertDelivered(db, alert.id);
  }

  return result;
}

async function loadTargets(
  db: SupabaseClient,
  sessionId: string,
  alertType: string
): Promise<DispatchTarget[]> {
  const isCritical = CRITICAL_ALERT_TYPES.has(alertType);

  let query = db
    .from("guardians")
    .select("id, phone, is_emergency")
    .eq("session_id", sessionId)
    .is("revoked_at", null);

  if (!isCritical) {
    query = query.eq("is_emergency", false);
  }

  const { data: guardians, error } = await query;

  if (error || !guardians) return [];

  const targets: DispatchTarget[] = [];

  for (const g of guardians) {
    const { data: tokens } = await db
      .from("guardian_push_tokens")
      .select("fcm_token")
      .eq("guardian_id", g.id)
      .is("revoked_at", null);

    targets.push({
      guardian_id: g.id,
      phone: g.phone,
      fcm_tokens: (tokens ?? []).map((t) => t.fcm_token),
      is_emergency: g.is_emergency,
    });
  }

  return targets;
}

async function getPickerName(
  db: SupabaseClient,
  userId: string
): Promise<string> {
  const { data } = await db
    .from("users")
    .select("name")
    .eq("id", userId)
    .maybeSingle();
  return data?.name ?? "Грибник";
}

function buildSessionUrl(sessionId: string): string {
  const base = Deno.env.get("GUARDIAN_BASE_URL") ?? "https://guardian.mushroomradar.com.ua";
  return `${base}/session/${sessionId}`;
}

function buildGuardianUrl(_guardianId: string): string {
  const base = Deno.env.get("GUARDIAN_BASE_URL") ?? "https://guardian.mushroomradar.com.ua";
  return `${base}/s/`;
}

async function updateNotificationStatus(
  db: SupabaseClient,
  notificationId: number,
  status: "sent" | "failed",
  result: { providerMessageId?: string; errorMessage?: string }
): Promise<void> {
  await db
    .from("guardian_notifications")
    .update({
      status,
      sent_at: status === "sent" ? new Date().toISOString() : null,
      provider_message_id: result.providerMessageId ?? null,
      error_message: result.errorMessage ?? null,
    })
    .eq("id", notificationId);
}

async function markAlertDelivered(
  db: SupabaseClient,
  alertId: number
): Promise<void> {
  await db
    .from("guardian_alerts")
    .update({ delivered_at: new Date().toISOString() })
    .eq("id", alertId);
}
