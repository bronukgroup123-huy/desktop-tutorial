// ============================================================================
// GET / PATCH /me — pure handlers (group 9.5)
//
// GET   /me → профіль поточного користувача
// PATCH /me → онбординг: { name?, home_region_slug? } (partial update)
//
// JWT обов'язковий (requireMushroomPicker у index.ts). service_role обходить
// users_self_read — тому фільтрація явна: .eq('id', userId).
// home_region_slug валідується через RPC find_region_by_slug (migration 00015).
//
// Логіка винесена сюди, щоб тестувати без supabase-js/esm.sh.
// ============================================================================

import { corsHeaders } from "../cors.ts";

/** Мінімальний структурний тип Supabase-клієнта (ланцюжок thenable, як у db.ts) */
export interface MeDbClient {
  from(table: string): any;
  rpc(
    fn: string,
    params: Record<string, unknown>
  ): Promise<{ data: unknown; error: unknown }>;
}

/** Тіло PATCH /me (partial) */
export interface UpdateMeInput {
  name?: string;
  home_region_slug?: string;
}

/** Результат валідації */
export type UpdateMeResult =
  | { ok: true; input: UpdateMeInput }
  | { ok: false; error: string; status: number };

/** home_region у відповіді (з regions.slug) */
export interface MeProfileHomeRegion {
  id: number;
  slug: string;
  name: string;
}

/** Формат відповіді GET/PATCH /me (data.*) */
export interface MeProfile {
  id: string;
  name: string | null;
  rating: number;
  total_verified_picks: number;
  home_region: MeProfileHomeRegion | null;
  created_at: string;
}

export const ME_NAME_MAX = 50;
export const ME_SLUG_REGEX = /^[a-z0-9][a-z0-9_-]{1,31}$/; // 2..32, lowercase

const USER_SELECT =
  "id, name, rating, total_verified_picks, home_region_id, created_at";

const JSON_HEADERS = { ...corsHeaders, "Content-Type": "application/json" };

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: JSON_HEADERS,
  });
}

/**
 * Валідація тіла PATCH /me.
 * Приймає лише object (не array/null); невідомі поля ігноруються;
 * потрібне хоча б одне з name / home_region_slug.
 */
export function validateUpdateMe(body: unknown): UpdateMeResult {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, error: "invalid_body", status: 400 };
  }
  const obj = body as Record<string, unknown>;

  const hasName = "name" in obj && obj.name !== undefined;
  const hasSlug = "home_region_slug" in obj && obj.home_region_slug !== undefined;
  if (!hasName && !hasSlug) {
    // порожнє тіло {} або лише невідомі поля
    return { ok: false, error: "invalid_body", status: 400 };
  }

  const input: UpdateMeInput = {};

  if (hasName) {
    if (typeof obj.name !== "string") {
      return { ok: false, error: "invalid_name", status: 400 };
    }
    const name = obj.name.trim();
    if (name.length < 1 || name.length > ME_NAME_MAX) {
      return { ok: false, error: "invalid_name", status: 400 };
    }
    input.name = name;
  }

  if (hasSlug) {
    if (typeof obj.home_region_slug !== "string" || !ME_SLUG_REGEX.test(obj.home_region_slug)) {
      return { ok: false, error: "invalid_region_slug", status: 400 };
    }
    input.home_region_slug = obj.home_region_slug;
  }

  return { ok: true, input };
}

/** Профіль користувача (users + home_region зі slug) */
async function buildProfile(
  db: MeDbClient,
  userId: string
): Promise<
  | { ok: true; profile: MeProfile }
  | { ok: false; error: string; status: number }
> {
  const { data, error } = await db
    .from("users")
    .select(USER_SELECT)
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    console.error("me profile query failed:", error);
    return { ok: false, error: "db_error", status: 500 };
  }
  if (!data) {
    return { ok: false, error: "me_not_found", status: 404 };
  }

  const row = data as Record<string, unknown>;

  let homeRegion: MeProfileHomeRegion | null = null;
  const homeRegionId = row.home_region_id as number | null;
  if (homeRegionId != null) {
    const { data: region, error: regionErr } = await db
      .from("regions")
      .select("id, slug, name")
      .eq("id", homeRegionId)
      .maybeSingle();
    if (regionErr) {
      console.error("me home_region query failed:", regionErr);
      return { ok: false, error: "db_error", status: 500 };
    }
    if (region) {
      homeRegion = region as MeProfileHomeRegion;
    }
  }

  return {
    ok: true,
    profile: {
      id: String(row.id),
      name: row.name != null ? String(row.name) : null,
      rating: Number(row.rating),
      total_verified_picks: Number(row.total_verified_picks),
      home_region: homeRegion,
      created_at: String(row.created_at),
    },
  };
}

/**
 * Обробник /me: 204 OPTIONS | 405 non-GET/PATCH | GET → профіль |
 * PATCH → оновлення профілю.
 */
export async function handleMeRequest(
  db: MeDbClient,
  userId: string,
  req: Request
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method === "GET") {
    const res = await buildProfile(db, userId);
    if (!res.ok) return jsonResponse({ error: res.error }, res.status);
    return jsonResponse({ data: res.profile }, 200);
  }
  if (req.method === "PATCH") {
    return handlePatchMe(db, userId, req);
  }
  return jsonResponse({ error: "method_not_allowed" }, 405);
}

/**
 * PATCH /me — partial update профілю.
 * 400 invalid_json / invalid_* | 404 region_not_found | 200 {data: profile}.
 */
export async function handlePatchMe(
  db: MeDbClient,
  userId: string,
  req: Request
): Promise<Response> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const v = validateUpdateMe(body);
  if (!v.ok) {
    return jsonResponse({ error: v.error }, v.status);
  }

  // home_region_slug → region_id (RPC 00015)
  let homeRegionId: number | undefined;
  if (v.input.home_region_slug !== undefined) {
    const { data, error } = await db.rpc("find_region_by_slug", {
      slug_input: v.input.home_region_slug,
    });
    if (error) {
      console.error("find_region_by_slug failed:", error);
      return jsonResponse({ error: "db_error" }, 500);
    }
    const region = (Array.isArray(data) ? data[0] : data) as
      | { id: number }
      | undefined
      | null;
    if (!region) {
      return jsonResponse({ error: "region_not_found" }, 404);
    }
    homeRegionId = region.id;
  }

  // UPDATE users (WHERE id = userId — явно, service_role обходить RLS)
  const patch: Record<string, unknown> = {};
  if (v.input.name !== undefined) patch.name = v.input.name;
  if (homeRegionId !== undefined) patch.home_region_id = homeRegionId;

  const { error: updErr } = await db
    .from("users")
    .update(patch)
    .eq("id", userId)
    .select("id")
    .maybeSingle();
  if (updErr) {
    console.error("me update failed:", updErr);
    return jsonResponse({ error: "db_error" }, 500);
  }

  // Відповідь — той самий формат, що GET /me (свіжий SELECT)
  const res = await buildProfile(db, userId);
  if (!res.ok) return jsonResponse({ error: res.error }, res.status);
  return jsonResponse({ data: res.profile }, 200);
}
