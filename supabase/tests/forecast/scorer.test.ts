import { assertEquals, assert } from 'jsr:@std/assert';
import { scoreSpecies, scoreAll, scoreToLevel } from '../../functions/_shared/forecast/scorer.ts';
import type {
  SpeciesRule, ForecastContext, WeatherData, FeatureFlags,
} from '../../functions/_shared/forecast/types.ts';

// ─── Fixtures (дубль matchers.test.ts — тести самостійні) ────
//
// Дефолтна фікстура (wave=autumn, peakWaves=['autumn']) дає від правил
// 8.4b + 8.7b: rule1 (вік 50) = 0, rule2 skip (droughtDays=0), rule3 = 0,
// rule4 = +0.15 (autumn, БЕЗ peak — 8.7b), rule5 skip, rule6 = 0,
// rule8 (норма) = 0  →  Σ = +0.15
// peak_wave_bonus (scorer) = +0.05 — керований flag peak_wave_bonus_enabled
//
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

function makeWeather(overrides: Partial<WeatherData> = {}): WeatherData {
  return {
    tempAvg7d: 15, tempAvg14d: 15, tempAvg20d: 15,
    tempMin: 10, tempMax: 20,
    humidity: 70, rain1d: 5, rain2d: 8, rain3d: 12,
    rain7d: 20, rain14d: 30, rain30d: 50,
    droughtDays: 0, daysAfterRain: 2,
    pressure: 1013, pressureTrend: 'stable',
    soilState: 'normal', gdd: 1200,
    fetchedAt: '2026-10-11T00:00:00Z', source: 'open-meteo',
    ...overrides,
  } as WeatherData;
}

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

function makeCtx(overrides: Partial<ForecastContext> = {}): ForecastContext {
  return {
    input: {
      lat: 50.45, lng: 30.52,
      date: new Date('2026-10-11T00:00:00Z'),
      forestType: 'pine', forestConfirmed: true,
      homeRegionId: null,
    } as ForecastContext['input'],
    weather: makeWeather(),
    crowd: { verifiedPicks7d: 0, negativeReports7d: 0, indicatorSpecies: [] },
    wave: 'autumn',
    forestTypeUnknown: false,
    standAgeUnknown: false,
    standAge: 50,
    standAgeConfidence: 0.9,
    reliefType: 'plain',
    lightType: null,
    config: makeFlags(),
    regionName: null,
    computedAt: '2026-10-11T00:00:00Z',
    ...overrides,
  } as ForecastContext;
}

// ─── hardFail (8.4b: level → 'no_data') ──────────────────────
Deno.test('scoreSpecies: hard fail (temp < min) → 0 / no_data', () => {
  const ctx = makeCtx({ weather: makeWeather({ tempAvg7d: 3 }) });
  const r = scoreSpecies(makeRule(), ctx);
  assertEquals(r.score, 0);
  assertEquals(r.probability, 'no_data');
  assert(r.missed.length > 0);
});

Deno.test('scoreSpecies: hard fail (season) → 0 / no_data', () => {
  const ctx = makeCtx({ wave: 'spring' }); // rule.waveSpring = false
  const r = scoreSpecies(makeRule(), ctx);
  assertEquals(r.score, 0);
  assertEquals(r.probability, 'no_data');
  assert(r.missed.length > 0);
});

// ─── 8.4b РІШЕННЯ 3: no_data ────────────────────────────────
Deno.test('scoreSpecies: weather unavailable → 0 / no_data', () => {
  const ctx = makeCtx({ weather: makeWeather({ source: 'unavailable' }) });
  const r = scoreSpecies(makeRule(), ctx);
  assertEquals(r.score, 0);
  assertEquals(r.probability, 'no_data');
  assert(r.matched.some(x => x.includes('Погода недоступна')));
});

// ─── ідеальний випадок ───────────────────────────────────────
Deno.test('scoreSpecies: всі матчери 1.0, soil 1.0 → 1.0 / peak', () => {
  // weather=1.0 потребує drought-trigger: 0.6 + peak 0.2 + humidity 0.05 + rain3d 0.05 + drought 0.15 = 1.05 → clamp
  const rule = makeRule({ droughtDaysMin: 7, droughtThenRain: true });
  const ctx = makeCtx({
    weather: makeWeather({ tempAvg7d: 15, droughtDays: 10, rain1d: 5 }),
  });
  const r = scoreSpecies(rule, ctx);
  // base 1.0 (bonus skipped: 1.0 не < 1.0) + rule2 +0.05 + rule4 +0.15 → clamp 1.0
  assertEquals(r.score, 1);
  assertEquals(r.probability, 'peak');
  assert(r.matched.length > 0);
  assertEquals(r.missed.length, 0);
});

// ─── soil multiplier (peak_wave_bonus off → ізоляція soil) ───
Deno.test('scoreSpecies: waterlogged penalty 0.3 → ×0.7', () => {
  // weather = 0.9 (peak+humidity+rain3d), season = 1.0, geo = 1.0
  // base = (1 + 1.5*0.9 + 1)/3.5 = 0.9571; × soil 0.7 = 0.67; + rule4 0.15 = 0.82
  // peak_wave_bonus вимкнено — ізолюємо саме soil-множник
  const ctx = makeCtx({
    weather: makeWeather({ soilState: 'waterlogged' }),
    config: makeFlags({ peak_wave_bonus_enabled: false }),
  });
  const r = scoreSpecies(makeRule(), ctx);
  assert(Math.abs(r.score - 0.82) < 0.001, `score=${r.score}`);
});

// ─── fruiting_temp_buffer ────────────────────────────────────
// wave=summer1 → season = 0.7 (peak month 10), rule4 = +0.05
Deno.test('scoreSpecies: transition zone (temp = min+1) → base × 0.7', () => {
  // rule без peak temp і без drought → weather = 0.7 за будь-якої t у [6,22]
  const rule = makeRule({
    fruitingTempPeakMin: null,
    fruitingTempPeakMax: null,
    droughtDaysMin: null,
  });
  const flags = makeFlags({ peak_wave_bonus_enabled: false });
  // base = (1 + 1.5*0.7 + 0.7)/3.5 = 0.78571
  const full = scoreSpecies(rule, makeCtx({
    wave: 'summer1',
    weather: makeWeather({ tempAvg7d: 15 }),
    config: flags,
  }));
  const transition = scoreSpecies(rule, makeCtx({
    wave: 'summer1',
    weather: makeWeather({ tempAvg7d: 7 }), // 7 = min+1 < min+3
    config: flags,
  }));
  // full: 0.78571 + rule4 0.05 = 0.83571; transition: 0.78571×0.7 + 0.05 = 0.60
  assert(Math.abs(full.score - 0.835714285) < 1e-6, `full=${full.score}`);
  assert(Math.abs(transition.score - 0.6) < 1e-6, `transition=${transition.score}`);
});

Deno.test('scoreSpecies: temp у повній зоні (min+3..max-3) → без множника', () => {
  const rule = makeRule({
    fruitingTempPeakMin: null,
    fruitingTempPeakMax: null,
    droughtDaysMin: null,
  });
  const ctx = makeCtx({
    wave: 'summer1',
    weather: makeWeather({ tempAvg7d: 12 }), // межа: min+3=9..max-3=19
    config: makeFlags({ peak_wave_bonus_enabled: false }),
  });
  const r = scoreSpecies(rule, ctx);
  assert(Math.abs(r.score - 0.835714285) < 1e-6, `score=${r.score}`);
});

// ─── peak wave bonus ─────────────────────────────────────────
Deno.test('scoreSpecies: peak wave bonus → +0.05', () => {
  // weather = 0.35 (humidity 50 −0.1, rain3d 5 −0.15), season = 1.0 (autumn peak)
  // base = (1 + 1.5*0.35 + 1)/3.5 = 0.72143
  const rule = makeRule({
    fruitingTempPeakMin: null,
    fruitingTempPeakMax: null,
    droughtDaysMin: null,
  });
  const weakWeather = { humidity: 50, rain3d: 5 };
  const withBonus = scoreSpecies(rule, makeCtx({ weather: makeWeather(weakWeather) }));
  // 0.72143 + bonus 0.05 + rule4 0.15 = 0.92143
  assert(Math.abs(withBonus.score - 0.921428571) < 1e-6, `score=${withBonus.score}`);

  const withoutBonus = scoreSpecies(rule, makeCtx({
    weather: makeWeather(weakWeather),
    config: makeFlags({ peak_wave_bonus_enabled: false }),
  }));
  // 0.72143 + rule4 0.15 = 0.87143
  assert(Math.abs(withoutBonus.score - 0.871428571) < 1e-6, `score=${withoutBonus.score}`);

  // різниця рівно бонус
  assert(Math.abs((withBonus.score - withoutBonus.score) - 0.05) < 1e-6);
});

Deno.test('scoreSpecies: peak bonus капується на 1.0', () => {
  // без drought-trigger: weather=0.9 → base=0.9571 → +0.05 = 1.0071 → cap 1.0
  // + rule4 0.15 = 1.15 → clamp 1.0
  const r = scoreSpecies(makeRule(), makeCtx());
  assertEquals(r.score, 1);
  assertEquals(r.probability, 'peak');
});

// ─── 8.4b: Rule 1 як дельта ──────────────────────────────────
Deno.test('scoreSpecies: молодий сосняк (rule1 +0.10) → фінальний скор +0.10', () => {
  // weather = 0.35, wave summer1 → season 0.7
  // base = (1 + 1.5*0.35 + 0.7)/3.5 = 0.63571; rule4 = +0.05
  const rule = makeRule({
    fruitingTempPeakMin: null,
    fruitingTempPeakMax: null,
    droughtDaysMin: null,
  });
  const flags = makeFlags({ peak_wave_bonus_enabled: false });
  const baseCtx = {
    wave: 'summer1',
    weather: makeWeather({ humidity: 50, rain3d: 5 }),
    config: flags,
  } as Partial<ForecastContext>;
  const young = scoreSpecies(rule, makeCtx({ ...baseCtx, standAge: 20 }));
  const old = scoreSpecies(rule, makeCtx({ ...baseCtx, standAge: 50 }));
  // young: 0.63571 + 0.05 + 0.10 = 0.78571; old: 0.63571 + 0.05 = 0.68571
  assert(Math.abs(young.score - 0.785714285) < 1e-6, `young=${young.score}`);
  assert(Math.abs(old.score - 0.685714285) < 1e-6, `old=${old.score}`);
  assert(Math.abs((young.score - old.score) - 0.10) < 1e-6);
});

// ─── 8.4b: where (Rule 3/8 override) ─────────────────────────
Deno.test('scoreSpecies: soil dry → where = microrefugiumDry', () => {
  const rule = makeRule({ microrefugiumDry: 'південний схил', microrefugiumWet: 'низина' });
  const ctx = makeCtx({ weather: makeWeather({ soilState: 'dry' }) });
  const r = scoreSpecies(rule, ctx);
  assertEquals(r.where, 'південний схил');
});

// ─── scoreToLevel ────────────────────────────────────────────
Deno.test('scoreToLevel: граничні значення', () => {
  assertEquals(scoreToLevel(0.29), 'no_data');
  assertEquals(scoreToLevel(0.30), 'low');
  assertEquals(scoreToLevel(0.49), 'low');
  assertEquals(scoreToLevel(0.50), 'medium');
  assertEquals(scoreToLevel(0.69), 'medium');
  assertEquals(scoreToLevel(0.70), 'high');
  assertEquals(scoreToLevel(0.89), 'high');
  assertEquals(scoreToLevel(0.90), 'peak');
  assertEquals(scoreToLevel(1.0), 'peak');
});

// ─── scoreAll ────────────────────────────────────────────────
Deno.test('scoreAll: скорує всі правила', () => {
  const good = makeRule();
  const bad = makeRule({ id: 'rule-2', mushroomType: 'x', seasonStart: '01-01', seasonEnd: '01-31' });
  const ctx = makeCtx(); // 11 жовтня — bad поза сезоном
  const all = scoreAll([good, bad], ctx);
  assertEquals(all.length, 2);
  assertEquals(all[0].mushroom_type, 'boletus_edulis');
  assertEquals(all[1].score, 0);
  assertEquals(all[1].probability, 'no_data');
});
