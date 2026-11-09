import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { AppError, Errors } from "./errors.ts";
import { validateGuardianToken } from "./token.ts";
import { getGuardianByTokenHash } from "./db.ts";
import { hashToken } from "./token.ts";
import type { Guardian, GuardianSession } from "./types.ts";

export interface MushroomPickerAuth {
  userId: string;
  db: SupabaseClient;
  /** Гість (ADR-001): анонімний користувач Supabase. */
  isAnonymous: boolean;
}

export async function requireMushroomPicker(
  req: Request
): Promise<MushroomPickerAuth> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    throw Errors.unauthorized("Missing Authorization header");
  }

  const token = authHeader.slice("Bearer ".length);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const authClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await authClient.auth.getUser(token);
  if (error || !data.user) {
    throw Errors.unauthorized("Invalid or expired auth token");
  }

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return { userId: data.user.id, db, isAnonymous: data.user.is_anonymous === true };
}

/** Гостю заборонено сесії Наглядача і SOS (ADR-001) → 403 registration_required. */
export function assertRegisteredPicker(auth: MushroomPickerAuth): void {
  if (auth.isAnonymous) {
    throw new AppError(
      "registration_required",
      "Ця дія доступна після реєстрації. Увійдіть через Google, Apple або телефон.",
      403,
    );
  }
}

/** requireMushroomPicker + заборона для гостя. */
export async function requireRegisteredPicker(req: Request): Promise<MushroomPickerAuth> {
  const auth = await requireMushroomPicker(req);
  assertRegisteredPicker(auth);
  return auth;
}

export interface GuardianAuth {
  guardian: Guardian;
  session: GuardianSession;
  db: SupabaseClient;
}

export async function requireGuardian(
  req: Request,
  tokenFromPath?: string
): Promise<GuardianAuth> {
  const token = tokenFromPath ?? req.headers.get("X-Guardian-Token");
  if (!token) {
    throw Errors.unauthorized("Missing guardian token");
  }

  const validation = await validateGuardianToken(token);
  if (!validation.valid || !validation.payload) {
    throw Errors.invalidToken(validation.error ?? "Invalid token");
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const tokenHash = await hashToken(token);
  const guardian = await getGuardianByTokenHash(db, tokenHash);
  if (!guardian) {
    throw Errors.invalidToken("Token revoked or not found");
  }

  if (guardian.id !== validation.payload.guardian_id) {
    throw Errors.invalidToken("Token mismatch");
  }

  const { data: session, error } = await db
    .from("guardian_sessions")
    .select("*")
    .eq("id", guardian.session_id)
    .single();

  if (error || !session) {
    throw Errors.notFound("Session not found");
  }

  await db
    .from("guardians")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("id", guardian.id);

  return { guardian, session: session as GuardianSession, db };
}
