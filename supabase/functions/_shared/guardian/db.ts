import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  GuardianSession,
  Guardian,
  SessionSettings,
} from "./types.ts";

export function createServiceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function getSessionById(
  db: SupabaseClient,
  sessionId: string
): Promise<GuardianSession | null> {
  const { data, error } = await db
    .from("guardian_sessions")
    .select("*")
    .eq("id", sessionId)
    .maybeSingle();
  if (error) throw error;
  return data as GuardianSession | null;
}

export async function getActiveSessionByUser(
  db: SupabaseClient,
  userId: string
): Promise<GuardianSession | null> {
  const { data, error } = await db
    .from("guardian_sessions")
    .select("*")
    .eq("user_id", userId)
    .neq("status", "closed")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as GuardianSession | null;
}

export async function getGuardianByTokenHash(
  db: SupabaseClient,
  tokenHash: string
): Promise<Guardian | null> {
  const { data, error } = await db
    .from("guardians")
    .select("*")
    .eq("token_hash", tokenHash)
    .is("revoked_at", null)
    .maybeSingle();
  if (error) throw error;
  return data as Guardian | null;
}

export async function getGuardiansBySession(
  db: SupabaseClient,
  sessionId: string
): Promise<Guardian[]> {
  const { data, error } = await db
    .from("guardians")
    .select("*")
    .eq("session_id", sessionId)
    .is("revoked_at", null)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []) as Guardian[];
}

export const DEFAULT_SESSION_SETTINGS: SessionSettings = {
  overdue_thresholds: { soft: 0, medium: 30, hard: 90 },
  stationary_threshold_min: 30,
  offline_threshold_min: 60,
  grace_period_min: 5,
  recovery_window_min: 30,
};

export function mergeSettings(
  partial?: Partial<SessionSettings>
): SessionSettings {
  return {
    ...DEFAULT_SESSION_SETTINGS,
    ...partial,
    overdue_thresholds: {
      ...DEFAULT_SESSION_SETTINGS.overdue_thresholds,
      ...(partial?.overdue_thresholds ?? {}),
    },
  };
}
