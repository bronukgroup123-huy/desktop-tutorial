import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { sendSms } from "./sms.ts";
import { sendPush, isTokenInvalidError } from "./firebase.ts";
import type { SendResult } from "./types.ts";

const RETRY_DELAYS_SEC = [10, 60, 300];
const MAX_RETRIES = RETRY_DELAYS_SEC.length;

function nextRetryAfter(retryCount: number): Date | null {
  // retryCount — кількість вже провальних спроб (0-indexed перед цим ретраєм).
  // Якщо це перший ретрай (retryCount === 0), використовуємо RETRY_DELAYS_SEC[0].
  const idx = Math.min(retryCount, MAX_RETRIES - 1);
  const delaySec = RETRY_DELAYS_SEC[idx];
  return new Date(Date.now() + delaySec * 1000);
}

function guardianBaseUrl(): string {
  return (
    Deno.env.get("GUARDIAN_BASE_URL") ??
    "https://desktop-tutorial-eta-tan.vercel.app"
  );
}

export interface RetryStats {
  queued_processed: number;
  push_sent: number;
  sms_sent: number;
  fallback_sms: number;
  failed: number;
  skipped: number;
}

export async function processQueue(db: SupabaseClient): Promise<RetryStats> {
  const stats: RetryStats = {
    queued_processed: 0,
    push_sent: 0,
    sms_sent: 0,
    fallback_sms: 0,
    failed: 0,
    skipped: 0,
  };

  const nowIso = new Date().toISOString();
  const tenSecAgo = new Date(Date.now() - 10_000).toISOString();

  const { data: queued } = await db
    .from("guardian_notifications")
    .select(`
      id, guardian_id, alert_id, channel, status,
      retry_count, next_retry_at,
      guardian:guardians!inner(id, phone, name),
      alert:guardian_alerts!inner(id, alert_type, payload)
    `)
    .eq("status", "queued")
    .or("next_retry_at.is null,next_retry_at.lte." + nowIso)
    .lt("created_at", tenSecAgo)
    .limit(100);

  for (const notif of queued ?? []) {
    stats.queued_processed++;

    try {
      await processQueuedNotification(db, notif, stats);
    } catch (err) {
      console.error(`[queue] Error processing notification ${notif.id}:`, err);
      stats.failed++;
    }
  }

  const sixtySecAgo = new Date(Date.now() - 60_000).toISOString();

  const { data: silentPush } = await db
    .from("guardian_notifications")
    .select(`
      id, guardian_id, alert_id,
      guardian:guardians!inner(id, phone, name),
      alert:guardian_alerts!inner(id, alert_type, payload)
    `)
    .eq("channel", "push")
    .eq("status", "sent")
    .is("delivered_at", null)
    .lt("sent_at", sixtySecAgo)
    .limit(50);

  for (const push of silentPush ?? []) {
    if (!push.guardian?.phone) {
      stats.skipped++;
      continue;
    }

    const { data: existingSms } = await db
      .from("guardian_notifications")
      .select("id")
      .eq("guardian_id", push.guardian_id)
      .eq("alert_id", push.alert_id)
      .eq("channel", "sms")
      .limit(1)
      .maybeSingle();

    if (existingSms) {
      stats.skipped++;
      continue;
    }

    const { data: newSms } = await db
      .from("guardian_notifications")
      .insert({
        guardian_id: push.guardian_id,
        alert_id: push.alert_id,
        channel: "sms",
        status: "queued",
      })
      .select("id")
      .single();

    if (!newSms) continue;

    try {
      const smsText = `MushroomRadar: ${push.alert.alert_type}\n${guardianBaseUrl()}/s/`;
      const result = await sendSms({
        phone: push.guardian.phone,
        text: smsText,
      });

      await updateNotification(db, newSms.id, result);
      if (result.success) stats.fallback_sms++;
      else stats.failed++;
    } catch (err) {
      console.error("[queue] Fallback SMS error:", err);
      stats.failed++;
    }
  }

  return stats;
}

async function processQueuedNotification(
  db: SupabaseClient,
  notif: any,
  stats: RetryStats
): Promise<void> {
  if (notif.channel === "push") {
    const { data: tokens } = await db
      .from("guardian_push_tokens")
      .select("fcm_token")
      .eq("guardian_id", notif.guardian_id)
      .is("revoked_at", null);

    if (!tokens || tokens.length === 0) {
      await updateNotificationStatus(db, notif.id, "skipped", "No push tokens");
      stats.skipped++;
      return;
    }

    const title = `MushroomRadar`;
    const body = `${notif.alert.alert_type}`;

    let anySuccess = false;
    let anyQueued = false;
    for (const t of tokens) {
      const result = await sendPush({
        token: t.fcm_token,
        title,
        body,
        priority: "high",
      });

      if (result.success) anySuccess = true;
      if (result.queued) anyQueued = true;
      if (!result.success && result.errorMessage && isTokenInvalidError(result.errorMessage)) {
        await db
          .from("guardian_push_tokens")
          .update({ revoked_at: new Date().toISOString() })
          .eq("fcm_token", t.fcm_token);
      }
    }

    if (anyQueued) {
      await updateNotificationStatus(db, notif.id, "queued");
      stats.skipped++;
    } else if (anySuccess) {
      await updateNotificationStatus(db, notif.id, "sent");
      stats.push_sent++;
    } else {
      await recordFailure(db, notif.id, notif.retry_count, "All push tokens failed");
      stats.failed++;
    }
    return;
  }

  if (notif.channel === "sms") {
    if (!notif.guardian?.phone) {
      await updateNotificationStatus(db, notif.id, "skipped", "No phone");
      stats.skipped++;
      return;
    }

    const text = `MushroomRadar: ${notif.alert.alert_type}`;
    const result = await sendSms({ phone: notif.guardian.phone, text });

    if (result.success || result.queued) {
      await updateNotification(db, notif.id, result);
      stats.sms_sent++;
    } else {
      await recordFailure(db, notif.id, notif.retry_count, result.errorMessage);
      stats.failed++;
    }
  }
}

async function updateNotification(
  db: SupabaseClient,
  id: number,
  result: SendResult
): Promise<void> {
  const status = result.queued
    ? "queued"
    : result.success
    ? "sent"
    : "failed";
  await db
    .from("guardian_notifications")
    .update({
      status,
      sent_at: status === "sent" ? new Date().toISOString() : null,
      provider_message_id: result.providerMessageId ?? null,
      error_message: result.errorMessage ?? null,
    })
    .eq("id", id);
}

async function updateNotificationStatus(
  db: SupabaseClient,
  id: number,
  status: "sent" | "failed" | "skipped" | "queued",
  errorMessage?: string
): Promise<void> {
  await db
    .from("guardian_notifications")
    .update({
      status,
      sent_at: status === "sent" ? new Date().toISOString() : null,
      error_message: errorMessage ?? null,
    })
    .eq("id", id);
}

async function recordFailure(
  db: SupabaseClient,
  id: number,
  retryCount: number,
  errorMessage?: string
): Promise<void> {
  const nextCount = (retryCount ?? 0) + 1;
  const nextRetryAt = nextRetryAfter(nextCount - 1);

  if (nextCount >= MAX_RETRIES) {
    // Вичерпано всі спроби ретраю — позначити як постійно помилкове.
    await db
      .from("guardian_notifications")
      .update({
        status: "failed",
        retry_count: nextCount,
        next_retry_at: null,
        sent_at: null,
        error_message: errorMessage ?? null,
      })
      .eq("id", id);
  } else {
    await db
      .from("guardian_notifications")
      .update({
        status: "queued",
        retry_count: nextCount,
        next_retry_at: nextRetryAt.toISOString(),
        error_message: errorMessage ?? null,
      })
      .eq("id", id);
  }
}
