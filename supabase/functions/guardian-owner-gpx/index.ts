import {
  requireMushroomPicker,
  withErrorHandling,
  Errors,
  getActiveSessionByUser,
} from "../_shared/guardian/index.ts";
import { buildGpx } from "../_shared/guardian/gpx.ts";
import type { GuardianTrackPoint } from "../_shared/guardian/types.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "GET") throw Errors.notFound("Method not allowed");

  const url = new URL(req.url);
  const sessionIdParam = url.searchParams.get("session_id");

  const { userId, db } = await requireMushroomPicker(req);

  let session;
  if (sessionIdParam) {
    const { data } = await db
      .from("guardian_sessions")
      .select("*")
      .eq("id", sessionIdParam)
      .eq("user_id", userId)
      .maybeSingle();
    session = data;
  } else {
    session = await getActiveSessionByUser(db, userId);
  }

  if (!session) throw Errors.notFound("Session not found");

  const { data: points, error } = await db
    .from("guardian_track")
    .select("coords, recorded_at, speed_kmh, battery_pct, signal_strength")
    .eq("session_id", session.id)
    .order("recorded_at", { ascending: true });

  if (error) throw Errors.internal(error.message);

  const gpx = buildGpx(session, (points ?? []) as GuardianTrackPoint[]);

  return new Response(gpx, {
    status: 200,
    headers: {
      "Content-Type": "application/gpx+xml; charset=utf-8",
      "Content-Disposition": `attachment; filename="my-session-${session.id}.gpx"`,
    },
  });
}));
