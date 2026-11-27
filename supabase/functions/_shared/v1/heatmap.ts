// ============================================================================
// v1-heatmap — теплова карта знахідок (BACKEND_PLAN B3.5; ADR-010 §10.4, ADR-013 §13.5)
//
// GET v1-heatmap?period=3d|7d|30d&bbox=minLng,minLat,maxLng,maxLat
//   → { data: { cells: [{ lat, lng, level }], cell_lat, cell_lng, period_days, scope, can_change_period,
//               legend_label, scope_label } }
//   level 1–3: 5–9 / 10–19 / 20+ перевірених публічних точок у клітинці ≈ 1 км (кількість не віддаємо).
//   Клітинка — лише ≥ 5 точок від ≥ 2 авторів. Точні координати лишаються на сервері (ADR-018 §18.5).
//
// Доступ (перевіряє SQL `heatmap_cells`): з «Лісовика» — своя область, 3 дні; «Хранитель» — + сусідні;
// «Майстер» або Pro — уся Україна, 3/7/30 днів. Нижче — 403 level_required; більше, ніж дозволено, — 403 pro_required.
// ============================================================================

import {
  assertMethod,
  assertRegistered,
  type AuthUser,
  enforceRateLimit,
  HttpError,
  ok,
  requireUser,
  type TokenVerifier,
} from "../http.ts";

export interface HeatmapDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export interface HeatmapDeps {
  db: HeatmapDb;
  verify: TokenVerifier;
  /** Чи є Pro (entitlements, B6.3). До запуску Pro — немає ні в кого. */
  hasPro?: (userId: string) => Promise<boolean>;
}

const NUM = String.raw`-?\d+(?:\.\d+)?`;
const BBOX_RE = new RegExp(`^${NUM},${NUM},${NUM},${NUM}$`);
/** Найбільший bbox: уся Україна з запасом. */
const MAX_LNG_SPAN = 20;
const MAX_LAT_SPAN = 10;
const PERIODS: Record<string, number> = { "3d": 3, "7d": 7, "30d": 30 };

const STATUS: Record<string, number> = {
  home_region_required: 409,
  level_required: 403,
  pro_required: 403,
  validation_error: 400,
};

export const LEGEND_LABEL = "Де частіше знаходили — без точних місць; лише підтверджені точки";
export const SCOPE_LABELS: Record<string, string> = {
  home: "Ваша область",
  neighbours: "Ваша й сусідні області",
  ukraine: "Уся Україна",
};

export interface HeatmapQuery {
  periodDays: number;
  bbox: [number, number, number, number] | null;
}

export function parseHeatmapQuery(url: URL): HeatmapQuery {
  const p = url.searchParams;
  const rawPeriod = p.get("period") ?? "3d";
  const periodDays = PERIODS[rawPeriod];
  if (!periodDays) throw new HttpError(400, "validation_error", "period — 3d, 7d або 30d");
  const rawBbox = p.get("bbox");
  let bbox: HeatmapQuery["bbox"] = null;
  if (rawBbox !== null) {
    if (!BBOX_RE.test(rawBbox)) throw new HttpError(400, "invalid_bbox", "bbox — minLng,minLat,maxLng,maxLat");
    const [minLng, minLat, maxLng, maxLat] = rawBbox.split(",").map(Number);
    if (minLng >= maxLng || minLat >= maxLat || minLng < -180 || maxLng > 180 || minLat < -90 || maxLat > 90) {
      throw new HttpError(400, "invalid_bbox", "bbox: межі задано неправильно");
    }
    if (maxLng - minLng > MAX_LNG_SPAN || maxLat - minLat > MAX_LAT_SPAN) {
      throw new HttpError(400, "bbox_too_large", "Завелика ділянка карти — наблизьте карту");
    }
    bbox = [minLng, minLat, maxLng, maxLat];
  }
  return { periodDays, bbox };
}

export async function handleHeatmap(req: Request, deps: HeatmapDeps): Promise<Response> {
  assertMethod(req, ["GET"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-heatmap");
  const user: AuthUser = await requireUser(req, deps.verify);
  assertRegistered(user);
  const q = parseHeatmapQuery(new URL(req.url));
  const pro = deps.hasPro ? await deps.hasPro(user.id) : false;

  const { data, error } = await deps.db.rpc("heatmap_cells", {
    p_user_id: user.id,
    p_period_days: q.periodDays,
    p_pro: pro,
    p_min_lng: q.bbox?.[0] ?? null,
    p_min_lat: q.bbox?.[1] ?? null,
    p_max_lng: q.bbox?.[2] ?? null,
    p_max_lat: q.bbox?.[3] ?? null,
  });
  if (error) {
    console.error("[v1-heatmap] heatmap_cells failed:", error);
    throw new HttpError(500, "db_error", "Помилка бази даних");
  }
  const r = (data ?? {}) as Record<string, unknown>;
  if (r.ok !== true) {
    const code = typeof r.code === "string" ? r.code : "validation_error";
    throw new HttpError(STATUS[code] ?? 400, code, typeof r.message === "string" ? r.message : "Не вдалося");
  }
  const { ok: _ok, ...rest } = r;
  return ok({
    ...rest,
    legend_label: LEGEND_LABEL,
    scope_label: SCOPE_LABELS[String(r.scope)] ?? null,
  }, req);
}
