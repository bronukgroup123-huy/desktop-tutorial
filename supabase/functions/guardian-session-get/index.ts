import {
  requireGuardian,
  Errors,
  successResponse,
  withErrorHandling,
} from "../_shared/guardian/index.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "GET") throw Errors.notFound("Method not allowed");

  const url = new URL(req.url);
  const token = url.pathname.split("/").pop();
  if (!token) throw Errors.validation("Missing token in path");

  const { guardian, session, db } = await requireGuardian(req, token);

  const { data: guardians } = await db
    .from("guardians")
    .select("id, name, is_emergency, last_seen_at, revoked_at")
    .eq("session_id", session.id)
    .is("revoked_at", null);

  const now = Date.now();
  const lastKnownAt = session.last_known_at
    ? new Date(session.last_known_at).getTime()
    : null;
  const secondsSinceLastKnown = lastKnownAt
    ? Math.floor((now - lastKnownAt) / 1000)
    : null;

  const minutesToReturn = Math.floor(
    (new Date(session.expected_return).getTime() - now) / 60000
  );

  return successResponse({
    session: {
      id: session.id,
      status: session.status,
      expected_return: session.expected_return,
      original_return: session.original_return,
      started_at: session.started_at,
      closed_at: session.closed_at,
      recoverable_until: session.recoverable_until,
      last_known_coords: session.last_known_coords,
      last_known_at: session.last_known_at,
      last_battery_pct: session.last_battery_pct,
      last_signal_strength: session.last_signal_strength,
      exit_detected_at: session.exit_detected_at,
      sos_activated_at: session.sos_activated_at,
      overdue_level: session.overdue_level,
      previous_status: session.previous_status,
      settings: session.settings,
    },
    derived: {
      seconds_since_last_known: secondsSinceLastKnown,
      minutes_to_return: minutesToReturn,
    },
    guardians,
    current_guardian_id: guardian.id,
  });
}));
