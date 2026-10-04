import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { GuardianSession } from "./types.ts";
import { Errors } from "./errors.ts";
import { generateGuardianToken, hashToken } from "./token.ts";

const RESCUE_TOKEN_TTL_HOURS = 24;

export interface CreateRescueResult {
  rescue_id: string;
  token: string;
  url: string;
  expires_at: string;
}

export async function createRescueRequest(
  db: SupabaseClient,
  session: GuardianSession,
  userId: string,
  target: "101" | "police" | "family" | "other",
  notes?: string
): Promise<CreateRescueResult> {
  if (session.status === "closed") {
    throw Errors.conflict("Cannot create rescue request for closed session");
  }

  const { data: existing } = await db
    .from("guardian_rescue_requests")
    .select("id, expires_at")
    .eq("session_id", session.id)
    .is("resolved_at", null)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing) {
    throw Errors.conflict(
      "Активний rescue-запит уже існує для цієї сесії",
      { rescue_id: existing.id, expires_at: existing.expires_at }
    );
  }

  const tokenData = await generateRescueToken(session.id);
  const expiresAt = new Date(
    Date.now() + RESCUE_TOKEN_TTL_HOURS * 60 * 60 * 1000
  ).toISOString();

  const payload = {
    picker_coords: extractCoords(session.last_known_coords),
    battery_pct: session.last_battery_pct,
    signal_strength: session.last_signal_strength,
    expected_return: session.expected_return,
    last_known_at: session.last_known_at,
    status_at_creation: session.status,
    sos_activated_at: session.sos_activated_at,
  };

  const { data: rescue, error } = await db
    .from("guardian_rescue_requests")
    .insert({
      session_id: session.id,
      created_by: userId,
      token_hash: tokenData.tokenHash,
      token_prefix: tokenData.tokenPrefix,
      target,
      notes: notes ?? null,
      payload,
      expires_at: expiresAt,
    })
    .select("id")
    .single();

  if (error || !rescue) {
    throw Errors.internal(`Failed to create rescue request: ${error?.message}`);
  }

  const url = buildRescueUrl(tokenData.token);

  return {
    rescue_id: rescue.id,
    token: tokenData.token,
    url,
    expires_at: expiresAt,
  };
}

export interface RescueView {
  rescue_id: string;
  session: {
    id: string;
    status: string;
    started_at: string;
    expected_return: string;
    last_known_coords: { lat: number; lng: number } | null;
    last_known_at: string | null;
    sos_activated_at: string | null;
  };
  picker: {
    name: string;
  };
  target: string;
  notes: string | null;
  payload: Record<string, unknown>;
  created_at: string;
  expires_at: string;
  resolved_at: string | null;
}

export async function getRescueByToken(
  db: SupabaseClient,
  token: string
): Promise<RescueView | null> {
  const tokenHash = await hashToken(token);

  const { data, error } = await db
    .from("guardian_rescue_requests")
    .select(`
      id, target, notes, payload, created_at, expires_at, resolved_at, viewed_count,
      session:guardian_sessions!inner(
        id, status, started_at, expected_return,
        last_known_coords, last_known_at, sos_activated_at,
        user:users!inner(name)
      )
    `)
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (error || !data) return null;

  if (new Date(data.expires_at) < new Date()) {
    return null;
  }

  await db
    .from("guardian_rescue_requests")
    .update({
      viewed_count: (data as any).viewed_count + 1,
      last_viewed_at: new Date().toISOString(),
    })
    .eq("id", data.id);

  const session = (data as any).session;
  const pickerName = session.user?.name ?? "Грибник";

  return {
    rescue_id: data.id,
    session: {
      id: session.id,
      status: session.status,
      started_at: session.started_at,
      expected_return: session.expected_return,
      last_known_coords: extractCoords(session.last_known_coords),
      last_known_at: session.last_known_at,
      sos_activated_at: session.sos_activated_at,
    },
    picker: { name: pickerName },
    target: data.target,
    notes: data.notes,
    payload: data.payload as Record<string, unknown>,
    created_at: data.created_at,
    expires_at: data.expires_at,
    resolved_at: data.resolved_at,
  };
}

export async function resolveRescue(
  db: SupabaseClient,
  rescueId: string,
  userId: string,
  note?: string
): Promise<void> {
  const { error } = await db
    .from("guardian_rescue_requests")
    .update({
      resolved_at: new Date().toISOString(),
      resolved_note: note ?? null,
    })
    .eq("id", rescueId)
    .eq("created_by", userId);

  if (error) {
    throw Errors.internal(`Failed to resolve rescue: ${error.message}`);
  }
}

interface RescueTokenData {
  token: string;
  tokenHash: string;
  tokenPrefix: string;
}

async function generateRescueToken(sessionId: string): Promise<RescueTokenData> {
  const generated = await generateGuardianToken(sessionId, "rescue");
  return {
    token: generated.token,
    tokenHash: generated.tokenHash,
    tokenPrefix: generated.tokenPrefix,
  };
}

function buildRescueUrl(token: string): string {
  const base =
    Deno.env.get("GUARDIAN_BASE_URL") ??
    "https://guardian.mushroomradar.com.ua";
  return `${base}/rescue/${token}`;
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
