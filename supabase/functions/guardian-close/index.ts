import {
  requireMushroomPicker,
  Errors,
  successResponse,
  withErrorHandling,
  getActiveSessionByUser,
  transitionSession,
} from "../_shared/guardian/index.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  if (session.status === "closing") {
    return successResponse({ session, already_closing: true });
  }
  if (session.status === "closed") {
    throw Errors.invalidTransition("closed", "closing");
  }

  const now = new Date();
  const gracePeriodMin = session.settings.grace_period_min ?? 5;

  const updated = await transitionSession(db, session, "closing", {
    savePreviousStatus: true,
    extraUpdates: {
      closing_started_at: now.toISOString(),
    },
  });

  await db.from("guardian_alerts").insert({
    session_id: session.id,
    alert_type: "closing",
    payload: {
      grace_period_min: gracePeriodMin,
      auto_close_at: new Date(now.getTime() + gracePeriodMin * 60000).toISOString(),
    },
  });

  return successResponse({
    session: updated,
    grace_period_min: gracePeriodMin,
  });
}));
