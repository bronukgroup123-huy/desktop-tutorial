// ============================================================================
// GET v1-forest-zones — полігони лісів тільки в межах Home Region
// (BACKEND_PLAN B1.2, ADR-015 §15.2)
//
// Query: bbox=minLng,minLat,maxLng,maxLat (опційно) · z=0..22 (опційно) · limit=1..10000
// 200 { data: FeatureCollection } · 400 invalid_bbox / bbox_too_large / invalid_zoom /
// invalid_limit · 401 · 404 me_not_found · 409 home_region_required · 429 · 500
// ============================================================================

import {
  assertMethod,
  enforceRateLimit,
  HttpError,
  loadHomeRegionId,
  ok,
  requireHomeRegion,
  requireUser,
  type TokenVerifier,
  type UsersReadDb,
} from "../http.ts";
import { buildCorsHeaders } from "../cors.ts";
import { etagFor } from "./regions.ts";

/** Максимальний розмір bbox у градусах (найбільша область України ≈ 4.5° × 3°). */
export const MAX_BBOX_LNG_SPAN = 8;
export const MAX_BBOX_LAT_SPAN = 6;
export const DEFAULT_LIMIT = 5000;
export const MAX_LIMIT = 10000;

/** Підписи й кольори типів лісу — сервер віддає готові (Response Shaping). */
export const FOREST_TYPE_STYLE: Record<string, { label: string; color: string }> = {
  pine: { label: "Сосновий ліс", color: "#81c784" },
  spruce: { label: "Ялиновий ліс", color: "#2e7d32" },
  oak: { label: "Дубовий ліс", color: "#4caf50" },
  birch: { label: "Березовий ліс", color: "#aed581" },
  aspen: { label: "Осиковий ліс", color: "#c5e1a5" },
  alder: { label: "Вільшаний ліс", color: "#8bc34a" },
  beech: { label: "Буковий ліс", color: "#689f38" },
  hornbeam: { label: "Грабовий ліс", color: "#7cb342" },
  deciduous: { label: "Листяний ліс", color: "#a5d6a7" },
  coniferous: { label: "Хвойний ліс", color: "#66bb6a" },
  mixed: { label: "Мішаний ліс", color: "#9e9e9e" },
};
export const UNKNOWN_FOREST_STYLE = { label: "Ліс (тип невідомий)", color: "#b0bec5" };

export function forestTypeStyle(type: unknown): { label: string; color: string } {
  return (typeof type === "string" && FOREST_TYPE_STYLE[type]) || UNKNOWN_FOREST_STYLE;
}

export interface ForestZonesQuery {
  bbox: [number, number, number, number] | null;
  zoom: number | null;
  limit: number;
}

const NUM = String.raw`-?\d+(?:\.\d+)?`;
const BBOX_RE = new RegExp(`^${NUM},${NUM},${NUM},${NUM}$`);

export function parseForestZonesQuery(url: URL): ForestZonesQuery {
  const p = url.searchParams;

  let bbox: ForestZonesQuery["bbox"] = null;
  const rawBbox = p.get("bbox");
  if (rawBbox !== null) {
    if (!BBOX_RE.test(rawBbox)) {
      throw new HttpError(400, "invalid_bbox", "bbox: minLng,minLat,maxLng,maxLat");
    }
    const [minLng, minLat, maxLng, maxLat] = rawBbox.split(",").map(Number);
    if (
      minLng >= maxLng || minLat >= maxLat ||
      minLng < -180 || maxLng > 180 || minLat < -90 || maxLat > 90
    ) {
      throw new HttpError(400, "invalid_bbox", "Некоректні межі bbox");
    }
    if (maxLng - minLng > MAX_BBOX_LNG_SPAN || maxLat - minLat > MAX_BBOX_LAT_SPAN) {
      throw new HttpError(400, "bbox_too_large", "Запитана ділянка більша за область");
    }
    bbox = [minLng, minLat, maxLng, maxLat];
  }

  let zoom: number | null = null;
  const rawZ = p.get("z");
  if (rawZ !== null) {
    zoom = Number(rawZ);
    if (!Number.isInteger(zoom) || zoom < 0 || zoom > 22) {
      throw new HttpError(400, "invalid_zoom", "z — ціле число 0..22");
    }
  }

  let limit = DEFAULT_LIMIT;
  const rawLimit = p.get("limit");
  if (rawLimit !== null) {
    limit = Number(rawLimit);
    if (!Number.isInteger(limit) || limit < 1 || limit > MAX_LIMIT) {
      throw new HttpError(400, "invalid_limit", `limit — ціле число 1..${MAX_LIMIT}`);
    }
  }

  return { bbox, zoom, limit };
}

/** Допуск спрощення геометрії (градуси) за масштабом карти: дрібний масштаб — грубіше. */
export function toleranceForZoom(zoom: number | null): number {
  if (zoom === null || zoom >= 12) return 0;
  if (zoom >= 10) return 0.0002;
  if (zoom >= 8) return 0.0008;
  return 0.002;
}

interface Feature {
  type: "Feature";
  id?: unknown;
  geometry: unknown;
  properties: Record<string, unknown>;
}

/** Додає type_label / type_color до кожного полігону. */
export function shapeForestZones(raw: unknown): { type: "FeatureCollection"; features: Feature[] } {
  const features = (raw && typeof raw === "object" && Array.isArray((raw as { features?: unknown }).features))
    ? (raw as { features: Feature[] }).features
    : [];
  return {
    type: "FeatureCollection",
    features: features.map((f) => {
      const style = forestTypeStyle(f.properties?.forest_type);
      return {
        ...f,
        properties: { ...f.properties, type_label: style.label, type_color: style.color },
      };
    }),
  };
}

export interface ForestZonesDb extends UsersReadDb {
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export async function handleForestZones(
  req: Request,
  deps: { db: ForestZonesDb; verify: TokenVerifier },
): Promise<Response> {
  assertMethod(req, ["GET"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-forest-zones");

  const user = await requireUser(req, deps.verify);
  const regionId = requireHomeRegion(await loadHomeRegionId(deps.db, user.id));
  const q = parseForestZonesQuery(new URL(req.url));

  const { data, error } = await deps.db.rpc("get_forest_zones_geojson_region", {
    p_region_id: regionId,
    p_min_lng: q.bbox?.[0] ?? null,
    p_min_lat: q.bbox?.[1] ?? null,
    p_max_lng: q.bbox?.[2] ?? null,
    p_max_lat: q.bbox?.[3] ?? null,
    p_max_features: q.limit,
    p_tolerance: toleranceForZoom(q.zoom),
  });
  if (error) {
    console.error("[v1-forest-zones] rpc failed:", error);
    throw new HttpError(500, "db_error", "Не вдалося завантажити ліси");
  }

  const fc = shapeForestZones(data);
  console.log(`[v1-forest-zones] region=${regionId} features=${fc.features.length} z=${q.zoom ?? "-"}`);

  // Застосунок зберігає ліси області на телефоні й перевіряє, чи вони змінились,
  // через If-None-Match: без змін → 304 без тіла (офлайн-карта, B1.2/ADR-010).
  const etag = await etagFor(JSON.stringify(fc));
  const cacheHeaders = { "ETag": etag, "Cache-Control": "private, no-cache" };
  if (req.headers.get("If-None-Match") === etag) {
    return new Response(null, { status: 304, headers: { ...buildCorsHeaders(req), ...cacheHeaders } });
  }
  return ok(fc, req, 200, cacheHeaders);
}
