import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { GuardianSession, SessionStatus } from "./types.ts";
import { Errors } from "./errors.ts";

export interface SosResult {
  session: GuardianSession;
  previous_status: SessionStatus;
  alert_id: number;
}

export async function activateSos(
  db: SupabaseClient,
  session: GuardianSession
): Promise<SosResult> {
  if (session.status === "closing" || session.status === "closed") {
    throw Errors.invalidTransition(session.status, "sos");
  }

  if (session.status === "sos") {
    const { data: existingAlert } = await db
      .from("guardian_alerts")
      .select("id")
      .eq("session_id", session.id)
      .eq("alert_type", "sos")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingAlert) {
      return {
        session,
        previous_status: "sos",
        alert_id: existingAlert.id,
      };
    }
  }

  const previousStatus = session.status;
  const now = new Date().toISOString();

  const { data: updated, error } = await db
    .from("guardian_sessions")
    .update({
      status: "sos",
      sos_activated_at: now,
      previous_status: previousStatus,
    })
    .eq("id", session.id)
    .eq("status", previousStatus)
    .select("*")
    .single();

  if (error || !updated) {
    throw Errors.internal(`Failed to activate SOS: ${error?.message}`);
  }

  const { data: alert, error: alertError } = await db
    .from("guardian_alerts")
    .insert({
      session_id: session.id,
      alert_type: "sos",
      payload: {
        activated_at: now,
        previous_status: previousStatus,
        coords: extractCoords(session.last_known_coords),
        battery_pct: session.last_battery_pct,
      },
    })
    .select("id")
    .single();

  if (alertError || !alert) {
    throw Errors.internal(`Failed to create SOS alert: ${alertError?.message}`);
  }

  return {
    session: updated as GuardianSession,
    previous_status: previousStatus,
    alert_id: alert.id,
  };
}

export async function cancelSos(
  db: SupabaseClient,
  session: GuardianSession
): Promise<{ session: GuardianSession; alert_id: number }> {
  if (session.status !== "sos") {
    throw Errors.invalidTransition(session.status, "active");
  }

  const targetStatus: SessionStatus =
    (session.previous_status as SessionStatus | null) ?? "active";

  const safeTarget: SessionStatus =
    targetStatus === "closing" || targetStatus === "closed"
      ? "active"
      : targetStatus;

  const { data: updated, error } = await db
    .from("guardian_sessions")
    .update({
      status: safeTarget,
      previous_status: null,
    })
    .eq("id", session.id)
    .eq("status", "sos")
    .select("*")
    .single();

  if (error || !updated) {
    throw Errors.internal(`Failed to cancel SOS: ${error?.message}`);
  }

  const { data: alert, error: alertError } = await db
    .from("guardian_alerts")
    .insert({
      session_id: session.id,
      alert_type: "recovered",
      payload: {
        action: "sos_cancelled",
        target_status: safeTarget,
      },
    })
    .select("id")
    .single();

  if (alertError || !alert) {
    throw Errors.internal(`Failed to create cancel-SOS alert: ${alertError?.message}`);
  }

  return {
    session: updated as GuardianSession,
    alert_id: alert.id,
  };
}

function extractCoords(
  coords: unknown
): { lat: number; lng: number } | null {
  if (!coords || typeof coords !== "object") return null;
  const c = coords as Record<string, unknown>;
  if (Array.isArray(c.coordinates) && c.coordinates.length === 2) {
    return {
      lng: c.coordinates[0] as number,
      lat: c.coordinates[1] as number,
    };
  }
  if (typeof c.lat === "number" && typeof c.lng === "number") {
    return { lat: c.lat, lng: c.lng };
  }
  return null;
}
