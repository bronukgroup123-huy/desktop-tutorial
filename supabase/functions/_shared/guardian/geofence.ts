// ============================================================================
// Geofence / Exit Detection (Audit G4 fix)
// 3-state RPC + debounce + was_offline skip + unknown fallback
// ============================================================================
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface ExitDetectionResult {
  isOutsideForest: boolean;
  isConfirmedExit: boolean;
  consecutiveOutsideCount: number;
  totalChecked: number;
  hadUnknown: boolean;
}

const MIN_CONSECUTIVE = 3; // було 2 — збільшено для уникнення false-positive

export async function detectForestExit(
  db: SupabaseClient,
  sessionId: string,
): Promise<ExitDetectionResult> {
  const { data: points, error } = await db
    .from("guardian_track")
    .select("coords, recorded_at, was_offline")
    .eq("session_id", sessionId)
    .order("recorded_at", { ascending: false })
    .limit(10); // було 5

  if (error || !points || points.length === 0) {
    return {
      isOutsideForest: false,
      isConfirmedExit: false,
      consecutiveOutsideCount: 0,
      totalChecked: 0,
      hadUnknown: false,
    };
  }

  let consecutiveOutside = 0;
  let hadUnknown = false;
  let processed = 0;

  for (const point of points) {
    // Пропускаємо офлайн-точки (можуть бути неточні / зі стрімкою쪽у)
    if (point.was_offline) continue;

    const { data: state, error: rpcError } = await db.rpc(
      "check_forest_position",
      {
        p_lat: point.coords.coordinates[1],
        p_lng: point.coords.coordinates[0],
      },
    );

    processed++;

    if (rpcError) {
      console.error("[geofence] RPC error:", rpcError);
      break;
    }

    if (state === "unknown") {
      hadUnknown = true;
      continue; // не рахувати як outside і не скидати counter
    }

    if (state === "outside") {
      consecutiveOutside++;
      if (consecutiveOutside >= MIN_CONSECUTIVE) break;
    } else {
      // inside — скинути counter і зупинити ( точка всередині лісу)
      consecutiveOutside = 0;
      break;
    }
  }

  return {
    isOutsideForest: consecutiveOutside > 0,
    isConfirmedExit: consecutiveOutside >= MIN_CONSECUTIVE,
    consecutiveOutsideCount: consecutiveOutside,
    totalChecked: processed,
    hadUnknown,
  };
}
