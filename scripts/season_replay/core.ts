// ============================================================================
// Повтор сезону (BACKEND_PLAN B2.15, ADR-015 §15.7 п.6): справжній рушій прогнозу
// день за днем на погоді минулого сезону (архів Open-Meteo) або штучного сценарію.
//
// Без БД і без мережі: контекст збирається тут, оцінка — ForecastEngine.forecastFromContext
// і scoreAll, тобто та сама логіка, що й у застосунку. Числа score тут видно — це
// інструмент розробника, у застосунок вони не йдуть (Заборона №1 стосується відповідей API).
// ============================================================================

import { ForecastEngine } from "../../supabase/functions/_shared/forecast/engine.ts";
import { DEFAULT_FEATURE_FLAGS, type FeatureFlags } from "../../supabase/functions/_shared/forecast/flags.ts";
import { scoreAll } from "../../supabase/functions/_shared/forecast/scorer.ts";
import type {
  ForecastContext,
  ForestType,
  ProbabilityLevel,
  SpeciesRule,
} from "../../supabase/functions/_shared/forecast/types.ts";
import { detectWave } from "../../supabase/functions/_shared/forecast/wave.ts";
import { type WeatherSeries, weatherAsOf } from "../../supabase/functions/_shared/forecast/weather.ts";

export interface SpeciesDay {
  level: ProbabilityLevel;
  score: number;
  matched: string[];
  missed: string[];
}

export interface ReplayDay {
  date: string;
  wave: string;
  weather: { tmean: number; tmin: number; tmax: number; rain: number; rain7d: number; daysAfterRain: number; droughtDays: number; soil: string; humidity: number };
  top1: string | null;
  top1Level: ProbabilityLevel | null;
  alternative: string | null;
  species: Record<string, SpeciesDay>;
}

export interface ReplayRun {
  title: string;
  lat: number;
  lng: number;
  forestType: ForestType | null;
  days: ReplayDay[];
  /** mushroom_type → назва українською. */
  names: Record<string, string>;
  note?: string;
}

/** Дні від [from] до [to] включно ("YYYY-MM-DD"). */
export function dateRange(from: string, to: string): string[] {
  const out: string[] = [];
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= Date.parse(`${to}T00:00:00Z`); t += 86_400_000) {
    out.push(new Date(t).toISOString().slice(0, 10));
  }
  return out;
}

/** Контекст рушія на день [date] — як у ContextBuilder, але з готової погоди. */
export function contextFor(
  series: WeatherSeries,
  date: string,
  lat: number,
  lng: number,
  forestType: ForestType | null,
  flags: FeatureFlags = DEFAULT_FEATURE_FLAGS,
): ForecastContext {
  const day = new Date(`${date}T00:00:00Z`);
  return {
    input: { lat, lng, date: day, forestType, forestConfirmed: forestType !== null, homeRegionId: null },
    weather: weatherAsOf(series, date),
    crowd: { verifiedPicks7d: 0, negativeReports7d: 0, indicatorSpecies: [] },
    wave: detectWave(day, lat, 0),
    forestTypeUnknown: forestType === null,
    standAgeUnknown: true,
    standAge: null,
    standAgeConfidence: 0,
    reliefType: null,
    lightType: null,
    cumulativeGdd: 0,
    config: flags,
    regionName: null,
    computedAt: new Date(0).toISOString(),
  };
}

/** Прогін рушія по днях [dates] для одного типу лісу. */
export function replay(
  title: string,
  series: WeatherSeries,
  dates: string[],
  lat: number,
  lng: number,
  forestType: ForestType | null,
  rules: SpeciesRule[],
  flags: FeatureFlags = DEFAULT_FEATURE_FLAGS,
): ReplayRun {
  const days = dates.map((date): ReplayDay => {
    const ctx = contextFor(series, date, lat, lng, forestType, flags);
    const result = ForecastEngine.forecastFromContext(ctx, rules);
    const species: Record<string, SpeciesDay> = {};
    for (const s of scoreAll(rules, ctx)) {
      species[s.mushroom_type] = { level: s.probability, score: Math.round(s.score * 100) / 100, matched: s.matched, missed: s.missed };
    }
    const w = ctx.weather;
    return {
      date,
      wave: ctx.wave,
      weather: {
        tmean: round1((w.day?.tempMin ?? 0) / 2 + (w.day?.tempMax ?? 0) / 2),
        tmin: round1(w.day?.tempMin ?? 0),
        tmax: round1(w.day?.tempMax ?? 0),
        rain: round1(w.day?.rain ?? 0),
        rain7d: round1(w.rain7d),
        daysAfterRain: w.daysAfterRain,
        droughtDays: w.droughtDays,
        soil: w.soilState,
        humidity: Math.round(w.humidity),
      },
      top1: result.top1?.mushroom_type ?? null,
      top1Level: result.top1?.probability ?? null,
      alternative: result.alternative?.mushroom_type ?? null,
      species,
    };
  });
  return { title, lat, lng, forestType, days, names: Object.fromEntries(rules.map((r) => [r.mushroomType, r.nameUa])) };
}

const round1 = (v: number) => Math.round(v * 10) / 10;

// ─── Штучні сценарії ─────────────────────────────────────────────────────────

/** Відрізок сценарію: [days] днів з однаковою погодою; rain — мм на день (або по днях). */
export interface Segment {
  days: number;
  t: number;
  rain?: number | number[];
  humidity?: number;
  soil?: number;
  /** Плавно змінювати температуру до цього значення в кінці відрізка. */
  tTo?: number;
}

/** Ряд погоди зі сценарію: дні від [start], кожен відрізок — підряд. */
export function scenarioSeries(start: string, segments: Segment[]): WeatherSeries {
  const tmean: number[] = [], precip: number[] = [], humidity: number[] = [], soil: number[] = [];
  for (const seg of segments) {
    for (let i = 0; i < seg.days; i++) {
      const t = seg.tTo === undefined ? seg.t : seg.t + (seg.tTo - seg.t) * (seg.days === 1 ? 1 : i / (seg.days - 1));
      tmean.push(t);
      precip.push(Array.isArray(seg.rain) ? seg.rain[i] ?? 0 : seg.rain ?? 0);
      humidity.push(seg.humidity ?? 75);
      soil.push(seg.soil ?? 0.3);
    }
  }
  const n = tmean.length;
  const dates = dateRange(start, new Date(Date.parse(`${start}T00:00:00Z`) + (n - 1) * 86_400_000).toISOString().slice(0, 10));
  return {
    version: 2,
    dates,
    today: dates[0],
    precip,
    tmax: tmean.map((t) => t + 5),
    tmin: tmean.map((t) => t - 5),
    tmean,
    humidity,
    soil,
    pressureStart: Array(n).fill(1013),
    pressureEnd: Array(n).fill(1013),
    fetchedAt: new Date(0).toISOString(),
  };
}

export interface Scenario {
  id: string;
  title: string;
  /** Що мав би показати добрий прогноз — для читача звіту. */
  expectation: string;
  lat: number;
  forestType: ForestType;
  start: string;
  /** Перші 30 днів — «передісторія» для вікон погоди; звіт — з [showFrom]. */
  showFrom: string;
  segments: Segment[];
}

const every = (n: number, days: number, mm: number) => Array.from({ length: days }, (_, i) => (i % n === n - 1 ? mm : 0));

export const SCENARIOS: Scenario[] = [
  {
    id: "september_peak",
    title: "Вересневий пік: посуха → злива 25 мм → тепла волога осінь",
    expectation: "Білий і лисичка — низько до зливи, підйом через 5–9 днів після неї, тримається 1–2 тижні.",
    lat: 50.25, forestType: "pine",
    start: "2025-08-05", showFrom: "2025-08-25",
    segments: [
      { days: 30, t: 20, rain: 0, humidity: 60, soil: 0.18 },
      { days: 1, t: 17, rain: 25, humidity: 90, soil: 0.35 },
      { days: 1, t: 15, rain: 8, humidity: 90, soil: 0.38 },
      { days: 30, t: 14, rain: every(4, 30, 3), humidity: 82, soil: 0.34 },
    ],
  },
  {
    id: "june_wave",
    title: "Червнева хвиля: тепло, два дощі на початку червня",
    expectation: "Перша літня хвиля (білий, сироїжки) через ~1 тиждень після дощів.",
    lat: 50.25, forestType: "deciduous",
    start: "2025-05-01", showFrom: "2025-05-25",
    segments: [
      { days: 34, t: 16, tTo: 18, rain: every(5, 34, 2), humidity: 70, soil: 0.25 },
      { days: 2, t: 18, rain: [14, 10], humidity: 90, soil: 0.36 },
      { days: 25, t: 19, rain: every(6, 25, 3), humidity: 76, soil: 0.32 },
    ],
  },
  {
    id: "drought_heat",
    title: "Посуха і спека в липні",
    expectation: "Лісові гриби — низько або «недостатньо даних» увесь період.",
    lat: 50.25, forestType: "pine",
    start: "2025-06-20", showFrom: "2025-07-15",
    segments: [{ days: 56, t: 27, rain: 0, humidity: 42, soil: 0.1 }],
  },
  {
    id: "waterlogged",
    title: "Перезволоження: 10 днів зливи в серпні",
    expectation: "Рівень не росте попри дощі (занадто сиро), після підсихання — відновлення.",
    lat: 50.25, forestType: "mixed",
    start: "2025-07-10", showFrom: "2025-08-01",
    segments: [
      { days: 30, t: 19, rain: every(4, 30, 4), humidity: 75, soil: 0.3 },
      { days: 10, t: 17, rain: 16, humidity: 96, soil: 0.9 },
      { days: 21, t: 18, rain: every(5, 21, 2), humidity: 80, soil: 0.4 },
    ],
  },
  {
    id: "frost",
    title: "Пізня осінь: похолодання до заморозків",
    expectation: "Білий і лисичка згасають; опеньки й зимові опеньки тримаються довше, при морозі — нуль.",
    lat: 50.25, forestType: "deciduous",
    start: "2025-09-25", showFrom: "2025-10-20",
    segments: [{ days: 57, t: 11, tTo: -3, rain: every(4, 57, 4), humidity: 85, soil: 0.35 }],
  },
  {
    id: "spring",
    title: "Весна: потепління квітня",
    expectation: "Зморшки й строчки з'являються при прогріванні ґрунту, літні види — ні.",
    lat: 50.25, forestType: "deciduous",
    start: "2025-03-05", showFrom: "2025-04-01",
    segments: [{ days: 57, t: 4, tTo: 15, rain: every(3, 57, 4), humidity: 78, soil: 0.34 }],
  },
];

/** Прогін сценарію. */
export function runScenario(s: Scenario, rules: SpeciesRule[], flags: FeatureFlags = DEFAULT_FEATURE_FLAGS): ReplayRun {
  const series = scenarioSeries(s.start, s.segments);
  const dates = series.dates.filter((d) => d >= s.showFrom);
  return { ...replay(s.title, series, dates, s.lat, 30.0, s.forestType, rules, flags), note: s.expectation };
}
