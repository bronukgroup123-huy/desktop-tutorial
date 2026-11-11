// ============================================================================
// v1-picks: карта тук-туків і картка точки (BACKEND_PLAN B3.3; ADR-018 §18.2, §18.5)
//
// GET v1-picks/map?bbox=minLng,minLat,maxLng,maxLat&mine=true|false
//   → 200 { data: { points: [...], truncated } }
// GET v1-picks/{id}
//   → 200 { data: { ...картка } } · 404 pick_not_found
//
// Користувач бачить публічні точки інших у своїй області (сірі — «Перевіряється»,
// зелені — «Підтверджено») і власні точки; `mine=true` додає власні приватні.
//
// Приватність: для чужих точок із БД приходить лише зсунуте місце (display_geom,
// 300–500 м). Точні координати — тільки автору (`is_exact: true`). У картці чужої
// точки немає ні імені, ні id автора, ні точного часу зйомки — лише дата.
// ============================================================================

import { type AuthUser, HttpError, loadHomeRegionId, ok, requireHomeRegion } from "../http.ts";
import { pickPresentation, speciesLabel } from "../picks/presentation.ts";
import type { PicksDeps } from "./picks.ts";

/** Максимум точок в одній відповіді; якщо їх більше — `truncated: true`. */
export const MAP_LIMIT = 500;
/** Термін дії посилання на фото в картці, секунди. */
export const PHOTO_URL_TTL_S = 600;
/** Найбільший bbox (як у v1-forest-zones): найбільша область ≈ 4.5° × 3°. */
export const MAX_BBOX_LNG_SPAN = 8;
export const MAX_BBOX_LAT_SPAN = 6;
export const PHOTO_DISCLAIMER = "Фото користувача — не порада їсти гриб";

const NUM = String.raw`-?\d+(?:\.\d+)?`;
const BBOX_RE = new RegExp(`^${NUM},${NUM},${NUM},${NUM}$`);

export interface PicksMapQuery {
  bbox: [number, number, number, number] | null;
  /** Показати й власні приватні точки (перемикач «Приватні точки»). */
  mine: boolean;
}

export function parsePicksMapQuery(url: URL): PicksMapQuery {
  const p = url.searchParams;

  let bbox: PicksMapQuery["bbox"] = null;
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

  const rawMine = p.get("mine");
  if (rawMine !== null && !["true", "false", "1", "0"].includes(rawMine)) {
    throw new HttpError(400, "invalid_mine", "mine: true або false");
  }
  return { bbox, mine: rawMine === "true" || rawMine === "1" };
}

interface MapRow {
  id: string;
  lat: number;
  lng: number;
  is_mine: boolean;
  pick_type: string;
  verification_status: string;
  species_id: string | null;
  name_ua: string | null;
}

/** Точка карти: готові підпис і колір; `is_exact` — тільки для власних точок. */
export function shapeMapPoint(row: MapRow): Record<string, unknown> {
  const mine = row.is_mine === true;
  return {
    id: row.id,
    lat: row.lat,
    lng: row.lng,
    is_exact: mine,
    is_mine: mine,
    visibility: row.pick_type,
    species_id: row.species_id ?? null,
    name_label: speciesLabel(row.name_ua),
    ...pickPresentation(row.pick_type, row.verification_status),
  };
}

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-picks] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

export async function handlePicksMap(
  req: Request,
  url: URL,
  user: AuthUser,
  deps: PicksDeps,
): Promise<Response> {
  const regionId = requireHomeRegion(await loadHomeRegionId(deps.db, user.id));
  const q = parsePicksMapQuery(url);

  const { data, error } = await deps.db.rpc("get_picks_map", {
    p_user_id: user.id,
    p_region_id: regionId,
    p_min_lng: q.bbox?.[0] ?? null,
    p_min_lat: q.bbox?.[1] ?? null,
    p_max_lng: q.bbox?.[2] ?? null,
    p_max_lat: q.bbox?.[3] ?? null,
    p_include_private: q.mine,
    p_limit: MAP_LIMIT,
  });
  if (error) dbFail("get_picks_map", error);

  const rows = Array.isArray(data) ? (data as MapRow[]) : [];
  return ok({
    points: rows.slice(0, MAP_LIMIT).map(shapeMapPoint),
    truncated: rows.length > MAP_LIMIT,
  }, req);
}

const DATE_FORMAT = new Intl.DateTimeFormat("uk-UA", {
  timeZone: "Europe/Kyiv",
  day: "numeric",
  month: "long",
  year: "numeric",
});

/** «10 листопада 2026 р.» — дата за київським часом. */
export function dateLabel(iso: unknown): string | null {
  if (typeof iso !== "string") return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : DATE_FORMAT.format(d);
}

interface CardRow extends MapRow {
  description: string | null;
  photo_path: string | null;
  taken_at: string | null;
}

export async function handlePickCard(
  req: Request,
  pickId: string,
  user: AuthUser,
  deps: PicksDeps,
): Promise<Response> {
  const regionId = requireHomeRegion(await loadHomeRegionId(deps.db, user.id));

  const { data, error } = await deps.db.rpc("get_pick_card", {
    p_user_id: user.id,
    p_region_id: regionId,
    p_pick_id: pickId,
  });
  if (error) dbFail("get_pick_card", error);
  // Чужа приватна, відхилена чи видалена точка відповідає так само, як неіснуюча.
  if (!data) throw new HttpError(404, "pick_not_found", "Точку не знайдено");
  const row = data as CardRow;
  const mine = row.is_mine === true;

  let photoUrl: string | null = null;
  if (row.photo_path) {
    const signed = await deps.storage.createSignedUrl(row.photo_path, PHOTO_URL_TTL_S);
    if (signed.error || !signed.data) {
      console.warn("[v1-picks] could not sign photo url:", signed.error);
    } else {
      photoUrl = signed.data.signedUrl;
    }
  }

  return ok({
    ...shapeMapPoint(row),
    description: row.description ?? null,
    date_label: dateLabel(row.taken_at),
    // Точний час зйомки — лише автору.
    captured_at: mine ? row.taken_at : null,
    photo_url: photoUrl,
    disclaimer_label: row.pick_type === "public" ? PHOTO_DISCLAIMER : null,
    // Дії з'являться разом з ендпоінтами: «Поскаржитися» — B3.12, зміна й видалення — B3.4.
    actions: [],
  }, req);
}
