// ============================================================================
// GET /picks — pure handler (group 9.4)
//
// Стрічка трофеїв для Flutter: scopes mine|friends|public|region,
// periods 24h|3d|week|all, фільтри mushroom_type/region_slug,
// пагінація limit (20 default, max 50) / offset.
//
// БЕЗПЕКА (гібрид клієнтів, бо RLS не дає прочитати чужі users-рядки):
//   readDb  — клієнт користувача (anon-key + JWT) → RLS mushroom_picks_read
//             (owner | shared_with | public | same home_region) enforced
//   adminDb — service_role → enrichment: users.name/home_region_id,
//             regions.name, catalog.name_ua, storage signed URLs
//
// Логіка винесена сюди, щоб тестувати без supabase-js/esm.sh.
// ============================================================================

import { corsHeaders } from "../cors.ts";

export const PICKS_SCOPES = ["mine", "friends", "public", "region"] as const;
export type PicksScope = (typeof PICKS_SCOPES)[number];

export const PICKS_PERIODS = ["24h", "3d", "week", "all"] as const;
export type PicksPeriod = (typeof PICKS_PERIODS)[number];

export const PICKS_DEFAULT_LIMIT = 20;
export const PICKS_MAX_LIMIT = 50;
export const PICKS_SIGNED_URL_TTL = 600; // 600s (спец 9.4)
const PICKS_BUCKET = "mushroom-photos";

/** Мінімальний структурний тип Supabase-клієнта (ланцюжок thenable, як у db.ts) */
export interface PicksListDbClient {
  from(table: string): any;
  storage: {
    from(bucket: string): {
      createSignedUrls(
        paths: string[],
        expiresIn: number
      ): Promise<{
        data: Array<{ path: string; signedUrl: string }> | null;
        error: unknown;
      }>;
    };
  };
  rpc(
    fn: string,
    params: Record<string, unknown>
  ): Promise<{ data: unknown; error: unknown }>;
}

/** Розпарсені фільтри (limit/offset завжди є — дефолти) */
export interface PicksListFilters {
  scope: PicksScope;
  period: PicksPeriod;
  limit: number;
  offset: number;
  mushroomType?: string;
  regionSlug?: string;
}

/** Рядок фіда (формат відповіді 9.4) */
export interface PickFeedItem {
  id: string;
  user_id: string;
  user_name: string | null;
  region_name: string | null;
  mushroom_type: string;
  name_ua: string | null;
  photo_url: string | null;
  lat: number | null;
  lng: number | null;
  forest_type: string | null;
  verification_status: string;
  weight: number;
  is_indicator: boolean;
  is_negative: boolean;
  created_at: string;
}

export type PicksQueryResult = PicksListFilters | { error: string };

const PICK_SELECT =
  "id, user_id, mushroom_type, forest_type, pick_type, " +
  "verification_status, weight, is_indicator, is_negative, " +
  "created_at, photo_url, geom";

const JSON_HEADERS = { ...corsHeaders, "Content-Type": "application/json" };

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: JSON_HEADERS,
  });
}

/** Частота періодів у мс; null = 'all' (без фільтра) */
export function periodCutoffMs(period: PicksPeriod, now: Date): number | null {
  const H = 60 * 60 * 1000;
  switch (period) {
    case "24h":
      return now.getTime() - 24 * H;
    case "3d":
      return now.getTime() - 3 * 24 * H;
    case "week":
      return now.getTime() - 7 * 24 * H;
    case "all":
      return null;
  }
}

/** lat/lng з GeoJSON `geom` (supabase-js віддає geography як GeoJSON) */
export function extractLatLng(geom: unknown): { lat: number | null; lng: number | null } {
  if (geom && typeof geom === "object" && "coordinates" in geom) {
    const c = (geom as { coordinates: unknown }).coordinates;
    if (Array.isArray(c) && c.length === 2) {
      const lng = Number(c[0]);
      const lat = Number(c[1]);
      if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
    }
  }
  return { lat: null, lng: null };
}

/**
 * Парсинг query-string у фільтри. При помилці → { error: '<code>' }.
 */
export function parsePicksQuery(url: URL): PicksQueryResult {
  const params = url.searchParams;

  const scopeRaw = params.get("scope");
  const scope: PicksScope =
    scopeRaw === null || scopeRaw === ""
      ? "public"
      : (PICKS_SCOPES as readonly string[]).includes(scopeRaw)
      ? (scopeRaw as PicksScope)
      : (null as unknown as PicksScope);
  if (scope === null) return { error: "invalid_scope" };

  const periodRaw = params.get("period");
  const period: PicksPeriod =
    periodRaw === null || periodRaw === ""
      ? "week"
      : (PICKS_PERIODS as readonly string[]).includes(periodRaw)
      ? (periodRaw as PicksPeriod)
      : (null as unknown as PicksPeriod);
  if (period === null) return { error: "invalid_period" };

  let limit = PICKS_DEFAULT_LIMIT;
  const limitRaw = params.get("limit");
  if (limitRaw !== null && limitRaw !== "") {
    const n = Number(limitRaw);
    if (!Number.isInteger(n) || n < 1) return { error: "invalid_pagination" };
    if (n > PICKS_MAX_LIMIT) return { error: "limit_out_of_range" };
    limit = n;
  }

  let offset = 0;
  const offsetRaw = params.get("offset");
  if (offsetRaw !== null && offsetRaw !== "") {
    const n = Number(offsetRaw);
    if (!Number.isInteger(n) || n < 0) return { error: "invalid_offset" };
    offset = n;
  }

  const filters: PicksListFilters = { scope, period, limit, offset };

  const mushroomType = params.get("mushroom_type");
  if (mushroomType !== null && mushroomType !== "") {
    if (!/^[a-z][a-z0-9_]{0,63}$/.test(mushroomType)) {
      return { error: "invalid_mushroom_type" };
    }
    filters.mushroomType = mushroomType;
  }

  const regionSlug = params.get("region_slug");
  if (regionSlug !== null && regionSlug !== "") {
    if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(regionSlug)) {
      return { error: "invalid_region_slug" };
    }
    filters.regionSlug = regionSlug;
  }

  return filters;
}

/**
 * Обробник GET /picks.
 *
 * Статуси: 204 OPTIONS | 405 non-GET | 400 invalid_* | 401 unauthorized |
 *          404 region_not_found | 200 {data,total,limit,offset} | 500 db_error.
 *
 * readDb (RLS-клієнт користувача) — вибірка picks; adminDb (service_role) —
 * enrichment (users/regions/catalog/signed URLs).
 */
export async function handlePicksListRequest(
  readDb: PicksListDbClient,
  adminDb: PicksListDbClient,
  userId: string | null,
  req: Request,
  now: Date = new Date()
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const filters = parsePicksQuery(new URL(req.url));
  if ("error" in filters) {
    return jsonResponse({ error: filters.error }, 400);
  }

  // mine/friends потребують userId (RLS фільтрує, але явний .eq — defense in depth)
  if ((filters.scope === "mine" || filters.scope === "friends") && !userId) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  try {
    // scope=region: slug → region_id (RPC 00015), потім автори регіону
    let regionUserIds: Array<{ id: string }> | null = null;
    if (filters.scope === "region") {
      if (!filters.regionSlug) {
        return jsonResponse({ error: "missing_region_slug" }, 400);
      }
      const { data, error } = await adminDb.rpc("find_region_by_slug", {
        slug_input: filters.regionSlug,
      });
      if (error) {
        console.error("find_region_by_slug failed:", error);
        return jsonResponse({ error: "db_error" }, 500);
      }
      const region = (Array.isArray(data) ? data[0] : data) as
        | { id: number; name: string }
        | undefined
        | null;
      if (!region) {
        return jsonResponse({ error: "region_not_found" }, 404);
      }
      const { data: users, error: usersErr } = await adminDb
        .from("users")
        .select("id")
        .eq("home_region_id", region.id);
      if (usersErr) {
        console.error("users-by-region failed:", usersErr);
        return jsonResponse({ error: "db_error" }, 500);
      }
      regionUserIds = (users ?? []) as Array<{ id: string }>;
      if (regionUserIds.length === 0) {
        // порожній регіон — короткий шлях, без запиту picks
        return jsonResponse(
          { data: [], total: 0, limit: filters.limit, offset: filters.offset },
          200
        );
      }
    }

    // ── Вибірка picks (RLS-клієнт) ──
    let query = readDb.from("mushroom_picks").select(PICK_SELECT, { count: "exact" });

    if (filters.scope === "mine") {
      query = query.eq("user_id", userId!);
    } else if (filters.scope === "friends") {
      // RLS покаже лише ті, що shared_with=me / public / same-region / mine
      query = query.eq("pick_type", "friends");
    } else if (filters.scope === "public") {
      query = query.eq("pick_type", "public");
    } else if (filters.scope === "region" && regionUserIds) {
      query = query.in("user_id", regionUserIds.map((u) => u.id));
    }

    const cutoff = periodCutoffMs(filters.period, now);
    if (cutoff !== null) {
      query = query.gte("created_at", new Date(cutoff).toISOString());
    }

    if (filters.mushroomType) {
      query = query.eq("mushroom_type", filters.mushroomType);
    }

    const { data, error, count } = await query
      .order("created_at", { ascending: false })
      .range(filters.offset, filters.offset + filters.limit - 1);

    if (error) {
      console.error("picks query failed:", error);
      return jsonResponse({ error: "db_error" }, 500);
    }

    const rows = Array.isArray(data) ? (data as Record<string, unknown>[]) : [];

    // ── Enrichment (service_role): users → regions → catalog → signed URLs ──
    const items = await enrichFeedItems(adminDb, rows);

    return jsonResponse(
      {
        data: items,
        total: typeof count === "number" ? count : 0,
        limit: filters.limit,
        offset: filters.offset,
      },
      200
    );
  } catch (err) {
    console.error("picks feed error:", err);
    return jsonResponse({ error: "internal_error" }, 500);
  }
}

/** Мапінг рядків picks → PickFeedItem (batch-запити на adminDb, не N+1) */
async function enrichFeedItems(
  adminDb: PicksListDbClient,
  rows: Record<string, unknown>[]
): Promise<PickFeedItem[]> {
  if (rows.length === 0) return [];

  const userIds = [...new Set(rows.map((r) => String(r.user_id)))];
  const types = [...new Set(rows.map((r) => String(r.mushroom_type)))];

  // users (RLS self-read не дасть читати чужих — тому service_role)
  const { data: usersData, error: usersErr } = await adminDb
    .from("users")
    .select("id, name, home_region_id")
    .in("id", userIds);
  if (usersErr) {
    console.error("users enrichment failed:", usersErr);
    throw usersErr; // → 500 internal_error
  }
  const users = (usersData ?? []) as Array<{
    id: string;
    name: string | null;
    home_region_id: number | null;
  }>;
  const usersById = new Map(users.map((u) => [u.id, u]));

  // regions — імена домашніх регіонів авторів
  const regionIds = [
    ...new Set(users.map((u) => u.home_region_id).filter((v): v is number => v != null)),
  ];
  let regionsById = new Map<number, string>();
  if (regionIds.length > 0) {
    const { data: regionsData, error: regionsErr } = await adminDb
      .from("regions")
      .select("id, name")
      .in("id", regionIds);
    if (regionsErr) {
      console.error("regions enrichment failed:", regionsErr);
      throw regionsErr;
    }
    regionsById = new Map(
      ((regionsData ?? []) as Array<{ id: number; name: string }>).map((r) => [r.id, r.name])
    );
  }

  // catalog — name_ua по mushroom_type
  const { data: catalogData, error: catalogErr } = await adminDb
    .from("mushroom_catalog")
    .select("id, name_ua")
    .in("id", types);
  if (catalogErr) {
    console.error("catalog enrichment failed:", catalogErr);
    throw catalogErr;
  }
  const nameUaByType = new Map(
    ((catalogData ?? []) as Array<{ id: string; name_ua: string }>).map((c) => [
      c.id,
      c.name_ua,
    ])
  );

  // signed URLs — один batch-виклик (не N+1); помилка → photo_url null
  const photoPaths = [
    ...new Set(rows.map((r) => (r.photo_url ? String(r.photo_url) : null)).filter(
      (p): p is string => p != null
    )),
  ];
  let signedByPath = new Map<string, string>();
  if (photoPaths.length > 0) {
    const { data: signed, error: signErr } = await adminDb.storage
      .from(PICKS_BUCKET)
      .createSignedUrls(photoPaths, PICKS_SIGNED_URL_TTL);
    if (signErr) {
      console.error("signed urls failed:", signErr);
    } else {
      signedByPath = new Map(
        ((signed ?? []) as Array<{ path: string; signedUrl: string }>).map((s) => [
          s.path,
          s.signedUrl,
        ])
      );
    }
  }

  return rows.map((row) => {
    const userId = String(row.user_id);
    const user = usersById.get(userId);
    const { lat, lng } = extractLatLng(row.geom);
    const photoPath = row.photo_url ? String(row.photo_url) : null;
    return {
      id: String(row.id),
      user_id: userId,
      user_name: user?.name ?? null,
      region_name:
        user?.home_region_id != null
          ? regionsById.get(user.home_region_id) ?? null
          : null,
      mushroom_type: String(row.mushroom_type),
      name_ua: nameUaByType.get(String(row.mushroom_type)) ?? null,
      photo_url: photoPath ? signedByPath.get(photoPath) ?? null : null,
      lat,
      lng,
      forest_type: row.forest_type != null ? String(row.forest_type) : null,
      verification_status: String(row.verification_status),
      weight: Number(row.weight),
      is_indicator: Boolean(row.is_indicator),
      is_negative: Boolean(row.is_negative),
      created_at: String(row.created_at),
    };
  });
}
