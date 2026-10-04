import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { THRESHOLDS } from "./thresholds.ts";

export interface MovementState {
  hasFreshData: boolean;
  isMoving: boolean;
  avgSpeedKmh: number;
  secondsSinceLastPing: number | null;
  pointsInWindow: number;
}

export async function analyzeMovement(
  db: SupabaseClient,
  sessionId: string,
  lastKnownAt: string | null
): Promise<MovementState> {
  const now = Date.now();

  if (!lastKnownAt) {
    return {
      hasFreshData: false,
      isMoving: false,
      avgSpeedKmh: 0,
      secondsSinceLastPing: null,
      pointsInWindow: 0,
    };
  }

  const lastKnownMs = new Date(lastKnownAt).getTime();
  const secondsSinceLastPing = Math.floor((now - lastKnownMs) / 1000);

  const hasFreshData = secondsSinceLastPing < THRESHOLDS.STALE_MIN * 60;

  if (!hasFreshData) {
    return {
      hasFreshData: false,
      isMoving: false,
      avgSpeedKmh: 0,
      secondsSinceLastPing,
      pointsInWindow: 0,
    };
  }

  const windowStart = new Date(
    now - THRESHOLDS.MOVEMENT_WINDOW_MIN * 60 * 1000
  ).toISOString();

  const { data: points, error } = await db
    .from("guardian_track")
    .select("speed_kmh, recorded_at")
    .eq("session_id", sessionId)
    .gte("recorded_at", windowStart)
    .order("recorded_at", { ascending: true });

  if (error || !points || points.length === 0) {
    return {
      hasFreshData: true,
      isMoving: false,
      avgSpeedKmh: 0,
      secondsSinceLastPing,
      pointsInWindow: 0,
    };
  }

  const speeds = points
    .map((p) => p.speed_kmh)
    .filter((s): s is number => s !== null);

  const avgSpeedKmh =
    speeds.length > 0
      ? speeds.reduce((a, b) => a + b, 0) / speeds.length
      : 0;

  const isMoving = avgSpeedKmh >= THRESHOLDS.MOVEMENT_SPEED_KMH;

  return {
    hasFreshData: true,
    isMoving,
    avgSpeedKmh,
    secondsSinceLastPing,
    pointsInWindow: points.length,
  };
}
