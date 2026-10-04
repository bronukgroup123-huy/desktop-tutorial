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

  if (session.status === "exiting") {
    return successResponse({ session, already_exiting: true });
  }

  const updated = await transitionSession(db, session, "exiting", {
    extraUpdates: { overdue_level: null },
  });

  await db.from("guardian_alerts").insert({
    session_id: session.id,
    alert_type: "exit",
    payload: { action: "user_marked_exiting" },
  });

  return successResponse({ session: updated });
}));
