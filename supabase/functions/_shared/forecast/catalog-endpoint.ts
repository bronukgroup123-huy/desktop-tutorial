// ============================================================================
// GET /catalog — pure handler (group 9.3)
//
// Довідник 326 видів грибів для Flutter.
// Фільтри: ?forest=pine,oak | ?season=autumn | ?edible=true|false |
//          ?search=text (ILIKE по name_ua/name_lat)
// Пагінація: ?limit=50&offset=0 (default 50, max 100)
// Відповідь: { data: CatalogEntry[], total, limit, offset }
//
// Логіка винесена сюди, щоб тестувати без supabase-js/esm.sh —
// index.ts лише створює service_role-клієнт і викликає handleCatalogRequest.
// service_role обходить RLS (catalog_read — тільки authenticated).
// ============================================================================

import { corsHeaders } from "../cors.ts";
import { catalogRowToEntry } from "./types.ts";
import type { CatalogEntry } from "./types.ts";

/** Мінімальний структурний тип Supabase-клієнта (ланцюжок thenable, як у db.ts) */
export interface CatalogDbClient {
  from(table: string): any;
}

/** Розпарсені фільтри (limit/offset завжди є — дефолти) */
export interface CatalogFilters {
  forest?: string[];
  season?: string;
  edible?: boolean;
  search?: string;
  limit: number;
  offset: number;
}

/** Результат парсингу: фільтри або помилка валідації */
export type CatalogQueryResult = CatalogFilters | { error: string };

export const CATALOG_DEFAULT_LIMIT = 50;
export const CATALOG_MAX_LIMIT = 100;
export const CATALOG_MAX_SEARCH_LEN = 100;

/** Валідні значення attrs.season (дані каталогу), не Wave-енум */
export const CATALOG_SEASONS = ["spring", "summer", "autumn", "winter"] as const;

/** edible=true → ці два значення edibility; решта — "не їстівні" */
const EDIBLE_VALUES = ["edible", "conditionally_edible"];
const NOT_EDIBLE_VALUES = ["inedible", "poisonous", "deadly_poisonous"];

const SELECT_COLUMNS =
  "id, name_ua, name_lat, edibility, edibility_label, red_listed, " +
  "rarity, has_photo, top20, popular, months, peak_months, zones, attrs, photos, " +
  "ai_recognition, features";

const JSON_HEADERS = { ...corsHeaders, "Content-Type": "application/json" };

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: JSON_HEADERS,
  });
}

function parsePositiveInt(
  raw: string | null,
  fallback: number,
  max: number
): { value: number } | { error: string } {
  if (raw === null || raw === "") return { value: fallback };
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) return { error: "invalid_pagination" };
  if (n > max) return { error: "limit_out_of_range" };
  return { value: n };
}

function parseOffset(raw: string | null): { value: number } | { error: string } {
  if (raw === null || raw === "") return { value: 0 };
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 0) return { error: "invalid_offset" };
  return { value: n };
}

/**
 * Парсинг query-string у фільтри. При помилці → { error: '<code>' }.
 */
export function parseCatalogQuery(url: URL): CatalogQueryResult {
  const params = url.searchParams;

  const limit = parsePositiveInt(params.get("limit"), CATALOG_DEFAULT_LIMIT, CATALOG_MAX_LIMIT);
  if ("error" in limit) return limit;
  const offset = parseOffset(params.get("offset"));
  if ("error" in offset) return offset;

  const filters: CatalogFilters = { limit: limit.value, offset: offset.value };

  const forestRaw = params.get("forest");
  if (forestRaw !== null && forestRaw !== "") {
    const forest = forestRaw
      .split(",")
      .map((f) => f.trim().toLowerCase())
      .filter((f) => f !== "");
    if (forest.length > 0) filters.forest = forest;
  }

  const season = params.get("season");
  if (season !== null && season !== "") {
    if (!(CATALOG_SEASONS as readonly string[]).includes(season)) {
      return { error: "invalid_season" };
    }
    filters.season = season;
  }

  const edible = params.get("edible");
  if (edible !== null && edible !== "") {
    if (edible === "true") filters.edible = true;
    else if (edible === "false") filters.edible = false;
    else return { error: "invalid_edible" };
  }

  const search = params.get("search");
  if (search !== null && search.trim() !== "") {
    const trimmed = search.trim();
    if (trimmed.length > CATALOG_MAX_SEARCH_LEN) {
      return { error: "search_too_long" };
    }
    filters.search = trimmed;
  }

  return filters;
}

/**
 * Обробник GET /catalog.
 *
 * Статуси: 204 OPTIONS | 405 non-GET | 400 invalid_* | 200 {data,total,limit,offset} | 500 db_error.
 */
export async function handleCatalogRequest(
  db: CatalogDbClient,
  req: Request
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const filters = parseCatalogQuery(new URL(req.url));
  if ("error" in filters) {
    return jsonResponse({ error: filters.error }, 400);
  }

  try {
    let query = db
      .from("mushroom_catalog")
      .select(SELECT_COLUMNS, { count: "exact" });

    // forest: JSONB overlap по attrs->tree — OR кількох contains
    // (jsonb-масиви не підтримують overlaps-оператор PostgRES — лише @>)
    if (filters.forest && filters.forest.length > 0) {
      const orClause = filters.forest
        .map((f) => `attrs->tree.cs.["${f}"]`)
        .join(",");
      query = query.or(orClause);
    }
    // season: attrs.season містить значення
    if (filters.season) {
      query = query.contains("attrs->season", [filters.season]);
    }
    // edible: групування значень edibility
    if (filters.edible === true) {
      query = query.in("edibility", EDIBLE_VALUES);
    } else if (filters.edible === false) {
      query = query.in("edibility", NOT_EDIBLE_VALUES);
    }
    // search: ILIKE по name_ua / name_lat (description-колонки немає)
    if (filters.search) {
      const escaped = filters.search.replace(/[%,]/g, "\\$&");
      query = query.or(
        `name_ua.ilike.%${escaped}%,name_lat.ilike.%${escaped}%`
      );
    }

    const { data, error, count } = await query
      .order("name_ua", { ascending: true })
      .range(filters.offset, filters.offset + filters.limit - 1);

    if (error) {
      console.error("catalog query failed:", error);
      return jsonResponse({ error: "db_error" }, 500);
    }

    const items = Array.isArray(data)
      ? (data as Record<string, unknown>[]).map(catalogRowToEntry)
      : [];

    return jsonResponse(
      {
        data: items as CatalogEntry[],
        total: typeof count === "number" ? count : 0,
        limit: filters.limit,
        offset: filters.offset,
      },
      200
    );
  } catch (err) {
    console.error("catalog error:", err);
    return jsonResponse({ error: "internal_error" }, 500);
  }
}
