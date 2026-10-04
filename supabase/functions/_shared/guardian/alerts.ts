import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { AlertType } from "./types.ts";

export async function createAlertOnce(
  db: SupabaseClient,
  sessionId: string,
  alertType: AlertType,
  payload: Record<string, unknown> = {}
): Promise<boolean> {
  const { data: existing } = await db
    .from("guardian_alerts")
    .select("id")
    .eq("session_id", sessionId)
    .eq("alert_type", alertType)
    .limit(1)
    .maybeSingle();

  if (existing) return false;

  const { error } = await db.from("guardian_alerts").insert({
    session_id: sessionId,
    alert_type: alertType,
    payload,
  });

  if (error) {
    console.error(`[alerts] Failed to create alert ${alertType}:`, error);
    return false;
  }

  return true;
}
