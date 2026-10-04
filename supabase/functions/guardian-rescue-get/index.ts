import {
  createServiceClient,
  successResponse,
  withErrorHandling,
  Errors,
} from "../_shared/guardian/index.ts";
import { getRescueByToken } from "../_shared/guardian/rescue.ts";
import { buildGpx } from "../_shared/guardian/gpx.ts";
import type { GuardianTrackPoint } from "../_shared/guardian/types.ts";

Deno.serve(withErrorHandling(async (req) => {
  if (req.method !== "GET") throw Errors.notFound("Method not allowed");

  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const token = parts[parts.length - 2] === "gpx" ? parts[parts.length - 3] : parts[parts.length - 1];
  const isGpx = parts[parts.length - 1] === "gpx";

  if (!token) throw Errors.validation("Missing token in path");

  const db = createServiceClient();
  const rescue = await getRescueByToken(db, token);

  if (!rescue) {
    throw Errors.notFound("Rescue request not found or expired");
  }

  if (isGpx) {
    const { data: session } = await db
      .from("guardian_sessions")
      .select("*")
      .eq("id", rescue.session.id)
      .single();

    if (!session) throw Errors.notFound("Session not found");

    const { data: points } = await db
      .from("guardian_track")
      .select("coords, recorded_at, speed_kmh, battery_pct, signal_strength")
      .eq("session_id", session.id)
      .order("recorded_at", { ascending: true });

    let sosWaypoint = null;
    if (session.sos_activated_at && session.last_known_coords) {
      sosWaypoint = {
        lat: (session.last_known_coords as any).coordinates?.[1] ?? 0,
        lng: (session.last_known_coords as any).coordinates?.[0] ?? 0,
        time: session.sos_activated_at,
      };
    }

    const gpx = buildGpx(
      session,
      (points ?? []) as GuardianTrackPoint[],
      { name: `Rescue — ${rescue.picker.name}`, sosWaypoint }
    );

    return new Response(gpx, {
      status: 200,
      headers: {
        "Content-Type": "application/gpx+xml; charset=utf-8",
        "Content-Disposition": `attachment; filename="rescue-${rescue.rescue_id}.gpx"`,
      },
    });
  }

  return successResponse({
    ...rescue,
    gpx_url: `/guardian-rescue-get/${token}/gpx`,
  });
}));
