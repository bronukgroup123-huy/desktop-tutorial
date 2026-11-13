// ============================================================================
// GET v1-regions/{slug}/geometry — кордон області для маски «острова» (B1.1)
//
// Публічний (потрібен ще до вибору області), з rate limit і кешуванням (ETag).
// Query: detail=low|medium|high (за замовчуванням medium).
// 200 { data: { id, slug, name, bbox, center, zoom, geometry } } · 304 · 400 · 404 · 429
// ============================================================================

import { assertMethod, enforceRateLimit, HttpError, ok } from "../http.ts";
import { buildCorsHeaders } from "../cors.ts";

export const SLUG_RE = /^[a-z0-9][a-z0-9_-]{1,31}$/;

export const DETAIL_TOLERANCE: Record<string, number> = {
  low: 0.02,
  medium: 0.005,
  high: 0.001,
};

/** slug з шляху `/v1-regions/{slug}/geometry` або з `?slug=`. */
export function parseGeometryRequest(url: URL): { slug: string; tolerance: number } {
  const m = url.pathname.match(/\/v1-regions\/([^/]+)\/geometry\/?$/);
  const slug = m ? decodeURIComponent(m[1]) : url.searchParams.get("slug");
  if (!slug) {
    throw new HttpError(404, "not_found", "Очікується /v1-regions/{slug}/geometry");
  }
  if (!SLUG_RE.test(slug)) {
    throw new HttpError(400, "invalid_region_slug", "Некоректний slug області");
  }
  const detail = url.searchParams.get("detail") ?? "medium";
  const tolerance = DETAIL_TOLERANCE[detail];
  if (tolerance === undefined) {
    throw new HttpError(400, "invalid_detail", "detail: low | medium | high");
  }
  return { slug, tolerance };
}

/** Де лежать файли лісів областей (GitHub Releases; змінюється без релізу застосунку). */
export const DEFAULT_FORESTS_BASE_URL =
  "https://github.com/bronukgroup123-huy/desktop-tutorial/releases/download/forests-data";

export function forestFiles(slug: string, baseUrl?: string): { meta_url: string; data_url: string } {
  const base = (baseUrl || DEFAULT_FORESTS_BASE_URL).replace(/\/+$/, "");
  return {
    meta_url: `${base}/forests-${slug}.json`,
    data_url: `${base}/forests-${slug}.geojson.gz`,
  };
}

/** Де лежать карти-підкладки областей для роботи без інтернету (пілот, рішення PO 2026-11-13). */
export const DEFAULT_BASEMAP_BASE_URL =
  "https://github.com/bronukgroup123-huy/desktop-tutorial/releases/download/basemap-data";

/** Файл карти області (PMTiles) і його опис; немає опису (404) — карти для області ще немає. */
export function basemapFiles(slug: string, baseUrl?: string): { meta_url: string; data_url: string } {
  const base = (baseUrl || DEFAULT_BASEMAP_BASE_URL).replace(/\/+$/, "");
  return {
    meta_url: `${base}/basemap-${slug}.json`,
    data_url: `${base}/basemap-${slug}.pmtiles`,
  };
}

/** Рекомендований початковий zoom, щоб область вмістилась на екрані. */
export function zoomForBbox(bbox: [number, number, number, number]): number {
  const lngSpan = Math.max(bbox[2] - bbox[0], 1e-6);
  const latSpan = Math.max(bbox[3] - bbox[1], 1e-6);
  const span = Math.max(lngSpan, latSpan * 1.5); // широта на мапі «довша» в середніх широтах
  const z = Math.floor(Math.log2(360 / span));
  return Math.min(12, Math.max(5, z));
}

export async function etagFor(body: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(body));
  const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `"${hex}"`;
}

export interface RegionsDb {
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export async function handleRegionGeometry(
  req: Request,
  deps: { db: RegionsDb; forestsBaseUrl?: string; basemapBaseUrl?: string },
): Promise<Response> {
  assertMethod(req, ["GET"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-regions");

  const { slug, tolerance } = parseGeometryRequest(new URL(req.url));
  const { data, error } = await deps.db.rpc("get_region_geometry", {
    p_slug: slug,
    p_tolerance: tolerance,
  });
  if (error) {
    console.error("[v1-regions] rpc failed:", error);
    throw new HttpError(500, "db_error", "Не вдалося завантажити кордон області");
  }
  if (!data) {
    throw new HttpError(404, "region_not_found", "Область не знайдено");
  }

  const row = data as {
    id: number; slug: string; name: string;
    bbox: [number, number, number, number]; center: [number, number]; geometry: unknown;
  };
  const payload = {
    id: row.id,
    slug: row.slug,
    name: row.name,
    bbox: row.bbox,
    center: row.center,
    zoom: zoomForBbox(row.bbox),
    geometry: row.geometry,
    // Ліси області — одним файлом (завантажується застосунком один раз, офлайн).
    forests: forestFiles(row.slug, deps.forestsBaseUrl),
    // Карта-підкладка області — один файл, завантажується один раз і працює без інтернету.
    basemap: basemapFiles(row.slug, deps.basemapBaseUrl),
  };

  const body = JSON.stringify({ data: payload });
  const etag = await etagFor(body);
  const cacheHeaders = { "Cache-Control": "public, max-age=86400", "ETag": etag };
  if (req.headers.get("If-None-Match") === etag) {
    return new Response(null, { status: 304, headers: { ...buildCorsHeaders(req), ...cacheHeaders } });
  }
  return ok(payload, req, 200, cacheHeaders);
}

