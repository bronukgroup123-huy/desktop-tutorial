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

  const { session, db } = await requireGuardian(req, token);

  const sinceParam = url.searchParams.get("since");
  const limit = Math.min(
    parseInt(url.searchParams.get("limit") ?? "5000", 10),
    10000
  );

  let query = db
    .from("guardian_track")
    .select("coords, recorded_at, battery_pct, signal_strength, speed_kmh")
    .eq("session_id", session.id)
    .order("recorded_at", { ascending: true })
    .limit(limit);

  if (sinceParam) {
    query = query.gte("recorded_at", sinceParam);
  }

  const { data: points, error } = await query;
  if (error) throw Errors.internal(error.message);

  return successResponse({
    session_id: session.id,
    points: points ?? [],
  });
}));
