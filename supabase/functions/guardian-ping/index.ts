import {
  requireMushroomPicker,
  parseBody,
  PingSchema,
  Errors,
  successResponse,
  withErrorHandling,
  getActiveSessionByUser,
  transitionSession,
} from "../_shared/guardian/index.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "POST") throw Errors.notFound("Method not allowed");

  const { userId, db } = await requireMushroomPicker(req);
  const input = await parseBody(req, PingSchema);

  const session = await getActiveSessionByUser(db, userId);
  if (!session) throw Errors.notFound("No active session");

  let updatedSession = session;
  if (session.status === "pending") {
    updatedSession = await transitionSession(db, session, "active");
  }

  if (["stale", "offline", "overdue_soft", "overdue_medium"].includes(session.status)) {
    updatedSession = await transitionSession(db, session, "active", {
      extraUpdates: { overdue_level: null },
    });
  }

  const recordedAt = input.recorded_at
    ? new Date(input.recorded_at)
    : new Date();

  const { error: trackError } = await db
    .from("guardian_track")
    .insert({
      session_id: session.id,
      coords: `POINT(${input.lng} ${input.lat})`,
      recorded_at: recordedAt.toISOString(),
      battery_pct: input.battery_pct ?? null,
      signal_strength: input.signal_strength ?? null,
      speed_kmh: input.speed_kmh ?? null,
      was_offline: input.was_offline,
    });

  if (trackError) throw Errors.internal(trackError.message);

  const { error: sessionError } = await db
    .from("guardian_sessions")
    .update({
      last_known_coords: `POINT(${input.lng} ${input.lat})`,
      last_known_at: recordedAt.toISOString(),
      last_battery_pct: input.battery_pct ?? null,
      last_signal_strength: input.signal_strength ?? null,
    })
    .eq("id", session.id);

  if (sessionError) throw Errors.internal(sessionError.message);

  return successResponse({
    session_id: session.id,
    status: updatedSession.status,
    recorded_at: recordedAt.toISOString(),
  }, 201);
}));
