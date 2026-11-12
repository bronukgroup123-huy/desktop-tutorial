// ============================================================================
// v1-analysis — машинний прогноз: аналіз ділянки (BACKEND_PLAN B2.9, ADR-015)
//
// GET  v1-analysis
//   → 200 { data: { sizes: [...], areas: [...], usage, hint_label } }
// POST v1-analysis  { lat, lng, size_km: 5 | 10, date?: "YYYY-MM-DD", forest?: { forest_km2, types: [{ forest_type, km2 }] } }
//   → 200 { data: { area, date, forest, top1, alternative, weather, warnings, usage } }
//
// Користувач ставить точку на карті — сервер аналізує квадрат навколо неї: які ліси
// і скільки їх у ділянці, погода, найімовірніші види. Результат — тільки рівні з
// готовими підписами, без відсотків (маніфест, Заборона №1).
//
// Правила (ADR-015 §15.1–15.2):
//   * ділянка — тільки у своїй області (`403 outside_home_region`);
//   * безкоштовно: 1 ділянка 5×5 км, базова погода, 5 аналізів на добу;
//   * 10×10 км, до 3 ділянок і горизонт далі 3 днів — Pro (`403 pro_required`);
//   * перевищення ліміту — `429 analysis_limit_reached` з часом скидання.
// Що доступно користувачу, каже сервер (`GET` → `sizes[].available`), клієнт лише показує.
// ============================================================================

import { parseEwkbPoint } from "../forecast/picks-list.ts";
import type { ForecastResult, ScoredSpecies } from "../forecast/types.ts";
import {
  assertMethod,
  type AuthUser,
  enforceRateLimit,
  HttpError,
  loadHomeRegionId,
  ok,
  readJson,
  requireHomeRegion,
  requireUser,
  type TokenVerifier,
} from "../http.ts";
import { forestTypeStyle } from "./forest-styles.ts";
import { weatherBlock } from "./forecast-labels.ts";
import { shapeSpecies } from "./forecast.ts";

export const ANALYSIS_SIZES = [5, 10] as const;
export type AnalysisSize = (typeof ANALYSIS_SIZES)[number];
/** Розмір, доступний лише в Pro. */
export const PRO_SIZE_KM = 10;
export const FREE_DAILY_LIMIT = 5;
export const PRO_DAILY_LIMIT = 10;
/** Горизонт прогнозу без Pro, днів від сьогодні (ADR-010). */
export const FREE_HORIZON_DAYS = 3;
/** Слот єдиної ділянки безкоштовного користувача. */
export const FREE_SLOT = 1;
/** Скільки переважних типів лісу проганяється через рушій прогнозу. */
export const MAX_FOREST_RUNS = 2;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

export const sizeLabel = (km: number) => `${km}×${km} км`;

/** Менше за це (≈ 1 га) — «лісу в ділянці немає». */
export const MIN_FOREST_KM2 = 0.01;
const MAX_HINT_TYPES = 12;

/**
 * Ліс у ділянці, порахований застосунком із тих самих полігонів, що на карті
 * (файл лісів області, ADR-015 + ліси з OSM). Таблиця `forest_zones` у БД містить
 * лише частину областей — без цієї підказки сервер казав «лісів немає» під
 * видимим лісовим масивом.
 */
export interface ForestHint {
  forestKm2: number;
  types: Array<{ forestType: string | null; km2: number }>;
}

// ─── Залежності ────────────────────────────────────────────────────────────

export interface AnalysisDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export interface AreaForecastInput {
  lat: number;
  lng: number;
  date: Date;
  forestType: string | null;
  homeRegionId: number;
}

export interface AnalysisDeps {
  db: AnalysisDb;
  verify: TokenVerifier;
  /** Прогноз для центру ділянки з заданим типом лісу (обгортка над ForecastEngine). */
  forecast: (input: AreaForecastInput) => Promise<ForecastResult>;
  /** Чи є в користувача Pro-аналіз (entitlements, B6.3). До запуску Pro — немає ні в кого. */
  hasAnalysisPro?: (userId: string) => Promise<boolean>;
  now?: () => Date;
}

function validationError(message: string): HttpError {
  return new HttpError(422, "validation_error", message);
}

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-analysis] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

// ─── Час (доба — за київським часом, як у лічильнику БД) ────────────────────

const KYIV_DATE = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Kyiv",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});
const KYIV_CLOCK = new Intl.DateTimeFormat("en-GB", {
  timeZone: "Europe/Kyiv",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
});

/** Сьогоднішня дата в Києві: "YYYY-MM-DD". */
export function kyivToday(now: Date): string {
  return KYIV_DATE.format(now);
}

/** Скільки секунд до київської півночі (скидання добового ліміту). */
export function secondsToKyivMidnight(now: Date): number {
  const [h, m, s] = KYIV_CLOCK.format(now).split(":").map(Number);
  return Math.max(1, 24 * 3600 - (h * 3600 + m * 60 + s));
}

// ─── Тіло запиту ───────────────────────────────────────────────────────────

export interface AnalysisInput {
  lat: number;
  lng: number;
  sizeKm: AnalysisSize;
  /** "YYYY-MM-DD" */
  date: string;
  forest: ForestHint | null;
}

const FOREST_TYPE_RE = /^[a-z_]{1,32}$/;

export function validateForestHint(raw: unknown, sizeKm: number): ForestHint | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) throw validationError("forest — об'єкт");
  const obj = raw as Record<string, unknown>;
  const area = sizeKm * sizeKm;
  const num = (v: unknown, what: string) => {
    if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > area * 1.05) {
      throw validationError(`${what} — площа від 0 до ${area} км²`);
    }
    return v;
  };
  const forestKm2 = num(obj.forest_km2, "forest.forest_km2");
  if (!Array.isArray(obj.types) || obj.types.length > MAX_HINT_TYPES) {
    throw validationError(`forest.types — список до ${MAX_HINT_TYPES} типів`);
  }
  const types = obj.types.map((t, i) => {
    if (t === null || typeof t !== "object") throw validationError(`forest.types[${i}] — об'єкт`);
    const ft = (t as Record<string, unknown>).forest_type;
    if (ft !== null && (typeof ft !== "string" || !FOREST_TYPE_RE.test(ft))) {
      throw validationError(`forest.types[${i}].forest_type — код типу лісу або null`);
    }
    return { forestType: ft as string | null, km2: num((t as Record<string, unknown>).km2, `forest.types[${i}].km2`) };
  });
  const sum = types.reduce((a, t) => a + t.km2, 0);
  if (sum > area * 1.05) throw validationError("forest.types — сума площ більша за ділянку");
  return { forestKm2: Math.min(forestKm2, area), types: types.sort((a, b) => b.km2 - a.km2) };
}

/** Підставляє ліс із підказки застосунку замість даних БД (межі квадрата — з БД). */
export function applyForestHint(db: ForestSummary, hint: ForestHint | null): ForestSummary {
  if (!hint) return db;
  return {
    bbox: db.bbox,
    area_km2: db.area_km2,
    forest_km2: Math.round(hint.forestKm2 * 100) / 100,
    types: hint.types.filter((t) => t.km2 > 0).map((t) => ({
      forest_type: t.forestType,
      km2: Math.round(t.km2 * 100) / 100,
      stand_age_years: null,
    })),
  };
}

export function validateAnalysisBody(body: unknown, now: Date): AnalysisInput {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw validationError("Тіло запиту має бути JSON-об'єктом");
  }
  const obj = body as Record<string, unknown>;

  if (typeof obj.lat !== "number" || !Number.isFinite(obj.lat) || obj.lat < -90 || obj.lat > 90) {
    throw validationError("lat — широта від -90 до 90");
  }
  if (typeof obj.lng !== "number" || !Number.isFinite(obj.lng) || obj.lng < -180 || obj.lng > 180) {
    throw validationError("lng — довгота від -180 до 180");
  }
  if (!(ANALYSIS_SIZES as readonly unknown[]).includes(obj.size_km)) {
    throw validationError("size_km — 5 або 10");
  }

  const today = kyivToday(now);
  let date = today;
  if (obj.date !== undefined && obj.date !== null) {
    if (
      typeof obj.date !== "string" || !DATE_RE.test(obj.date) ||
      Number.isNaN(new Date(`${obj.date}T00:00:00Z`).getTime())
    ) {
      throw validationError("date — дата у форматі РРРР-ММ-ДД");
    }
    date = obj.date;
  }
  if (date < today) throw validationError("Дата аналізу не може бути в минулому");

  const sizeKm = obj.size_km as AnalysisSize;
  return { lat: obj.lat, lng: obj.lng, sizeKm, date, forest: validateForestHint(obj.forest, sizeKm) };
}

/** На скільки днів `date` пізніше за `today` (обидві — "YYYY-MM-DD"). */
export function daysAhead(date: string, today: string): number {
  return Math.round((Date.parse(`${date}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / DAY_MS);
}

// ─── Підписи ───────────────────────────────────────────────────────────────

/** Площа українською: «≈ 8,4 км²», «≈ 12 км²». */
export function km2Label(km2: number): string {
  const text = km2 < 10 ? km2.toFixed(1).replace(".", ",") : String(Math.round(km2));
  return `≈ ${text} км²`;
}

export function usageBlock(used: number, limit: number): Record<string, unknown> {
  return { used, limit, label: `Сьогодні: ${used} з ${limit} аналізів` };
}

export function sizeOptions(hasPro: boolean): Array<Record<string, unknown>> {
  return ANALYSIS_SIZES.map((km) => {
    const available = km !== PRO_SIZE_KM || hasPro;
    return {
      size_km: km,
      label: sizeLabel(km),
      available,
      lock_label: available ? null : "Доступно в Pro",
    };
  });
}

interface ForestTypeRow {
  forest_type: string | null;
  km2: number;
  stand_age_years: number | null;
}

export interface ForestSummary {
  bbox: [number, number, number, number];
  area_km2: number;
  forest_km2: number;
  types: ForestTypeRow[];
}

export function shapeForest(f: ForestSummary): Record<string, unknown> {
  return {
    summary_label: f.forest_km2 >= MIN_FOREST_KM2
      ? `Ліс займає ${km2Label(f.forest_km2)} з ${f.area_km2} км² ділянки`
      : "На карті в цій ділянці лісів немає",
    types: f.types.slice(0, 5).map((t) => {
      const style = forestTypeStyle(t.forest_type);
      return {
        forest_type: t.forest_type,
        type_label: style.label,
        type_color: style.color,
        area_label: km2Label(Number(t.km2)),
        age_label: t.stand_age_years ? `~${Math.round(Number(t.stand_age_years))} р.` : null,
      };
    }),
  };
}

// ─── Доступи й ліміти ──────────────────────────────────────────────────────

async function hasPro(deps: AnalysisDeps, user: AuthUser): Promise<boolean> {
  return deps.hasAnalysisPro ? await deps.hasAnalysisPro(user.id) : false;
}

interface AreaRow {
  id: string;
  slot: number;
  size_km: number;
  center: unknown;
}

async function loadAreas(db: AnalysisDb, userId: string): Promise<AreaRow[]> {
  const { data, error } = await db
    .from("analysis_areas")
    .select("id, slot, size_km, center")
    .eq("user_id", userId);
  if (error) dbFail("analysis_areas select", error);
  return ((data ?? []) as AreaRow[]).sort((a, b) => a.slot - b.slot);
}

async function usedToday(db: AnalysisDb, userId: string, areaId: string): Promise<number> {
  const { data, error } = await db.rpc("analysis_used_today", { p_user_id: userId, p_area_id: areaId });
  if (error) dbFail("analysis_used_today", error);
  return Number(data ?? 0);
}

// ─── GET: що доступно і що вже збережено ───────────────────────────────────

async function getOverview(req: Request, user: AuthUser, deps: AnalysisDeps): Promise<Response> {
  const pro = await hasPro(deps, user);
  const limit = pro ? PRO_DAILY_LIMIT : FREE_DAILY_LIMIT;
  const areas = await loadAreas(deps.db, user.id);
  const first = areas[0];
  const used = first ? await usedToday(deps.db, user.id, first.id) : 0;

  return ok({
    sizes: sizeOptions(pro),
    areas: areas.flatMap((a) => {
      const point = typeof a.center === "string" ? parseEwkbPoint(a.center) : null;
      return point
        ? [{ id: a.id, slot: a.slot, lat: point.lat, lng: point.lng, size_km: a.size_km, size_label: sizeLabel(a.size_km) }]
        : [];
    }),
    usage: usageBlock(used, limit),
    hint_label: "Торкніться карти, щоб обрати центр ділянки",
  }, req);
}

// ─── POST: аналіз ──────────────────────────────────────────────────────────

interface Candidate {
  species: ScoredSpecies;
  forestType: string | null;
}

/** Найкращий вид і альтернатива серед прогонів для різних типів лісу ділянки. */
export function pickBest(
  runs: Array<{ forestType: string | null; result: ForecastResult }>,
): { top1: Candidate | null; alternative: Candidate | null } {
  const all: Candidate[] = [];
  for (const run of runs) {
    for (const species of [run.result.top1, run.result.alternative]) {
      if (species) all.push({ species, forestType: run.forestType });
    }
  }
  all.sort((a, b) => b.species.score - a.species.score); // score — лише для порядку, у відповідь не йде
  const top1 = all[0] ?? null;
  const alternative = top1
    ? all.find((c) => c.species.mushroom_type !== top1.species.mushroom_type) ?? null
    : null;
  return { top1, alternative };
}

function shapeCandidate(c: Candidate | null, result: ForecastResult): Record<string, unknown> | null {
  if (!c) return null;
  const shaped = shapeSpecies(c.species, result.weather);
  if (!shaped) return null;
  return { ...shaped, forest_label: c.forestType ? forestTypeStyle(c.forestType).label : null };
}

async function runAnalysis(
  req: Request,
  user: AuthUser,
  deps: AnalysisDeps,
  now: Date,
): Promise<Response> {
  const input = validateAnalysisBody(await readJson(req), now);

  // Тільки у своїй області (ADR-015 §15.2) — і в Pro також.
  const regionId = requireHomeRegion(await loadHomeRegionId(deps.db, user.id));
  const inRegion = await deps.db.rpc("point_in_region", { lat: input.lat, lng: input.lng, region_id: regionId });
  if (inRegion.error) dbFail("point_in_region", inRegion.error);
  if (inRegion.data !== true) {
    throw new HttpError(
      403,
      "outside_home_region",
      "Ділянка поза вашою областю. Аналіз доступний лише у своїй області.",
    );
  }

  const pro = await hasPro(deps, user);
  if (input.sizeKm === PRO_SIZE_KM && !pro) {
    throw new HttpError(403, "pro_required", "Ділянка 10×10 км доступна в Pro. Безкоштовно — ділянка 5×5 км.");
  }
  if (!pro && daysAhead(input.date, kyivToday(now)) > FREE_HORIZON_DAYS) {
    throw new HttpError(403, "pro_required", "Прогноз далі ніж на 3 дні доступний у Pro.");
  }

  // Ліміт перевіряємо до того, як пересунути збережену ділянку.
  const limit = pro ? PRO_DAILY_LIMIT : FREE_DAILY_LIMIT;
  const existing = (await loadAreas(deps.db, user.id)).find((a) => a.slot === FREE_SLOT);
  let used: number | null = null;
  if (existing) used = await consume(deps, user.id, existing.id, limit, now);

  const saved = await deps.db.rpc("save_analysis_area", {
    p_user_id: user.id,
    p_slot: FREE_SLOT,
    p_lat: input.lat,
    p_lng: input.lng,
    p_size_km: input.sizeKm,
    p_region_id: regionId,
  });
  if (saved.error || typeof saved.data !== "string") dbFail("save_analysis_area", saved.error ?? "no id");
  const areaId = saved.data;
  if (used === null) used = await consume(deps, user.id, areaId, limit, now);

  try {
    const forestRes = await deps.db.rpc("analyze_area_forest", {
      p_region_id: regionId,
      p_lat: input.lat,
      p_lng: input.lng,
      p_size_km: input.sizeKm,
    });
    if (forestRes.error || !forestRes.data) dbFail("analyze_area_forest", forestRes.error ?? "empty result");
    const forest = applyForestHint(forestRes.data as ForestSummary, input.forest);
    const hasForest = forest.forest_km2 >= MIN_FOREST_KM2;

    // Прогноз для переважних типів лісу ділянки; якщо лісів немає — базовий.
    const forestTypes = forest.types
      .map((t) => t.forest_type)
      .filter((t): t is string => typeof t === "string" && t.length > 0)
      .slice(0, MAX_FOREST_RUNS);
    const runTypes: Array<string | null> = forestTypes.length > 0 ? forestTypes : [null];
    const date = new Date(`${input.date}T00:00:00Z`);
    const runs = [];
    for (const forestType of runTypes) {
      runs.push({
        forestType,
        result: await deps.forecast({ lat: input.lat, lng: input.lng, date, forestType, homeRegionId: regionId }),
      });
    }
    const first = runs[0].result;
    // Лісу немає — лісові види не прогнозуємо (раніше рушій без типу лісу все одно
    // віддавав, напр., зимовий опеньок, і це суперечило «лісів немає»).
    const best = hasForest ? pickBest(runs) : { top1: null, alternative: null };
    const weather = weatherBlock(first.weather);

    const data: Record<string, unknown> = {
      area: {
        id: areaId,
        slot: FREE_SLOT,
        lat: input.lat,
        lng: input.lng,
        size_km: input.sizeKm,
        size_label: sizeLabel(input.sizeKm),
        bbox: forest.bbox,
      },
      date: input.date,
      forest: shapeForest(forest),
      top1: shapeCandidate(best.top1, first),
      alternative: shapeCandidate(best.alternative, first),
      // Безкоштовно — базова погода: температура, вологість, опади (ADR-015 §15.1).
      weather: weather
        ? { icon: weather.icon, temp_label: weather.temp_label, humidity_label: weather.humidity_label, rain_label: weather.rain_label }
        : null,
      warnings: [...new Set(runs.flatMap((r) => r.result.warnings))],
      usage: usageBlock(used, limit),
    };
    if (!hasForest) {
      data.no_data_reason = "У цій ділянці на карті немає лісу, тож лісові гриби тут не прогнозуємо. " +
        "Оберіть ділянку, де є ліс.";
    } else if (!best.top1 && first.noDataReason) {
      data.no_data_reason = first.noDataReason;
    }
    return ok(data, req);
  } catch (err) {
    // Розрахунок не вдався — списаний аналіз повертаємо.
    try {
      await deps.db.rpc("refund_analysis", { p_user_id: user.id, p_area_id: areaId });
    } catch (refundErr) {
      console.warn("[v1-analysis] refund failed:", refundErr);
    }
    if (err instanceof HttpError) throw err;
    console.error("[v1-analysis] analysis failed:", err);
    throw new HttpError(500, "internal_error", "Не вдалося виконати аналіз. Спробуйте ще раз.");
  }
}

/** Списує один аналіз; `429 analysis_limit_reached`, якщо добовий ліміт вичерпано. */
async function consume(
  deps: AnalysisDeps,
  userId: string,
  areaId: string,
  limit: number,
  now: Date,
): Promise<number> {
  const { data, error } = await deps.db.rpc("consume_analysis", {
    p_user_id: userId,
    p_area_id: areaId,
    p_limit: limit,
  });
  if (error) dbFail("consume_analysis", error);
  if (typeof data !== "number") {
    throw new HttpError(
      429,
      "analysis_limit_reached",
      `Сьогодні використано всі ${limit} аналізів. Ліміт оновиться о 00:00 за київським часом.`,
      { "Retry-After": String(secondsToKyivMidnight(now)) },
    );
  }
  return data;
}

export async function handleAnalysis(req: Request, deps: AnalysisDeps): Promise<Response> {
  assertMethod(req, ["GET", "POST"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-analysis");
  const user = await requireUser(req, deps.verify);
  const now = deps.now ? deps.now() : new Date();

  return req.method === "GET" ? await getOverview(req, user, deps) : await runAnalysis(req, user, deps, now);
}
