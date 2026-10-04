import {
  requireGuardian,
  withErrorHandling,
  Errors,
} from "../_shared/guardian/index.ts";
import { buildGpx } from "../_shared/guardian/gpx.ts";
import type { GuardianTrackPoint } from "../_shared/guardian/types.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "GET") throw Errors.notFound("Method not allowed");

  const url = new URL(req.url);
  const token = url.pathname.split("/").pop();
  if (!token) throw Errors.validation("Missing token in path");

  const { session, db } = await requireGuardian(req, token);

  const { data: points, error } = await db
    .from("guardian_track")
    .select("coords, recorded_at, speed_kmh, battery_pct, signal_strength")
    .eq("session_id", session.id)
    .order("recorded_at", { ascending: true });

  if (error) throw Errors.internal(error.message);

  let sosWaypoint = null;
  if (session.sos_activated_at && session.last_known_coords) {
    sosWaypoint = {
      lat: (session.last_known_coords as any).coordinates?.[1] ?? 0,
      lng: (session.last_known_coords as any).coordinates?.[0] ?? 0,
      time: session.sos_activated_at,
    };
  }

  let exitWaypoint = null;
  if (session.exit_detected_at && session.last_known_coords) {
    exitWaypoint = {
      lat: (session.last_known_coords as any).coordinates?.[1] ?? 0,
      lng: (session.last_known_coords as any).coordinates?.[0] ?? 0,
      time: session.exit_detected_at,
    };
  }

  const gpx = buildGpx(
    session,
    (points ?? []) as GuardianTrackPoint[],
    { sosWaypoint, exitWaypoint }
  );

  return new Response(gpx, {
    status: 200,
    headers: {
      "Content-Type": "application/gpx+xml; charset=utf-8",
      "Content-Disposition": `attachment; filename="session-${session.id}.gpx"`,
    },
  });
}));
