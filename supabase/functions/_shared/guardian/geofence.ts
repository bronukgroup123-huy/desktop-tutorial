import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface ExitDetectionResult {
  isOutsideForest: boolean;
  isConfirmedExit: boolean;
  consecutiveOutsideCount: number;
}

export async function detectForestExit(
  db: SupabaseClient,
  sessionId: string
): Promise<ExitDetectionResult> {
  const { data: points, error } = await db
    .from("guardian_track")
    .select("coords")
    .eq("session_id", sessionId)
    .order("recorded_at", { ascending: false })
    .limit(5);

  if (error || !points || points.length === 0) {
    return {
      isOutsideForest: false,
      isConfirmedExit: false,
      consecutiveOutsideCount: 0,
    };
  }

  let consecutiveOutside = 0;
  for (const point of points) {
    const { data, error: rpcError } = await db.rpc("is_point_in_forest", {
      p_lat: point.coords.coordinates[1],
      p_lng: point.coords.coordinates[0],
    });

    if (rpcError) {
      console.error("[geofence] RPC error:", rpcError);
      break;
    }

    if (data === false) {
      consecutiveOutside++;
    } else {
      break;
    }
  }

  const isOutsideForest = consecutiveOutside > 0;
  const isConfirmedExit = consecutiveOutside >= 2;

  return {
    isOutsideForest,
    isConfirmedExit,
    consecutiveOutsideCount: consecutiveOutside,
  };
}
