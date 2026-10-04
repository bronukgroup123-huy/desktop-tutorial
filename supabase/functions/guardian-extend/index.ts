import {
  requireMushroomPicker,
  parseBody,
  ExtendSchema,
  Errors,
  successResponse,
  withErrorHandling,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const { minutes } = await parseBody(req, ExtendSchema);

  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  if (session.status === "closing" || session.status === "closed") {
    throw Errors.invalidTransition(session.status, "extend");
  }

  const newReturn = new Date(
    new Date(session.expected_return).getTime() + minutes * 60000
  );

  const updates: Record<string, unknown> = {
    expected_return: newReturn.toISOString(),
  };
  if (session.status.startsWith("overdue")) {
    updates.status = "active";
    updates.overdue_level = null;
  }

  const { data: updated, error } = await db
    .from("guardian_sessions")
    .update(updates)
    .eq("id", session.id)
    .select("*")
    .single();

  if (error) throw Errors.internal(error.message);

  await db.from("guardian_alerts").insert({
    session_id: session.id,
    alert_type: "overdue_soft",
    payload: { action: "extend", minutes, new_return: newReturn.toISOString() },
  });

  return successResponse({ session: updated });
}));
