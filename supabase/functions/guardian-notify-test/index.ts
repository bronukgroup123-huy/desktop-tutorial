import { createServiceClient } from "../_shared/guardian/db.ts";
import { withErrorHandling, successResponse, Errors } from "../_shared/guardian/errors.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const db = createServiceClient();

  const { data: alerts } = await db
    .from("guardian_alerts")
    .select("*")
    .is("delivered_at", null)
    .lt("created_at", new Date(Date.now() - 5000).toISOString())
    .order("created_at", { ascending: true })
    .limit(10);

  if (!alerts || alerts.length === 0) {
    return successResponse({ message: "No pending alerts" });
  }

  const results = [];
  for (const alert of alerts) {
    const { data: session } = await db
      .from("guardian_sessions")
      .select("*")
      .eq("id", alert.session_id)
      .single();

    if (!session) continue;

    const { dispatchAlert } = await import("../_shared/guardian/notifications/dispatcher.ts");
    const result = await dispatchAlert(db, alert, session);
    results.push(result);
  }

  return successResponse({ processed: results.length, results });
}));
