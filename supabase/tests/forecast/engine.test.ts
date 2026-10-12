import { assertEquals, assert } from 'jsr:@std/assert';
import { ForecastEngine } from '../../functions/_shared/forecast/engine.ts';
import type { ForecastDbClient } from '../../functions/_shared/forecast/context.ts';
import type { DbClient, RegionRow } from '../../functions/_shared/forecast/db.ts';
import type {
  SpeciesRule, ForecastInput, FeatureFlags,
} from '../../functions/_shared/forecast/types.ts';

// ─── Fixtures (дубль fallback.test.ts — тести самостійні) ────────

function makeRule(overrides: Partial<SpeciesRule> = {}): SpeciesRule {
  return {
    id: 'rule-1',
    legacyId: null,
    mushroomType: 'boletus_edulis',
    nameUa: 'Білий', nameLat: 'Boletus edulis',
    fruitingTempMin: 6, fruitingTempMax: 22,
    fruitingTempPeakMin: 12, fruitingTempPeakMax: 18,
    myceliumTempMin: null, myceliumTempMax: null,
    humidityMin: 60,
    rain1dMin: 1, rain2dMin: null, rain3dMin: 10,
    droughtDaysMin: null,
    daysAfterRainMin: null, daysAfterRainMax: null,
    waterloggedPenalty: 0.3, droughtThenRain: true,
    forestType: ['pine', 'spruce', 'oak'],
    habitatType: ['forest_floor'],
    reliefType: ['plain', 'hill'],
    altitudeMin: null, altitudeMax: null,
    soilPhMin: null, soilPhMax: null,
    lightPreference: null,
    standAgeMin: 20, standAgeMax: 100,
    prefersLowland: false, prefersHilltop: false,
    seasonStart: '06-01', seasonEnd: '10-31',
    waveSpring: false, waveSummer1: true, waveSummer2: true, waveAutumn: true, waveLate: false,
    peakWaves: ['autumn'], peakMonths: [9, 10],
    indicatorSpecies: [], shockRequired: false,
    microrefugiumDry: null, microrefugiumWet: null,
    regionIds: [], weight: 1.0, mvpStage: 'mvp',
    lastCalibratedAt: null,
    ...overrides,
  } as SpeciesRule;
}

const BOILETUS = makeRule();
const RUSSULA = makeRule({
  id: 'rule-2', mushroomType: 'russula_vesca',
  nameUa: 'Сироїжка', nameLat: 'Russula vesca', forestType: ['birch'],
});
const CHANTERELLE = makeRule({
  id: 'rule-3', mushroomType: 'cantharellus_cibarius',
  nameUa: 'Лисичка', nameLat: 'Cantharellus cibarius',
  forestType: ['birch'], peakWaves: ['summer2'],
  standAgeMin: null, standAgeMax: null,   // rule1 skip → лисичка сильніша
});
// поза сезоном → scoreSpecies → no_data (жорсткий фільтр кандидатів)
const JUNK = makeRule({
  id: 'rule-9', mushroomType: 'x_junk', nameLat: 'X junk',
  seasonStart: '01-01', seasonEnd: '01-31',
});

function makeFlags(overrides: Partial<FeatureFlags> = {}): FeatureFlags {
  return {
    fruiting_temp_buffer: 3,
    region_filter_enabled: true,
    auto_calibration_enabled: false,
    rule5_anti_double_counting_enabled: true,
    indicator_pidvyshen_enabled: false,
    pressure_enabled: false,
    light_enabled: false,
    relief_enabled: false,
    gdd_enabled: true,
    peak_wave_bonus_enabled: true,
    ...overrides,
  } as FeatureFlags;
}

const INPUT: ForecastInput = {
  lat: 50.45, lng: 30.52,
  date: new Date('2026-10-11T00:00:00Z'),
  forestType: null, forestConfirmed: false,
  homeRegionId: null,
} as ForecastInput;

const REGION: RegionRow = { id: 1, name: 'Київська', koatuu: null, katottg: null };

// ─── Mock DB: об'єднання ForecastDbClient + DbClient ─────────

interface MockOpts {
  rules: SpeciesRule[];
  region?: RegionRow | null;
  insideRegion?: boolean;
  picksCount?: number;
  negativesCount?: number;
}

function makeDbMock(opts: MockOpts) {
  const rpcCalls: { fn: string; params: Record<string, unknown> }[] = [];
  const db = {
    from(table: string) {
      const eqs: [string, unknown][] = [];
      const chain: Record<string, unknown> = {
        select() { return chain; },
        eq(col: string, val: unknown) { eqs.push([col, val]); return chain; },
        gte() { return chain; },
        order() { return chain; },
        then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
          if (table === 'expert_rules') {
            return Promise.resolve({ data: opts.rules.map(ruleToRow), error: null }).then(resolve, reject);
          }
          if (table === 'mushroom_picks') {
            const neg = eqs.some(([c, v]) => c === 'is_negative' && v === true);
            return Promise.resolve({
              count: neg ? (opts.negativesCount ?? 0) : (opts.picksCount ?? 0),
              error: null,
            }).then(resolve, reject);
          }
          return Promise.resolve({ data: null, error: null }).then(resolve, reject);
        },
        maybeSingle() {
          return Promise.resolve({ data: opts.region ?? null, error: null });
        },
      };
      return chain;
    },
    rpc(fn: string, params: Record<string, unknown>) {
      rpcCalls.push({ fn, params });
      if (fn === 'find_zone_by_point') {
        return Promise.resolve({
          data: {
            stand_age_years: 50, stand_age_source: 'test',
            stand_age_confidence: 0.9, relief_type: 'plain',
            light_type: null, forest_type: null,
          },
          error: null,
        });
      }
      if (fn === 'point_in_region') {
        return Promise.resolve({ data: opts.insideRegion === true, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return {
    db: db as unknown as ForecastDbClient & DbClient,
    rpcCalls,
  };
}

/** SpeciesRule (camelCase) → snake_case-рядок expert_rules (для rowToRule) */
function ruleToRow(rule: SpeciesRule): Record<string, unknown> {
  const row: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(rule)) {
    row[k.replace(/[A-Z]/g, (m) => `_${m.toLowerCase()}`)] = v;
  }
  return row;
}

// ─── Stub fetch (open-meteo): ContextBuilder → fetchWeather ──
// Реальні дані: temp 15, hum 70, rain3d 12, soil 0.3 → soilState normal,
// droughtDays 0, GDD=300. FIX 8.7a: GDD ігнорується → wave = calendar = autumn.

const HOURLY = 30 * 24;
const DAILY = 30;
// суми: last1=5, last2=8, last3=12, last7=20, last14=30, last30=50; усі ≥1 мм → drought 0
const DAILY_PRECIP = [
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, // 20
  2, 1, 1, 1, 1, 2, 2,                         // 10 → last14=30
  2, 2, 2, 2,                                  // 8
  4, 3, 5,                                      // 12 → last3=12, last7=20
];

function makeWeatherPayload() {
  const hourlyTime = Array.from({ length: HOURLY }, (_, i) => `h${i}`);
  const dailyTime = Array.from({ length: DAILY }, (_, i) => `d${i}`);
  return {
    hourly: {
      time: hourlyTime,
      temperature_2m: Array(HOURLY).fill(15),
      relative_humidity_2m: Array(HOURLY).fill(70),
      precipitation: Array(HOURLY).fill(0),
      pressure_msl: Array(HOURLY).fill(1013),
      soil_moisture_0_to_7cm: Array(HOURLY).fill(0.3),
    },
    daily: {
      time: dailyTime,
      temperature_2m_max: Array(DAILY).fill(20),
      temperature_2m_min: Array(DAILY).fill(10),
      precipitation_sum: DAILY_PRECIP,
    },
  };
}

// ─── Runner ─────────────────────────────────────────────────

type RunOverrides = {
  input?: Partial<ForecastInput>;
  flags?: Partial<FeatureFlags>;
} & Omit<MockOpts, "rules">;

async function runForecast(
  rules: SpeciesRule[],
  overrides: RunOverrides = {},
) {
  const { db, rpcCalls } = makeDbMock({ ...overrides, rules });
  const input = { ...INPUT, ...(overrides.input ?? {}) } as ForecastInput;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify(makeWeatherPayload()), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    )) as typeof globalThis.fetch;
  try {
    const result = await ForecastEngine.forecast(
      input,
      db,
      makeFlags(overrides.flags ?? {}),
    );
    return { result, rpcCalls };
  } finally {
    globalThis.fetch = originalFetch;
  }
}

// ─── 1–4. RegionGuard ───────────────────────────────────────

Deno.test('engine: RegionGuard flag off → не блокує (rpc не викликано)', async () => {
  const { result, rpcCalls } = await runForecast([BOILETUS, JUNK], {
    region: REGION,
    insideRegion: false,
    input: { homeRegionId: 1 },
    flags: { region_filter_enabled: false },
  });
  assert(result.top1 !== null);
  assert(!rpcCalls.some((c) => c.fn === 'point_in_region'));
});

Deno.test('engine: RegionGuard homeRegionId=null → пропускає з warning', async () => {
  const { result } = await runForecast([BOILETUS, JUNK], { insideRegion: false });
  assert(result.top1 !== null);
  assert(result.warnings.some((w) => w.includes('регіон')));
});

Deno.test('engine: RegionGuard region не знайдено → graceful skip', async () => {
  // regions = 0 рядків (seed у 9.1) — guard НЕ блокує
  const { result, rpcCalls } = await runForecast([BOILETUS, JUNK], {
    region: null,
    insideRegion: false,
    input: { homeRegionId: 1 },
  });
  assert(result.top1 !== null);
  assert(!rpcCalls.some((c) => c.fn === 'point_in_region'));
  assert(result.warnings.some((w) => w.includes('довіднику')));
});

Deno.test('engine: RegionGuard point_in_region=false → BLOCK', async () => {
  const { result, rpcCalls } = await runForecast([BOILETUS, JUNK], {
    region: REGION,
    insideRegion: false,
    input: { homeRegionId: 1 },
  });
  assertEquals(result.noDataReason, 'outside_home_region');
  assertEquals(result.top1, null);
  assertEquals(result.alternative, null);
  assertEquals(result.regionName, null);
  assertEquals(result.forest, '');
  assertEquals(result.warnings, ['Ви поза вашою областю.']);
  assert(rpcCalls.some((c) => c.fn === 'point_in_region'));
});

Deno.test('engine: RegionGuard point_in_region=true → проходить + regionName', async () => {
  const { result } = await runForecast([BOILETUS, JUNK], {
    region: REGION,
    insideRegion: true,
    input: { homeRegionId: 1 },
  });
  assert(result.top1 !== null);
  assertEquals(result.regionName, 'Київська'); // ContextBuilder читає regions.name
});

// ─── 5. Нормальний flow ─────────────────────────────────────

Deno.test('engine: нормальний flow — 3 rules → top1 + alternative', async () => {
  const { result } = await runForecast([BOILETUS, RUSSULA, JUNK]);
  assert(result.top1 !== null);
  assertEquals(result.top1.mushroom_type, 'boletus_edulis');
  // різні forestType (pine vs birch) → alternative = russula (Рівень 1)
  assert(result.alternative !== null);
  assertEquals(result.alternative.mushroom_type, 'russula_vesca');
  assert(result.warnings.some((w) => w.includes('міцні'))); // wave=autumn (8.7a: calendar only)
  assertEquals(result.date, '2026-10-11');
  assertEquals(result.forest, 'Ліс: невідомо. Прогноз базовий.');
});

// ─── 6. Fallback при 0 кандидатів ───────────────────────────

Deno.test('engine: 0 кандидатів → buildFallback (0 базових у rules)', async () => {
  const { result } = await runForecast([JUNK]);
  assertEquals(result.top1, null);
  assertEquals(result.noDataReason, 'Немає даних для поточного сезону.');
  assertEquals(result.forest, 'Ліс: невідомо. Прогноз базовий.');
});

// ─── 7. Anti-double (§12.5) ─────────────────────────────────

Deno.test('engine: anti-double — лисичка топ → білий −0.10', async () => {
  // білий: fruitingTempMin=13 → transition ×0.7 + humidityMin=85 (soft-miss −0.1),
  // щоб лисичка (autumn, clamp 1.0) була детерміновано вищою за білого
  const boletusTransition = makeRule({ fruitingTempMin: 13, humidityMin: 85 });

  const solo = await runForecast([boletusTransition, JUNK]);
  assertEquals(solo.result.top1?.mushroom_type, 'boletus_edulis');
  const scoreA = solo.result.top1!.score;

  const combined = await runForecast([boletusTransition, CHANTERELLE, JUNK]);
  assertEquals(combined.result.top1?.mushroom_type, 'cantharellus_cibarius');
  // alternative = білий (Рівень 1: pine vs birch); score −0.10 від solo
  assertEquals(combined.result.alternative?.mushroom_type, 'boletus_edulis');
  assert(
    Math.abs(combined.result.alternative!.score - (scoreA - 0.10)) < 1e-9,
    `alt=${combined.result.alternative!.score} solo=${scoreA}`,
  );

  // flag off → без штрафу
  const noPenalty = await runForecast([boletusTransition, CHANTERELLE, JUNK], {
    flags: { rule5_anti_double_counting_enabled: false },
  });
  assert(
    Math.abs(noPenalty.result.alternative!.score - scoreA) < 1e-9,
    `noPenalty=${noPenalty.result.alternative!.score} solo=${scoreA}`,
  );
});

// ─── 8. Forest string ───────────────────────────────────────

Deno.test('engine: forestType confirmed → forest = тип + вік', async () => {
  const { result } = await runForecast([BOILETUS, JUNK], {
    input: { forestType: 'pine', forestConfirmed: true },
  });
  assertEquals(result.forest, 'pine (підтверджено), 50 років');
});
