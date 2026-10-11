import { assertEquals, assert } from 'jsr:@std/assert';
import {
  matchGeo, matchWeather, matchSeason, matchSoil,
} from '../../functions/_shared/forecast/matchers.ts';
import type {
  SpeciesRule, ForecastContext, WeatherData, FeatureFlags,
} from '../../functions/_shared/forecast/types.ts';

// ─── Fixtures ────────────────────────────────────────────────
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

// ─── matchGeo ────────────────────────────────────────────────
Deno.test('matchGeo: forest match → score 1', () => {
  const r = matchGeo(makeRule(), makeCtx());
  assertEquals(r.hardFail, false);
  assertEquals(r.score, 1);
});

Deno.test('matchGeo: forest mismatch (confirmed) → hard fail', () => {
  const ctx = makeCtx({ input: { ...makeCtx().input, forestType: 'birch' } });
  const r = matchGeo(makeRule(), ctx);
  assertEquals(r.hardFail, true);
});

Deno.test('matchGeo: forest not confirmed → passthrough', () => {
  const ctx = makeCtx({ input: { ...makeCtx().input, forestConfirmed: false, forestType: null } });
  const r = matchGeo(makeRule(), ctx);
  assertEquals(r.hardFail, false);
  assertEquals(r.score, 1);
});

Deno.test('matchGeo: stand age out of range → ×0.5', () => {
  const ctx = makeCtx({ standAge: 5 });
  const r = matchGeo(makeRule(), ctx);
  assertEquals(r.hardFail, false);
  assertEquals(r.score, 0.5);
});

Deno.test('matchGeo: relief match (flag on) → без штрафу', () => {
  const ctx = makeCtx({ config: makeFlags({ relief_enabled: true }) });
  const r = matchGeo(makeRule(), ctx);
  assertEquals(r.hardFail, false);
  assertEquals(r.score, 1);
});

Deno.test('matchGeo: relief soft-miss (flag on) → ×0.7', () => {
  const ctx = makeCtx({
    reliefType: 'valley',
    config: makeFlags({ relief_enabled: true }),
  });
  const r = matchGeo(makeRule(), ctx);
  assertEquals(r.hardFail, false);
  assertEquals(r.score, 0.7);
});

Deno.test('matchGeo: relief flag off → relief ігнорується', () => {
  const ctx = makeCtx({ reliefType: 'valley' });
  const r = matchGeo(makeRule(), ctx);
  assertEquals(r.score, 1);
});

// ─── matchWeather ────────────────────────────────────────────
Deno.test('matchWeather: temp below min → hard fail', () => {
  const r = matchWeather(makeRule(), makeWeather({ tempAvg7d: 3 }));
  assertEquals(r.hardFail, true);
});

Deno.test('matchWeather: temp above max → hard fail', () => {
  const r = matchWeather(makeRule(), makeWeather({ tempAvg7d: 25 }));
  assertEquals(r.hardFail, true);
});

Deno.test('matchWeather: in peak temp → bonus', () => {
  const r = matchWeather(makeRule(), makeWeather({ tempAvg7d: 15 }));
  assertEquals(r.hardFail, false);
  assert(r.score > 0.6);
});

Deno.test('matchWeather: drought + no rain → penalty', () => {
  const rule = makeRule({ droughtDaysMin: 7, droughtThenRain: false });
  // tempAvg7d=8 — у fruiting range [6,22], але поза peak [12,18] (без peak-бонусу)
  const r = matchWeather(rule, makeWeather({ tempAvg7d: 8, droughtDays: 10, rain1d: 0 }));
  assert(r.score < 0.6, `score=${r.score}`);
  assert(r.reasons.some(x => x.includes('drought')));
});

Deno.test('matchWeather: drought → rain trigger → bonus', () => {
  const rule = makeRule({ droughtDaysMin: 7, droughtThenRain: true });
  const r = matchWeather(rule, makeWeather({ droughtDays: 10, rain1d: 6 }));
  assert(r.score > 0.6);
});

Deno.test('matchWeather: shock required + tempMin<5 → bonus', () => {
  const rule = makeRule({ shockRequired: true });
  const r = matchWeather(rule, makeWeather({ tempMin: 2 }));
  assert(r.reasons.some(x => x.includes('shock')));
});

Deno.test('matchWeather: weather unavailable → passthrough 1.0', () => {
  const r = matchWeather(makeRule(), makeWeather({ source: 'unavailable' }));
  assertEquals(r.hardFail, false);
  assertEquals(r.score, 1.0);
});

// ─── matchSeason ─────────────────────────────────────────────
Deno.test('matchSeason: wave not allowed → hard fail', () => {
  const ctx = makeCtx({ wave: 'spring' }); // rule.waveSpring = false
  const r = matchSeason(makeRule(), ctx);
  assertEquals(r.hardFail, true);
});

Deno.test('matchSeason: 11 жовтня в сезоні + peak wave + peak month → високий score', () => {
  const ctx = makeCtx({ wave: 'autumn' });
  const r = matchSeason(makeRule(), ctx);
  assertEquals(r.hardFail, false);
  assert(r.score >= 0.9, `score=${r.score}`);
});

Deno.test('matchSeason: 15 листопада — поза сезоном → hard fail', () => {
  const ctx = makeCtx({
    wave: 'late', // rule.waveLate = false → спочатку впаде на wave
    input: { ...makeCtx().input, date: new Date('2026-11-15T00:00:00Z') },
  });
  const r = matchSeason(makeRule(), ctx);
  assertEquals(r.hardFail, true);
});

Deno.test('matchSeason: wave allowed, але дата поза сезоном → hard fail', () => {
  // 15 листопада: waveLate=false завжди hard-fail; тестуємо саме сезонність:
  // 2 травня (spring disallowed) не підходить → беремо summer1 15 червня, сезон 06-01..10-31
  const rule = makeRule({ waveSpring: true, waveSummer1: true });
  const ctx = makeCtx({
    wave: 'summer1',
    input: { ...makeCtx().input, date: new Date('2026-05-15T00:00:00Z') },
  });
  const r = matchSeason(rule, ctx);
  assertEquals(r.hardFail, true);
});

// ─── matchSoil ───────────────────────────────────────────────
Deno.test('matchSoil: waterlogged → множник (1 − penalty)', () => {
  const r = matchSoil(makeRule(), makeWeather({ soilState: 'waterlogged' }));
  assert(Math.abs(r.score - 0.7) < 0.001);
});

Deno.test('matchSoil: dry → 0.7', () => {
  const r = matchSoil(makeRule(), makeWeather({ soilState: 'dry' }));
  assertEquals(r.score, 0.7);
});

Deno.test('matchSoil: normal → 1.0', () => {
  const r = matchSoil(makeRule(), makeWeather({ soilState: 'normal' }));
  assertEquals(r.score, 1.0);
});

Deno.test('matchSoil: weather unavailable → 1.0 passthrough', () => {
  const r = matchSoil(makeRule(), makeWeather({ source: 'unavailable' }));
  assertEquals(r.score, 1.0);
});
