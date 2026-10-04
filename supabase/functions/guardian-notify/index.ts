import { createServiceClient } from "../_shared/guardian/db.ts";
import { withErrorHandling, successResponse, Errors } from "../_shared/guardian/errors.ts";
import { dispatchAlert } from "../_shared/guardian/notifications/dispatcher.ts";
import type { GuardianAlert, GuardianSession } from "../_shared/guardian/types.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const body = await req.json().catch(() => ({}));
  const alertId = body?.alert_id;

  const db = createServiceClient();

  let alerts: GuardianAlert[];

  if (alertId) {
    const { data, error } = await db
      .from("guardian_alerts")
      .select("*")
      .eq("id", alertId)
      .is("delivered_at", null)
      .maybeSingle();

    if (error) throw Errors.internal(error.message);
    if (!data) return successResponse({ skipped: true, reason: "alert not found or already delivered" });
    alerts = [data as GuardianAlert];
  } else {
    const { data, error } = await db
      .from("guardian_alerts")
      .select("*")
      .is("delivered_at", null)
      .lt("created_at", new Date(Date.now() - 5000).toISOString())
      .order("created_at", { ascending: true })
      .limit(50);

    if (error) throw Errors.internal(error.message);
    alerts = (data ?? []) as GuardianAlert[];
  }

  const results = [];
  for (const alert of alerts) {
    const { data: session, error: sessionError } = await db
      .from("guardian_sessions")
      .select("*")
      .eq("id", alert.session_id)
      .single();

    if (sessionError || !session) {
      console.error(`[notify] Session not found for alert ${alert.id}`);
      continue;
    }

    try {
      const result = await dispatchAlert(db, alert, session as GuardianSession);
      results.push(result);
    } catch (err) {
      console.error(`[notify] Error dispatching alert ${alert.id}:`, err);
      results.push({ alert_id: alert.id, error: String(err) });
    }
  }

  return successResponse({ processed: results.length, results });
}));
