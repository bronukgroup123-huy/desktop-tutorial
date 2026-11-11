// ============================================================================
// GET /picks — pure handler (group 9.4)
//
// Стрічка трофеїв: scopes mine|public|region (scope friends скасовано ADR-018),
// periods 24h|3d|week|all, фільтри mushroom_type/region_slug,
// пагінація limit (20 default, max 50) / offset.
//
// БЕЗПЕКА (ADR-018 §18.5 — точні координати бачить лише автор):
//   readDb  — клієнт користувача (anon-key + JWT) → RLS mushroom_picks_read
//             (тільки власні точки). Лише для scope=mine; тут віддається точний geom.
//   adminDb — service_role. Чужі точки (scope=public|region) читаються тільки ним, з
//             явним фільтром pick_type = 'public' AND deleted_at IS NULL, і тільки
//             колонка display_geom (зсув 300–500 м). Колонка geom для цих scope
//             навіть не запитується. Також enrichment: users, regions, catalog,
//             signed URLs.
//
// Логіка винесена сюди, щоб тестувати без supabase-js/esm.sh.
// ============================================================================

import { buildCorsHeaders } from "../cors.ts";

export const PICKS_SCOPES = ["mine", "public", "region"] as const;
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
  /** scope=mine — точні координати; public/region — зсунуте місце (300–500 м). */
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

const PICK_COLUMNS =
  "id, user_id, mushroom_type, forest_type, pick_type, " +
  "verification_status, weight, is_indicator, is_negative, " +
  "created_at, photo_url";
/** Власні точки — з точними координатами. */
const PICK_SELECT_OWN = `${PICK_COLUMNS}, geom`;
/** Чужі публічні точки — лише зсунуте місце; `geom` не запитується взагалі. */
const PICK_SELECT_PUBLIC = `${PICK_COLUMNS}, display_geom`;

function jsonResponse(data: unknown, status: number, req: Request): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...buildCorsHeaders(req), "Content-Type": "application/json" },
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

/** Точка з EWKB у hex — саме так PostgREST віддає колонки типу geography. */
export function parseEwkbPoint(hex: string): { lat: number; lng: number } | null {
  if (hex.length < 42 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) return null;
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  const view = new DataView(bytes.buffer);
  const little = bytes[0] === 1;
  const type = view.getUint32(1, little);
  if ((type & 0xff) !== 1) return null; // не Point
  const offset = (type & 0x20000000) !== 0 ? 9 : 5; // з SRID чи без
  if (offset + 16 > bytes.length) return null;
  const lng = view.getFloat64(offset, little);
  const lat = view.getFloat64(offset + 8, little);
  return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
}

/** lat/lng з колонки geography: EWKB-hex (PostgREST) або GeoJSON. */
export function extractLatLng(geom: unknown): { lat: number | null; lng: number | null } {
  if (typeof geom === "string") {
    return parseEwkbPoint(geom) ?? { lat: null, lng: null };
  }
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
 * readDb (RLS-клієнт користувача) — лише власні точки (scope=mine);
 * adminDb (service_role) — публічні точки (тільки display_geom) та enrichment
 * (users/regions/catalog/signed URLs).
 */
export async function handlePicksListRequest(
  readDb: PicksListDbClient,
  adminDb: PicksListDbClient,
  userId: string | null,
  req: Request,
  now: Date = new Date()
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
  }
  if (req.method !== "GET") {
    return jsonResponse({ error: "method_not_allowed" }, 405, req);
  }

  const filters = parsePicksQuery(new URL(req.url));
  if ("error" in filters) {
    return jsonResponse({ error: filters.error }, 400, req);
  }

  // mine потребує userId (RLS фільтрує, але явний .eq — defense in depth)
  if (filters.scope === "mine" && !userId) {
    return jsonResponse({ error: "unauthorized" }, 401, req);
  }

  try {
    // scope=region: slug → region_id (RPC 00015), потім автори регіону
    let regionUserIds: Array<{ id: string }> | null = null;
    if (filters.scope === "region") {
      if (!filters.regionSlug) {
        return jsonResponse({ error: "missing_region_slug" }, 400, req);
      }
      const { data, error } = await adminDb.rpc("find_region_by_slug", {
        slug_input: filters.regionSlug,
      });
      if (error) {
        console.error("find_region_by_slug failed:", error);
        return jsonResponse({ error: "db_error" }, 500, req);
      }
      const region = (Array.isArray(data) ? data[0] : data) as
        | { id: number; name: string }
        | undefined
        | null;
      if (!region) {
        return jsonResponse({ error: "region_not_found" }, 404, req);
      }
      const { data: users, error: usersErr } = await adminDb
        .from("users")
        .select("id")
        .eq("home_region_id", region.id);
      if (usersErr) {
        console.error("users-by-region failed:", usersErr);
        return jsonResponse({ error: "db_error" }, 500, req);
      }
      regionUserIds = (users ?? []) as Array<{ id: string }>;
      if (regionUserIds.length === 0) {
        // порожній регіон — короткий шлях, без запиту picks
        return jsonResponse(
          { data: [], total: 0, limit: filters.limit, offset: filters.offset },
          200,
          req,
        );
      }
    }

    // ── Вибірка picks ──
    // mine: клієнт користувача (RLS) + точний geom.
    // public / region: service_role, тільки публічні точки і тільки display_geom.
    const own = filters.scope === "mine";
    let query = own
      ? readDb.from("mushroom_picks").select(PICK_SELECT_OWN, { count: "exact" })
      : adminDb.from("mushroom_picks").select(PICK_SELECT_PUBLIC, { count: "exact" });

    query = query.is("deleted_at", null);
    if (own) {
      query = query.eq("user_id", userId!);
    } else {
      // Відхилені спільнотою точки зникають зі стрічки (ADR-018 §18.4).
      query = query.eq("pick_type", "public").neq("verification_status", "rejected");
      if (filters.scope === "region" && regionUserIds) {
        query = query.in("user_id", regionUserIds.map((u) => u.id));
      }
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
      return jsonResponse({ error: "db_error" }, 500, req);
    }

    const rows = Array.isArray(data) ? (data as Record<string, unknown>[]) : [];

    // ── Enrichment (service_role): users → regions → catalog → signed URLs ──
    const items = await enrichFeedItems(adminDb, rows, own ? "geom" : "display_geom");

    return jsonResponse(
      {
        data: items,
        total: typeof count === "number" ? count : 0,
        limit: filters.limit,
        offset: filters.offset,
      },
      200,
      req
    );
  } catch (err) {
    console.error("picks feed error:", err);
    return jsonResponse({ error: "internal_error" }, 500, req);
  }
}

/** Мапінг рядків picks → PickFeedItem (batch-запити на adminDb, не N+1) */
async function enrichFeedItems(
  adminDb: PicksListDbClient,
  rows: Record<string, unknown>[],
  coordColumn: "geom" | "display_geom"
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
    const { lat, lng } = extractLatLng(row[coordColumn]);
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
