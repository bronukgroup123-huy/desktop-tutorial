import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const ANONYMIZED_USER_ID = "00000000-0000-0000-0000-000000000000";

class AppError extends Error {
  constructor(public status: number, public code: string, public message: string) {
    super(message);
    this.name = "AppError";
  }
}

function cors(req: Request): Record<string, string> {
  return { ...corsHeaders, "Vary": "Origin" };
}

function jsonResponse(data: unknown, status: number, req: Request): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors(req), "Content-Type": "application/json" },
  });
}

function errorResponse(err: unknown, req: Request): Response {
  if (err instanceof AppError) {
    return jsonResponse({ error: err.code, message: err.message }, err.status, req);
  }
  console.error("[Unhandled]", err);
  return jsonResponse(
    { error: "internal_error", message: "Internal server error" },
    500,
    req
  );
}

function withErrorHandling(handler: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    try {
      return await handler(req);
    } catch (err) {
      return errorResponse(err, req);
    }
  };
}

async function getUserId(req: Request): Promise<string> {
  const header = req.headers.get("Authorization");
  if (!header || !header.startsWith("Bearer ")) {
    throw new AppError(401, "unauthorized", "Missing Authorization header");
  }
  const jwt = header.slice("Bearer ".length);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new AppError(500, "internal_error", "Server misconfigured");
  }
  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await authClient.auth.getUser(jwt);
  if (error || !data?.user) {
    throw new AppError(401, "unauthorized", "Invalid or expired auth token");
  }
  return data.user.id;
}

function serviceDb(): SupabaseClient {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    throw new AppError(500, "internal_error", "Server misconfigured");
  }
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function anonymizePicks(db: SupabaseClient, userId: string): Promise<void> {
  const { error } = await db
    .from("mushroom_picks")
    .update({ user_id: ANONYMIZED_USER_ID })
    .eq("user_id", userId);
  if (error) {
    console.error("anonymize picks failed:", error);
    throw new AppError(500, "internal_error", "Failed to anonymize public picks");
  }
}

async function deletePrivateData(db: SupabaseClient, userId: string): Promise<void> {
  try {
    await db.from("guardian_sessions").delete().eq("user_id", userId);
  } catch {
    // таблиця може відсутня в схемі
  }
  try {
    await db.from("trips").delete().eq("user_id", userId);
  } catch {
    // таблиця може відсутня в схемі
  }
}

async function deleteProfile(db: SupabaseClient, userId: string): Promise<void> {
  const { error } = await db.from("users").delete().eq("id", userId);
  if (error) {
    console.error("delete profile failed:", error);
    throw new AppError(500, "internal_error", "Failed to delete profile");
  }
}

async function handleDelete(req: Request, userId: string): Promise<Response> {
  const db = serviceDb();

  await anonymizePicks(db, userId);
  await deletePrivateData(db, userId);
  await deleteProfile(db, userId);

  const { error } = await db.auth.admin.deleteUser(userId);
  if (error) {
    console.error("deleteUser failed:", error);
    throw new AppError(500, "internal_error", "Failed to delete auth user");
  }

  return jsonResponse({ ok: true, message: "Account deleted" }, 200, req);
}

async function handleGet(req: Request, userId: string): Promise<Response> {
  const db = serviceDb();

  const [usersRes, picksRes] = await Promise.all([
    db.from("users").select("*").eq("id", userId).maybeSingle(),
    db.from("mushroom_picks").select("*").eq("user_id", userId),
  ]);

  let trips = null;
  try {
    const { data } = await db.from("trips").select("*").eq("user_id", userId);
    trips = data;
  } catch {
    // таблиця може відсутня в схемі
  }

  const exportData = {
    exported_at: new Date().toISOString(),
    user: usersRes.data ?? null,
    mushroom_picks: picksRes.data ?? [],
    trips: trips ?? [],
  };

  return new Response(JSON.stringify(exportData), {
    status: 200,
    headers: {
      ...cors(req),
      "Content-Type": "application/json",
      "Content-Disposition": 'attachment; filename="my_data.json"',
    },
  });
}

Deno.serve(
  withErrorHandling(async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors(req) });
    }

    const userId = await getUserId(req);

    if (req.method === "DELETE") {
      return handleDelete(req, userId);
    }
    if (req.method === "GET") {
      return handleGet(req, userId);
    }

    return jsonResponse({ error: "method_not_allowed" }, 405, req);
  })
);
