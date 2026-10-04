import {
  requireMushroomPicker,
  Errors,
  successResponse,
  withErrorHandling,
} from "../_shared/guardian/index.ts";
import type { GuardianSession } from "../_shared/guardian/types.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);

  const { data: session, error: fetchError } = await db
    .from("guardian_sessions")
    .select("*")
    .eq("user_id", userId)
    .eq("status", "closed")
    .order("closed_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (fetchError) throw Errors.internal(fetchError.message);
  if (!session) throw Errors.notFound("No closed session to recover");

  const s = session as GuardianSession;
  if (!s.recoverable_until) {
    throw Errors.conflict("Session is not recoverable");
  }

  if (new Date(s.recoverable_until) < new Date()) {
    throw Errors.conflict("Recovery window has expired", {
      recoverable_until: s.recoverable_until,
    });
  }

  const { data: updated, error } = await db
    .from("guardian_sessions")
    .update({
      status: "active",
      closed_at: null,
      recoverable_until: null,
    })
    .eq("id", s.id)
    .select("*")
    .single();

  if (error) throw Errors.internal(error.message);

  await db.from("guardian_alerts").insert({
    session_id: s.id,
    alert_type: "recovered",
    payload: { action: "user_recovered" },
  });

  return successResponse({ session: updated });
}));
