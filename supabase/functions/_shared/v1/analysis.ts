// ============================================================================
// v1-analysis — машинний прогноз: аналіз ділянки (BACKEND_PLAN B2.9, ADR-015)
//
// GET    v1-analysis
//   → 200 { data: { sizes, areas: [{ id, slot, lat, lng, size_km, size_label, bbox?,
//            usage, last_result?, last_analyzed_at? }], can_create, create_hint_label,
//            usage, hint_label } }
// POST   v1-analysis  { lat, lng, size_km: 5 | 10, date?, forest? }   — НОВА ділянка + аналіз
// POST   v1-analysis  { area_id, date?, forest? }                     — повторний аналіз тієї ж ділянки
//   → 200 { data: { area, date, forest, top1, alternative, weather, warnings, usage,
//            days: [{ date, day_label, approximate, level…, top1, alternative, weather }],
//            horizon_days, best_day?, locked_days, locked_label? } }
//   Один аналіз рахує ВСІ дні горизонту (безкоштовно 3, Pro 7, від сьогодні); top1/weather
//   верхнього рівня — для `date` (за замовчуванням сьогодні). Перемикання днів — без запитів.
// DELETE v1-analysis/areas/{id}  → 200 { data: { deleted: true } }
// PUT    v1-analysis/areas/{id}/forest  { override: { types, extra } | null, forest?, date? }
//   → 200 { data: { ...як POST, forest_edit } } — уточнення лісу вручну + переаналіз (ADR-015 §15.6)
//
// Правила (ADR-015 §15.1, §15.2, §15.4):
//   * ділянка — тільки у своїй області (`403 outside_home_region`);
//   * ділянку НЕ пересувають: створюють у вільний слот або видаляють і створюють нову.
//     Вільного слоту немає → `409 area_limit_reached`;
//   * безкоштовно: 1 ділянка 5×5 км, базова погода, 5 аналізів на добу;
//   * 10×10 км, до 3 ділянок і дні 4–7 — Pro (`403 pro_required`); далі 7 днів — 422;
//   * ліміт — на слот за добу: «видалити → створити» його не обнуляє;
//     перевищення — `429 analysis_limit_reached` з часом скидання;
//   * останній результат зберігається з ділянкою — вкладка «Прогноз» показує його без
//     повторного списання.
// Що доступно користувачу, каже сервер (`GET` → `sizes[].available`, `can_create`).
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
import { LEVEL_COLOR, LEVEL_LABEL, normalizeLevel, type ProbabilityLevel, shapeSpecies } from "./forecast.ts";

export const ANALYSIS_SIZES = [5, 10] as const;
export type AnalysisSize = (typeof ANALYSIS_SIZES)[number];
/** Розмір, доступний лише в Pro. */
export const PRO_SIZE_KM = 10;
export const FREE_DAILY_LIMIT = 5;
export const PRO_DAILY_LIMIT = 10;
/** Горизонт прогнозу, днів разом із сьогодні (ADR-010): безкоштовно 3, Pro 7. */
export const FREE_HORIZON_DAYS = 3;
export const PRO_HORIZON_DAYS = 7;
export const horizonDays = (pro: boolean) => (pro ? PRO_HORIZON_DAYS : FREE_HORIZON_DAYS);
/** З якого дня від сьогодні прогноз «орієнтовний» (дні 5–7: дощ так далеко прогнозують гірше). */
export const APPROXIMATE_FROM_DAY = 4;
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

// ─── Уточнення лісу ділянки вручну (ADR-015 §15.6) ──────────────────────────

/** Не частіше 2 уточнень на ділянку за добу (київський час). */
export const FOREST_EDITS_PER_DAY = 2;
/** З уточненням прогноз рахується для до 3 порід (без нього — для 2 переважних типів). */
export const MAX_REFINED_RUNS = 3;

/** Породи, які знає прогноз (правила видів, `SpeciesRule.forestType`). */
export const FOREST_SPECIES = ["pine", "spruce", "oak", "birch", "aspen", "alder", "beech", "hornbeam"] as const;
export type ForestSpecies = (typeof FOREST_SPECIES)[number];

export const SPECIES_LABEL: Record<ForestSpecies, string> = {
  pine: "сосна",
  spruce: "ялина",
  oak: "дуб",
  birch: "береза",
  aspen: "осика",
  alder: "вільха",
  beech: "бук",
  hornbeam: "граб",
};

export const PRESENCE_LABEL = { dominant: "переважає", present: "є місцями" } as const;
export type Presence = keyof typeof PRESENCE_LABEL;

const MAX_OVERRIDE_TYPES = 12;
const MAX_OVERRIDE_EXTRA = 4;

/** Що користувач обрав: породи для типів лісу з карти + породи, яких карта не бачить. */
export interface ForestOverride {
  types: Array<{ forestType: string | null; species: ForestSpecies[] }>;
  extra: Array<{ species: ForestSpecies; presence: Presence }>;
}

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** Список порід і варіантів «присутності» — для вибору в застосунку (лише зі списку). */
export function forestEditOptions(): Record<string, unknown> {
  return {
    species: FOREST_SPECIES.map((code) => ({ code, label: capitalize(SPECIES_LABEL[code]) })),
    presence: (Object.keys(PRESENCE_LABEL) as Presence[]).map((code) => ({ code, label: PRESENCE_LABEL[code] })),
  };
}

function isSpecies(v: unknown): v is ForestSpecies {
  return typeof v === "string" && (FOREST_SPECIES as readonly string[]).includes(v);
}

/** Перевірка уточнення з тіла запиту; `null` — «Скинути до карти». */
export function validateForestOverride(raw: unknown): ForestOverride | null {
  if (raw === null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) throw validationError("override — об'єкт або null");
  const obj = raw as Record<string, unknown>;
  const typesRaw = obj.types ?? [];
  const extraRaw = obj.extra ?? [];
  if (!Array.isArray(typesRaw) || typesRaw.length > MAX_OVERRIDE_TYPES) {
    throw validationError(`override.types — список до ${MAX_OVERRIDE_TYPES} типів лісу`);
  }
  if (!Array.isArray(extraRaw) || extraRaw.length > MAX_OVERRIDE_EXTRA) {
    throw validationError(`override.extra — до ${MAX_OVERRIDE_EXTRA} порід`);
  }
  const seenTypes = new Set<string>();
  const types = typesRaw.map((t, i) => {
    if (t === null || typeof t !== "object") throw validationError(`override.types[${i}] — об'єкт`);
    const ft = (t as Record<string, unknown>).forest_type;
    if (ft !== null && (typeof ft !== "string" || !FOREST_TYPE_RE.test(ft))) {
      throw validationError(`override.types[${i}].forest_type — код типу лісу або null`);
    }
    const key = String(ft);
    if (seenTypes.has(key)) throw validationError(`override.types[${i}] — тип лісу повторюється`);
    seenTypes.add(key);
    const sp = (t as Record<string, unknown>).species;
    if (!Array.isArray(sp) || sp.length < 1 || sp.length > 2 || !sp.every(isSpecies) || new Set(sp).size !== sp.length) {
      throw validationError(`override.types[${i}].species — 1 або 2 різні породи зі списку`);
    }
    return { forestType: ft as string | null, species: sp as ForestSpecies[] };
  });
  const seenExtra = new Set<string>();
  const extra = extraRaw.map((e, i) => {
    if (e === null || typeof e !== "object") throw validationError(`override.extra[${i}] — об'єкт`);
    const { species, presence } = e as Record<string, unknown>;
    if (!isSpecies(species)) throw validationError(`override.extra[${i}].species — порода зі списку`);
    if (seenExtra.has(species)) throw validationError(`override.extra[${i}] — порода повторюється`);
    seenExtra.add(species);
    if (typeof presence !== "string" || !(presence in PRESENCE_LABEL)) {
      throw validationError(`override.extra[${i}].presence — dominant або present`);
    }
    return { species, presence: presence as Presence };
  });
  if (types.length === 0 && extra.length === 0) {
    throw validationError("override — оберіть хоча б одну породу (або null, щоб скинути до карти)");
  }
  return { types, extra };
}

/** Збережене уточнення з БД (зіпсоване — ігноруємо, щоб аналіз не падав). */
export function parseStoredOverride(raw: unknown): ForestOverride | null {
  if (raw === null || raw === undefined) return null;
  try {
    return validateForestOverride(raw);
  } catch {
    return null;
  }
}

export function overrideToJson(o: ForestOverride): Record<string, unknown> {
  return {
    types: o.types.map((t) => ({ forest_type: t.forestType, species: t.species })),
    extra: o.extra.map((e) => ({ species: e.species, presence: e.presence })),
  };
}

/**
 * Для яких типів лісу рахувати прогноз. Без уточнення — 2 переважні типи з карти.
 * З уточненням — породи замість типів з карти (площа типу ділиться між обраними
 * породами), «переважає» — першою, «є місцями» — після решти; до 3 порід.
 */
export function forestRunTypes(forest: ForestSummary, override: ForestOverride | null): string[] {
  if (!override) {
    return forest.types
      .map((t) => t.forest_type)
      .filter((t): t is string => typeof t === "string" && t.length > 0)
      .slice(0, MAX_FOREST_RUNS);
  }
  const weight = new Map<string, number>();
  const add = (k: string, w: number) => weight.set(k, (weight.get(k) ?? 0) + w);
  for (const t of forest.types) {
    const refined = override.types.find((o) => o.forestType === t.forest_type);
    if (refined) {
      for (const sp of refined.species) add(sp, Number(t.km2) / refined.species.length);
    } else if (t.forest_type) {
      add(t.forest_type, Number(t.km2));
    }
  }
  for (const e of override.extra) add(e.species, e.presence === "dominant" ? Number.POSITIVE_INFINITY : 0);
  return [...weight.entries()].sort((a, b) => b[1] - a[1]).map(([k]) => k).slice(0, MAX_REFINED_RUNS);
}

export function forestEditBlock(used: number, limit = FOREST_EDITS_PER_DAY): Record<string, unknown> {
  return {
    used,
    limit,
    can_edit: used < limit,
    label: used < limit
      ? `Уточнити ліс сьогодні можна ще ${limit - used} ${limit - used === 1 ? "раз" : "рази"}`
      : "Сьогодні ліс уже уточнено двічі. Знову можна завтра.",
  };
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
  /** Дні прогнозу "YYYY-MM-DD" (сьогодні…горизонт) — один прогін рушія на тип лісу. */
  dates: string[];
  forestType: string | null;
  homeRegionId: number;
}

export interface AnalysisDeps {
  db: AnalysisDb;
  verify: TokenVerifier;
  /** Прогноз для центру ділянки з заданим типом лісу на кожен день `dates` (у тому ж порядку). */
  forecast: (input: AreaForecastInput) => Promise<ForecastResult[]>;
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

/** Нова ділянка з центром у точці або повторний аналіз збереженої. */
export type AnalysisTarget =
  | { kind: "create"; lat: number; lng: number; sizeKm: AnalysisSize }
  | { kind: "area"; areaId: string };

export interface AnalysisInput {
  target: AnalysisTarget;
  /** "YYYY-MM-DD" */
  date: string;
  /** Сирий `forest` із тіла — перевіряється, коли відомий розмір ділянки. */
  forestRaw: unknown;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

  let target: AnalysisTarget;
  if (obj.area_id !== undefined) {
    if (typeof obj.area_id !== "string" || !UUID_RE.test(obj.area_id)) {
      throw validationError("area_id — ідентифікатор ділянки");
    }
    if (obj.lat !== undefined || obj.lng !== undefined || obj.size_km !== undefined) {
      throw validationError("Ділянку не можна змінити: передайте або area_id, або lat/lng/size_km для нової");
    }
    target = { kind: "area", areaId: obj.area_id.toLowerCase() };
  } else {
    if (typeof obj.lat !== "number" || !Number.isFinite(obj.lat) || obj.lat < -90 || obj.lat > 90) {
      throw validationError("lat — широта від -90 до 90");
    }
    if (typeof obj.lng !== "number" || !Number.isFinite(obj.lng) || obj.lng < -180 || obj.lng > 180) {
      throw validationError("lng — довгота від -180 до 180");
    }
    if (!(ANALYSIS_SIZES as readonly unknown[]).includes(obj.size_km)) {
      throw validationError("size_km — 5 або 10");
    }
    target = { kind: "create", lat: obj.lat, lng: obj.lng, sizeKm: obj.size_km as AnalysisSize };
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

  if (target.kind === "create") validateForestHint(obj.forest, target.sizeKm); // рано — до створення ділянки
  return { target, date, forestRaw: obj.forest };
}

/** На скільки днів `date` пізніше за `today` (обидві — "YYYY-MM-DD"). */
export function daysAhead(date: string, today: string): number {
  return Math.round((Date.parse(`${date}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / DAY_MS);
}

/** Дні горизонту від [today]: ["YYYY-MM-DD", …]. */
export function horizonDates(today: string, count: number): string[] {
  const start = Date.parse(`${today}T00:00:00Z`);
  return Array.from({ length: count }, (_, i) => new Date(start + i * DAY_MS).toISOString().slice(0, 10));
}

const WEEKDAY_SHORT = ["Нд", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"];
const WEEKDAY_FULL = ["неділя", "понеділок", "вівторок", "середа", "четвер", "пʼятниця", "субота"];

/** «Сьогодні», «Завтра», «Сб 16». */
export function dayLabel(date: string, today: string): string {
  const ahead = daysAhead(date, today);
  if (ahead === 0) return "Сьогодні";
  if (ahead === 1) return "Завтра";
  const d = new Date(`${date}T00:00:00Z`);
  return `${WEEKDAY_SHORT[d.getUTCDay()]} ${d.getUTCDate()}`;
}

/** «сьогодні», «завтра», «субота» — для «Найкращий день: …». */
function dayName(date: string, today: string): string {
  const ahead = daysAhead(date, today);
  if (ahead === 0) return "сьогодні";
  if (ahead === 1) return "завтра";
  return WEEKDAY_FULL[new Date(`${date}T00:00:00Z`).getUTCDay()];
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

export function shapeForest(f: ForestSummary, override: ForestOverride | null = null): Record<string, unknown> {
  const refined = override !== null;
  return {
    summary_label: f.forest_km2 >= MIN_FOREST_KM2
      ? `Ліс займає ${km2Label(f.forest_km2)} з ${f.area_km2} км² ділянки`
      : "На карті в цій ділянці лісів немає",
    types: f.types.slice(0, 5).map((t) => {
      const style = forestTypeStyle(t.forest_type);
      const species = override?.types.find((o) => o.forestType === t.forest_type)?.species ?? [];
      return {
        forest_type: t.forest_type,
        type_label: style.label,
        type_color: style.color,
        area_label: km2Label(Number(t.km2)),
        age_label: t.stand_age_years ? `~${Math.round(Number(t.stand_age_years))} р.` : null,
        // Уточнення вручну (ADR-015 §15.6): «сосна, ялина · уточнено вами».
        species,
        species_label: species.length > 0 ? `${species.map((s) => SPECIES_LABEL[s]).join(", ")} · уточнено вами` : null,
      };
    }),
    extra: (override?.extra ?? []).map((e) => ({
      species: e.species,
      label: capitalize(SPECIES_LABEL[e.species]),
      presence: e.presence,
      presence_label: `${PRESENCE_LABEL[e.presence]} · уточнено вами`,
    })),
    refined,
    // Уточнення діє лише на цю ділянку; ліс на карті змінюють перевірені тук-туки (ADR-019).
    refine_note_label: refined
      ? "Уточнення діє лише для вашої ділянки. Знайдете тут гриб — зробіть тук-тук, і ліс уточниться для всіх."
      : null,
  };
}

// ─── Доступи й ліміти ──────────────────────────────────────────────────────

async function hasPro(deps: AnalysisDeps, user: AuthUser): Promise<boolean> {
  return deps.hasAnalysisPro ? await deps.hasAnalysisPro(user.id) : false;
}

/** Скільки ділянок можна мати: безкоштовно — 1, Pro — до 3 (ADR-015 §15.1). */
export const FREE_MAX_AREAS = 1;
export const PRO_MAX_AREAS = 3;
export const maxAreas = (pro: boolean) => (pro ? PRO_MAX_AREAS : FREE_MAX_AREAS);

export interface AreaRow {
  id: string;
  slot: number;
  size_km: number;
  center: unknown;
  last_result?: unknown;
  last_analyzed_at?: string | null;
  forest_override?: unknown;
}

async function loadAreas(db: AnalysisDb, userId: string): Promise<AreaRow[]> {
  const { data, error } = await db
    .from("analysis_areas")
    .select("id, slot, size_km, center, last_result, last_analyzed_at, forest_override")
    .eq("user_id", userId);
  if (error) dbFail("analysis_areas select", error);
  return ((data ?? []) as AreaRow[]).sort((a, b) => a.slot - b.slot);
}

async function forestEditsToday(db: AnalysisDb, userId: string, areaId: string): Promise<number> {
  const { data, error } = await db.rpc("forest_edits_today", { p_user_id: userId, p_area_id: areaId });
  if (error) dbFail("forest_edits_today", error);
  return Number(data ?? 0);
}

async function usedToday(db: AnalysisDb, userId: string, slot: number): Promise<number> {
  const { data, error } = await db.rpc("analysis_used_today", { p_user_id: userId, p_slot: slot });
  if (error) dbFail("analysis_used_today", error);
  return Number(data ?? 0);
}

function areaCenter(a: AreaRow): { lat: number; lng: number } | null {
  return typeof a.center === "string" ? parseEwkbPoint(a.center) : null;
}

/** Підказка, чи можна створити ще одну ділянку і що для цього зробити. */
export function createHint(count: number, pro: boolean): { can_create: boolean; create_hint_label: string } {
  const max = maxAreas(pro);
  if (count < max) {
    return { can_create: true, create_hint_label: "Торкніться карти, щоб обрати центр нової ділянки" };
  }
  return {
    can_create: false,
    create_hint_label: pro
      ? `У вас уже ${max} ділянки — це максимум. Щоб створити нову, видаліть одну з них у вкладці «Прогноз».`
      : "У вас уже є ділянка. Щоб створити нову, видаліть стару у вкладці «Прогноз». " +
        "У Pro — до 3 ділянок одночасно.",
  };
}

// ─── GET: що доступно і що вже збережено ───────────────────────────────────

async function getOverview(req: Request, user: AuthUser, deps: AnalysisDeps): Promise<Response> {
  const pro = await hasPro(deps, user);
  const limit = pro ? PRO_DAILY_LIMIT : FREE_DAILY_LIMIT;
  const areas = await loadAreas(deps.db, user.id);

  const shaped = [];
  for (const a of areas) {
    const point = areaCenter(a);
    if (!point) continue;
    shaped.push({
      id: a.id,
      slot: a.slot,
      lat: point.lat,
      lng: point.lng,
      size_km: a.size_km,
      size_label: sizeLabel(a.size_km),
      usage: usageBlock(await usedToday(deps.db, user.id, a.slot), limit),
      last_result: a.last_result ?? null,
      last_analyzed_at: a.last_analyzed_at ?? null,
      forest_override: (() => {
        const o = parseStoredOverride(a.forest_override);
        return o ? overrideToJson(o) : null;
      })(),
      forest_edit: forestEditBlock(await forestEditsToday(deps.db, user.id, a.id)),
    });
  }

  return ok({
    sizes: sizeOptions(pro),
    areas: shaped,
    ...createHint(areas.length, pro),
    // Зворотна сумісність: ліміт першої ділянки (старі збірки застосунку).
    usage: shaped[0]?.usage ?? usageBlock(0, limit),
    hint_label: "Торкніться карти, щоб обрати центр ділянки",
    forest_edit_options: forestEditOptions(),
  }, req);
}

// ─── DELETE: видалити ділянку ──────────────────────────────────────────────

async function deleteArea(req: Request, user: AuthUser, deps: AnalysisDeps, areaId: string): Promise<Response> {
  if (!UUID_RE.test(areaId)) throw new HttpError(404, "not_found", "Ділянку не знайдено");
  const { data, error } = await deps.db.rpc("delete_analysis_area", { p_user_id: user.id, p_area_id: areaId });
  if (error) dbFail("delete_analysis_area", error);
  if (data !== true) throw new HttpError(404, "not_found", "Ділянку не знайдено");
  return ok({ deleted: true }, req);
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


/** День у межах горизонту: безкоштовно — сьогодні + 2 дні, Pro — сьогодні + 6 днів. */
function assertInHorizon(date: string, today: string, pro: boolean): void {
  const ahead = daysAhead(date, today);
  if (ahead >= PRO_HORIZON_DAYS) {
    throw validationError(`Прогноз доступний на ${PRO_HORIZON_DAYS} днів, від сьогодні`);
  }
  if (!pro && ahead >= FREE_HORIZON_DAYS) {
    throw new HttpError(403, "pro_required", `Прогноз далі ніж на ${FREE_HORIZON_DAYS} дні доступний у Pro.`);
  }
}

async function assertInRegion(deps: AnalysisDeps, lat: number, lng: number, regionId: number): Promise<void> {
  const inRegion = await deps.db.rpc("point_in_region", { lat, lng, region_id: regionId });
  if (inRegion.error) dbFail("point_in_region", inRegion.error);
  if (inRegion.data !== true) {
    throw new HttpError(
      403,
      "outside_home_region",
      "Ділянка поза вашою областю. Аналіз доступний лише у своїй області.",
    );
  }
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
  const pro = await hasPro(deps, user);
  assertInHorizon(input.date, kyivToday(now), pro);
  const limit = pro ? PRO_DAILY_LIMIT : FREE_DAILY_LIMIT;
  const areas = await loadAreas(deps.db, user.id);

  let area: AreaRef;
  let used: number;
  let override: ForestOverride | null = null;

  if (input.target.kind === "area") {
    // Повторний аналіз збереженої ділянки — центр і розмір незмінні.
    const areaId = input.target.areaId;
    const row = areas.find((a) => a.id === areaId);
    const point = row ? areaCenter(row) : null;
    if (!row || !point) throw new HttpError(404, "not_found", "Ділянку не знайдено. Можливо, її видалено.");
    if (!pro && (row.size_km === PRO_SIZE_KM || row.slot > FREE_MAX_AREAS)) {
      throw new HttpError(403, "pro_required", "Ця ділянка доступна в Pro. Безкоштовно — одна ділянка 5×5 км.");
    }
    await assertInRegion(deps, point.lat, point.lng, regionId);
    used = await consume(deps, user.id, row.slot, limit, now);
    area = { id: row.id, slot: row.slot, lat: point.lat, lng: point.lng, sizeKm: row.size_km };
    override = parseStoredOverride(row.forest_override);
  } else {
    const t = input.target;
    await assertInRegion(deps, t.lat, t.lng, regionId);
    if (t.sizeKm === PRO_SIZE_KM && !pro) {
      throw new HttpError(403, "pro_required", "Ділянка 10×10 км доступна в Pro. Безкоштовно — ділянка 5×5 км.");
    }
    if (areas.length >= maxAreas(pro)) {
      throw new HttpError(409, "area_limit_reached", createHint(areas.length, pro).create_hint_label);
    }
    // Ліміт — на слот, який займе нова ділянка (найменший вільний), до її створення.
    const taken = new Set(areas.map((a) => a.slot));
    let slot = 1;
    while (taken.has(slot)) slot++;
    used = await consume(deps, user.id, slot, limit, now);

    const created = await deps.db.rpc("create_analysis_area", {
      p_user_id: user.id,
      p_max_slots: maxAreas(pro),
      p_lat: t.lat,
      p_lng: t.lng,
      p_size_km: t.sizeKm,
      p_region_id: regionId,
    });
    if (created.error) {
      await refund(deps, user.id, slot);
      dbFail("create_analysis_area", created.error);
    }
    const row = (Array.isArray(created.data) ? created.data[0] : created.data) as
      | { id: string; slot: number }
      | null
      | undefined;
    if (!row?.id) {
      // Паралельний запит зайняв останній слот.
      await refund(deps, user.id, slot);
      throw new HttpError(409, "area_limit_reached", createHint(maxAreas(pro), pro).create_hint_label);
    }
    area = { id: row.id, slot: Number(row.slot), lat: t.lat, lng: t.lng, sizeKm: t.sizeKm };
  }

  try {
    const data = await analyzeArea(deps, area, regionId, { date: input.date, now, pro }, input.forestRaw, override, usageBlock(used, limit));
    // Останній результат — разом із ділянкою (вкладка «Прогноз», інші пристрої).
    const saved = await deps.db.rpc("save_analysis_result", { p_user_id: user.id, p_area_id: area.id, p_result: data });
    if (saved.error) console.warn("[v1-analysis] save_analysis_result failed:", saved.error);
    return ok(data, req);
  } catch (err) {
    // Розрахунок не вдався — списаний аналіз повертаємо.
    await refund(deps, user.id, area.slot);
    if (err instanceof HttpError) throw err;
    console.error("[v1-analysis] analysis failed:", err);
    throw new HttpError(500, "internal_error", "Не вдалося виконати аналіз. Спробуйте ще раз.");
  }
}

interface AreaRef {
  id: string;
  slot: number;
  lat: number;
  lng: number;
  sizeKm: number;
}

/** Розрахунок аналізу ділянки (без списань і збереження). */
async function analyzeArea(
  deps: AnalysisDeps,
  area: AreaRef,
  regionId: number,
  when: { date: string; now: Date; pro: boolean },
  forestRaw: unknown,
  override: ForestOverride | null,
  usage: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const forestHint = validateForestHint(forestRaw, area.sizeKm);
  const forestRes = await deps.db.rpc("analyze_area_forest", {
    p_region_id: regionId,
    p_lat: area.lat,
    p_lng: area.lng,
    p_size_km: area.sizeKm,
  });
  if (forestRes.error || !forestRes.data) dbFail("analyze_area_forest", forestRes.error ?? "empty result");
  const forest = applyForestHint(forestRes.data as ForestSummary, forestHint);
  const hasForest = forest.forest_km2 >= MIN_FOREST_KM2;

  // Дні горизонту від сьогодні: один прогін рушія на тип лісу рахує всі дні.
  const today = kyivToday(when.now);
  const dates = horizonDates(today, horizonDays(when.pro));
  const locked = when.pro ? [] : horizonDates(today, PRO_HORIZON_DAYS).slice(dates.length);

  // Прогноз для переважних типів лісу (з уточненням — для обраних порід); лісів немає — лише погода.
  const forestTypes = forestRunTypes(forest, override);
  const runTypes: Array<string | null> = forestTypes.length > 0 ? forestTypes : [null];
  const runs: Array<{ forestType: string | null; results: ForecastResult[] }> = [];
  for (const forestType of runTypes) {
    const results = await deps.forecast({ lat: area.lat, lng: area.lng, dates, forestType, homeRegionId: regionId });
    if (results.length !== dates.length) throw new Error(`forecast returned ${results.length} days, expected ${dates.length}`);
    runs.push({ forestType, results });
  }

  const days = dates.map((date, i) => {
    const dayRuns = runs.map((r) => ({ forestType: r.forestType, result: r.results[i] }));
    return analyzeDay(date, today, dayRuns, hasForest);
  });
  const selected = days[Math.max(0, dates.indexOf(when.date))];

  const data: Record<string, unknown> = {
    area: {
      id: area.id,
      slot: area.slot,
      lat: area.lat,
      lng: area.lng,
      size_km: area.sizeKm,
      size_label: sizeLabel(area.sizeKm),
      bbox: forest.bbox,
    },
    date: selected.view.date,
    forest: shapeForest(forest, override),
    top1: selected.view.top1,
    alternative: selected.view.alternative,
    weather: selected.view.weather,
    warnings: selected.view.warnings,
    usage,
    days: days.map((d) => d.view),
    horizon_days: dates.length,
    best_day: bestDay(days, today),
    locked_days: locked.map((date) => ({ date, day_label: dayLabel(date, today) })),
    locked_label: locked.length > 0 ? `Ще ${locked.length} дні прогнозу — у Pro` : null,
  };
  if (selected.view.no_data_reason) data.no_data_reason = selected.view.no_data_reason;
  return data;
}

interface AnalyzedDay {
  view: Record<string, unknown> & { date: string; top1: unknown; alternative: unknown; weather: unknown; warnings: string[]; no_data_reason: string | null };
  /** Внутрішній порядок для «найкращого дня» — у відповідь не йде. */
  bestScore: number | null;
  level: ProbabilityLevel;
}

/** Один день смужки: найкращий вид і альтернатива серед типів лісу, погода дня. */
function analyzeDay(
  date: string,
  today: string,
  runs: Array<{ forestType: string | null; result: ForecastResult }>,
  hasForest: boolean,
): AnalyzedDay {
  const first = runs[0].result;
  // Лісу немає — лісові види не прогнозуємо (узгоджено з «лісів немає»).
  const best = hasForest ? pickBest(runs) : { top1: null, alternative: null };
  const top1 = shapeCandidate(best.top1, first);
  const level = top1 ? normalizeLevel(String(top1.level)) : "no_data";
  const ahead = daysAhead(date, today);
  const approximate = ahead >= APPROXIMATE_FROM_DAY;
  const w = weatherBlock(first.weather);
  const dayW = first.weather?.day;
  return {
    view: {
      date,
      day_label: dayLabel(date, today),
      approximate,
      approximate_label: approximate ? "Орієнтовно: погоду так далеко прогнозують менш точно" : null,
      level,
      level_label: LEVEL_LABEL[level],
      level_short_label: LEVEL_SHORT_LABEL[level],
      level_color: LEVEL_COLOR[level],
      top1,
      alternative: shapeCandidate(best.alternative, first),
      // Безкоштовно — базова погода: температура, вологість, опади (ADR-015 §15.1).
      weather: w
        ? {
          icon: dayW ? dayIcon(dayW.rain, dayW.humidity) : w.icon,
          day_label: dayW ? `${Math.round(dayW.tempMin)}…${Math.round(dayW.tempMax)}°, ${dayRainLabel(dayW.rain)}` : null,
          temp_label: w.temp_label,
          humidity_label: w.humidity_label,
          rain_label: w.rain_label,
        }
        : null,
      warnings: [...new Set(runs.flatMap((r) => r.result.warnings))],
      no_data_reason: !hasForest ? NO_FOREST_REASON : !best.top1 && first.noDataReason ? first.noDataReason : null,
    },
    bestScore: best.top1 ? best.top1.species.score : null,
    level,
  };
}

const NO_FOREST_REASON = "У цій ділянці на карті немає лісу, тож лісові гриби тут не прогнозуємо. " +
  "Видаліть ділянку й оберіть місце, де є ліс.";

/** Коротко для смужки днів. */
const LEVEL_SHORT_LABEL: Record<ProbabilityLevel, string> = {
  peak: "Пік", high: "Висока", medium: "Середня", low: "Низька", no_data: "—",
};

const dayIcon = (rain: number, humidity: number) => (rain >= 1 ? "rain" : humidity >= 80 ? "cloud" : "sun");
const dayRainLabel = (rain: number) => (rain >= 0.5 ? `опади ${Math.max(1, Math.round(rain))} мм` : "без опадів");

/** Найкращий день горизонту: найвищий рівень (від середнього), за рівності — раніший. */
export function bestDay(days: AnalyzedDay[], today: string): Record<string, unknown> | null {
  const RANK: Record<ProbabilityLevel, number> = { peak: 4, high: 3, medium: 2, low: 1, no_data: 0 };
  let best: AnalyzedDay | null = null;
  for (const d of days) {
    if (d.bestScore === null || RANK[d.level] < RANK.medium) continue;
    if (!best || RANK[d.level] > RANK[best.level] || (RANK[d.level] === RANK[best.level] && d.bestScore > best.bestScore! + 0.05)) {
      best = d;
    }
  }
  if (!best || days.length < 2) return null;
  return { date: best.view.date, label: `Найкращий день: ${dayName(best.view.date, today)}` };
}

// ─── PUT: уточнити ліс ділянки вручну (ADR-015 §15.6) ─────────────────────

async function editForest(
  req: Request,
  user: AuthUser,
  deps: AnalysisDeps,
  areaId: string,
  now: Date,
): Promise<Response> {
  if (!UUID_RE.test(areaId)) throw new HttpError(404, "not_found", "Ділянку не знайдено");
  const body = await readJson(req);
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw validationError("Тіло запиту має бути JSON-об'єктом");
  }
  const obj = body as Record<string, unknown>;
  if (!("override" in obj)) throw validationError("override — уточнення лісу або null (скинути до карти)");
  const override = validateForestOverride(obj.override);
  const { date } = validateAnalysisBody({ area_id: areaId, date: obj.date }, now);

  const regionId = requireHomeRegion(await loadHomeRegionId(deps.db, user.id));
  const pro = await hasPro(deps, user);
  assertInHorizon(date, kyivToday(now), pro);
  const areas = await loadAreas(deps.db, user.id);
  const row = areas.find((a) => a.id === areaId);
  const point = row ? areaCenter(row) : null;
  if (!row || !point) throw new HttpError(404, "not_found", "Ділянку не знайдено. Можливо, її видалено.");
  if (!pro && (row.size_km === PRO_SIZE_KM || row.slot > FREE_MAX_AREAS)) {
    throw new HttpError(403, "pro_required", "Ця ділянка доступна в Pro. Безкоштовно — одна ділянка 5×5 км.");
  }
  await assertInRegion(deps, point.lat, point.lng, regionId);
  const area: AreaRef = { id: row.id, slot: row.slot, lat: point.lat, lng: point.lng, sizeKm: row.size_km };
  validateForestHint(obj.forest, area.sizeKm); // до списання уточнення

  // Не частіше 2 разів на добу на ділянку; переаналіз ліміт аналізів не списує.
  const edits = await deps.db.rpc("consume_forest_edit", {
    p_user_id: user.id,
    p_area_id: area.id,
    p_limit: FOREST_EDITS_PER_DAY,
  });
  if (edits.error) dbFail("consume_forest_edit", edits.error);
  if (typeof edits.data !== "number") {
    throw new HttpError(
      429,
      "forest_edit_limit_reached",
      "Сьогодні ліс цієї ділянки вже уточнено двічі. Знову можна завтра (о 00:00 за київським часом).",
      { "Retry-After": String(secondsToKyivMidnight(now)) },
    );
  }

  try {
    const limit = pro ? PRO_DAILY_LIMIT : FREE_DAILY_LIMIT;
    const usage = usageBlock(await usedToday(deps.db, user.id, area.slot), limit);
    const data = await analyzeArea(deps, area, regionId, { date, now, pro }, obj.forest, override, usage);
    const saved = await deps.db.rpc("save_forest_override", {
      p_user_id: user.id,
      p_area_id: area.id,
      p_override: override ? overrideToJson(override) : null,
      p_result: data,
    });
    if (saved.error) dbFail("save_forest_override", saved.error);
    if (saved.data !== true) throw new HttpError(404, "not_found", "Ділянку не знайдено. Можливо, її видалено.");
    return ok({ ...data, forest_edit: forestEditBlock(edits.data) }, req);
  } catch (err) {
    // Уточнення не збереглося — списане повертаємо.
    try {
      const r = await deps.db.rpc("refund_forest_edit", { p_user_id: user.id, p_area_id: area.id });
      if (r.error) console.warn("[v1-analysis] refund_forest_edit failed:", r.error);
    } catch (refundErr) {
      console.warn("[v1-analysis] refund_forest_edit failed:", refundErr);
    }
    if (err instanceof HttpError) throw err;
    console.error("[v1-analysis] forest edit failed:", err);
    throw new HttpError(500, "internal_error", "Не вдалося уточнити ліс. Спробуйте ще раз.");
  }
}

async function refund(deps: AnalysisDeps, userId: string, slot: number): Promise<void> {
  try {
    const r = await deps.db.rpc("refund_analysis", { p_user_id: userId, p_slot: slot });
    if (r.error) console.warn("[v1-analysis] refund failed:", r.error);
  } catch (refundErr) {
    console.warn("[v1-analysis] refund failed:", refundErr);
  }
}

/** Списує один аналіз слоту; `429 analysis_limit_reached`, якщо добовий ліміт вичерпано. */
async function consume(
  deps: AnalysisDeps,
  userId: string,
  slot: number,
  limit: number,
  now: Date,
): Promise<number> {
  const { data, error } = await deps.db.rpc("consume_analysis", {
    p_user_id: userId,
    p_slot: slot,
    p_limit: limit,
  });
  if (error) dbFail("consume_analysis", error);
  if (typeof data !== "number") {
    throw new HttpError(
      429,
      "analysis_limit_reached",
      `Сьогодні використано всі ${limit} аналізів цієї ділянки. Ліміт оновиться о 00:00 за київським часом.`,
      { "Retry-After": String(secondsToKyivMidnight(now)) },
    );
  }
  return data;
}

/** `/v1-analysis/areas/{id}/forest` → id ділянки. */
function forestAreaIdFromPath(url: URL): string | null {
  const m = url.pathname.match(/\/v1-analysis\/areas\/([^/]+)\/forest\/?$/);
  return m ? decodeURIComponent(m[1]).toLowerCase() : null;
}

/** `/v1-analysis/areas/{id}` → id ділянки. */
function areaIdFromPath(url: URL): string | null {
  const m = url.pathname.match(/\/v1-analysis\/areas\/([^/]+)\/?$/);
  return m ? decodeURIComponent(m[1]).toLowerCase() : null;
}

export async function handleAnalysis(req: Request, deps: AnalysisDeps): Promise<Response> {
  assertMethod(req, ["GET", "POST", "PUT", "DELETE"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-analysis");
  const user = await requireUser(req, deps.verify);
  const now = deps.now ? deps.now() : new Date();

  if (req.method === "PUT") {
    const id = forestAreaIdFromPath(new URL(req.url));
    if (!id) throw new HttpError(404, "not_found", "Очікується /v1-analysis/areas/{id}/forest");
    return await editForest(req, user, deps, id, now);
  }
  if (req.method === "DELETE") {
    const id = areaIdFromPath(new URL(req.url));
    if (!id) throw new HttpError(404, "not_found", "Очікується /v1-analysis/areas/{id}");
    return await deleteArea(req, user, deps, id);
  }
  return req.method === "GET" ? await getOverview(req, user, deps) : await runAnalysis(req, user, deps, now);
}
