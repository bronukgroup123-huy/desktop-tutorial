// ============================================================================
// Edge Function: guardian-demo-create (group 8.8)
// POST / — публічне демо Наглядача БЕЗ реєстрації.
//
// Пайплайн: inline cleanup (2h TTL) → count-check (макс 50 активних)
// → insert demo-session → insert guardian (PENDING) → generateGuardianToken
// → update hash → 201 { data: { url, session_id } }.
//
// TODO(V2): міграція на guardian.mushroomradar.com.ua
// після налаштування DNS + окремого Vercel-проєкту.
// Зараз buildGuardianUrl використовує GUARDIAN_BASE_URL з CI-secret
// (Vercel subdomain) — консистентно зі звичайними Guardian-посиланнями.
// ============================================================================

import { corsHeaders } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  DEMO_USER_ID,
  DEMO_MAX_ACTIVE,
  DEMO_TTL_HOURS,
  buildDemoSessionInsert,
  buildDemoGuardianInsert,
  demoCutoffIso,
  validateDemoLimit,
} from "../_shared/forecast/demo-guardian.ts";
import {
  generateGuardianToken,
  buildGuardianUrl,
} from "../_shared/guardian/token.ts";

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  // 1. CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return json({ error: "internal_error" }, 500);
  }
  const db = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    // 2. Inline cleanup: видалити demo-сесії старші 2h (best-effort)
    const { error: cleanupErr } = await db
      .from("guardian_sessions")
      .delete()
      .eq("settings->>demo", "true")
      .lt("started_at", demoCutoffIso());
    if (cleanupErr) {
      console.warn("demo cleanup failed (non-fatal):", cleanupErr.message);
    }

    // 3. Rate limit: макс DEMO_MAX_ACTIVE активних demo-сесій
    const { count, error: countErr } = await db
      .from("guardian_sessions")
      .select("id", { count: "exact", head: true })
      .eq("settings->>demo", "true")
      .eq("status", "active");

    if (countErr) {
      console.error("count failed:", countErr);
      return json({ error: "internal_error" }, 500);
    }
    const limitCheck = validateDemoLimit(count ?? 0);
    if (!limitCheck.ok) {
      return json(
        { error: limitCheck.error, message: limitCheck.message },
        limitCheck.status ?? 429,
      );
    }

    // 4. Insert demo-session
    const { data: session, error: sErr } = await db
      .from("guardian_sessions")
      .insert(buildDemoSessionInsert())
      .select("id")
      .single();

    if (sErr || !session) {
      console.error("session insert failed:", sErr);
      return json({ error: "db_error" }, 500);
    }

    // 5. Insert guardian (PENDING token)
    const { data: guardian, error: gErr } = await db
      .from("guardians")
      .insert(buildDemoGuardianInsert(session.id))
      .select("id")
      .single();

    if (gErr || !guardian) {
      await db.from("guardian_sessions").delete().eq("id", session.id);
      console.error("guardian insert failed:", gErr);
      return json({ error: "guardian_create_failed" }, 500);
    }

    // 6. Token (2 аргументи: sessionId, guardianId) → update hash
    const { token, tokenHash, tokenPrefix } = await generateGuardianToken(
      session.id,
      guardian.id,
    );
    const { error: updErr } = await db
      .from("guardians")
      .update({ token_hash: tokenHash, token_prefix: tokenPrefix })
      .eq("id", guardian.id);

    if (updErr) {
      await db.from("guardian_sessions").delete().eq("id", session.id);
      console.error("token update failed:", updErr);
      return json({ error: "token_update_failed" }, 500);
    }

    // 7. Redirect URL → GUARDIAN_BASE_URL/s/<token>
    return json(
      { data: { url: buildGuardianUrl(token), session_id: session.id } },
      201,
    );
  } catch (err) {
    console.error("demo-create error:", err);
    return json({ error: "internal_error" }, 500);
  }
});
