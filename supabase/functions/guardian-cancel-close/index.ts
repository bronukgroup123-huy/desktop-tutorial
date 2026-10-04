import {
  requireMushroomPicker,
  Errors,
  successResponse,
  withErrorHandling,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";
import type { SessionStatus } from "../_shared/guardian/types.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  if (session.status !== "closing") {
    throw Errors.invalidTransition(session.status, "cancel-close");
  }

  const targetStatus: SessionStatus =
    (session.previous_status as SessionStatus | null) ?? "active";

  const { data: updated, error } = await db
    .from("guardian_sessions")
    .update({
      status: targetStatus,
      closing_started_at: null,
      previous_status: null,
    })
    .eq("id", session.id)
    .select("*")
    .single();

  if (error) throw Errors.internal(error.message);

  await db.from("guardian_alerts").insert({
    session_id: session.id,
    alert_type: "recovered",
    payload: { action: "cancel_close", target_status: targetStatus },
  });

  return successResponse({ session: updated });
}));
