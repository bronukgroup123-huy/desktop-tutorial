import { assertEquals, assert } from 'jsr:@std/assert';
import { buildWhen, buildWarnings } from '../../functions/_shared/forecast/warnings.ts';
import type {
  SpeciesRule, ScoredSpecies, ForecastContext, WeatherData,
} from '../../functions/_shared/forecast/types.ts';

// ─── Fixtures ────────────────────────────────────────────────

function makeCtx(overrides: Partial<ForecastContext> = {}): ForecastContext {
  return {
    input: {
      lat: 50.45, lng: 30.52,
      date: new Date('2026-10-11T00:00:00Z'),
      forestType: null, forestConfirmed: false,
      homeRegionId: null,
    } as ForecastContext['input'],
    weather: { daysAfterRain: 7 } as WeatherData,
    crowd: { verifiedPicks7d: 0, negativeReports7d: 0, indicatorSpecies: [] },
    wave: 'autumn',
    forestTypeUnknown: false,
    standAgeUnknown: false,
    standAge: 50,
    standAgeConfidence: 0.9,
    reliefType: 'plain',
    lightType: null,
    config: {} as ForecastContext['config'],
    regionName: null,
    computedAt: '2026-10-11T00:00:00Z',
    ...overrides,
  } as ForecastContext;
}

function makeRule(overrides: Partial<SpeciesRule> = {}): SpeciesRule {
  return {
    id: 'rule-1',
    legacyId: null,
    mushroomType: 'boletus_edulis',
    nameUa: 'Білий', nameLat: 'Boletus edulis',
    fruitingTempMin: 6, fruitingTempMax: 22,
    fruitingTempPeakMin: null, fruitingTempPeakMax: null,
    myceliumTempMin: null, myceliumTempMax: null,
    humidityMin: null,
    rain1dMin: null, rain2dMin: null, rain3dMin: null,
    droughtDaysMin: null,
    daysAfterRainMin: 5, daysAfterRainMax: 9,
    waterloggedPenalty: null, droughtThenRain: false,
    forestType: [],
    habitatType: [],
    reliefType: [],
    altitudeMin: null, altitudeMax: null,
    soilPhMin: null, soilPhMax: null,
    lightPreference: null,
    standAgeMin: null, standAgeMax: null,
    prefersLowland: false, prefersHilltop: false,
    seasonStart: '06-01', seasonEnd: '10-31',
    waveSpring: false, waveSummer1: true, waveSummer2: true, waveAutumn: true, waveLate: false,
    peakWaves: [], peakMonths: [9, 10],
    indicatorSpecies: [], shockRequired: false,
    microrefugiumDry: null, microrefugiumWet: null,
    regionIds: [], weight: 1.0, mvpStage: 'mvp',
    lastCalibratedAt: null,
    ...overrides,
  } as SpeciesRule;
}

function makeScored(): ScoredSpecies {
  return {
    mushroom_type: 'boletus_edulis',
    name_ua: 'Білий',
    score: 0.8,
    probability: 'high',
    matched: [],
    missed: [],
    wave: 'autumn',
  } as ScoredSpecies;
}

// ─── buildWhen ───────────────────────────────────────────────
Deno.test('buildWhen: daysAfterRain у вікні → "Зараз"', () => {
  const ctx = makeCtx(); // daysAfterRain = 7
  assertEquals(buildWhen(ctx, makeRule()), 'Зараз — 7 днів після дощу');
});

Deno.test('buildWhen: дефолтне вікно 5–9 для rule без daysAfterRain', () => {
  const ctx = makeCtx(); // 7
  const rule = makeRule({ daysAfterRainMin: null, daysAfterRainMax: null });
  assertEquals(buildWhen(ctx, rule), 'Зараз — 7 днів після дощу');
});

Deno.test('buildWhen: вне вікна (3 дні), wave=autumn → осіння хвиля', () => {
  const ctx = makeCtx({
    weather: { daysAfterRain: 3 } as WeatherData,
    wave: 'autumn',
  });
  assertEquals(buildWhen(ctx, makeRule()), 'Весь період осінньої хвилі');
});

Deno.test('buildWhen: поза вікном, wave=late → пізня хвиля', () => {
  const ctx = makeCtx({
    weather: { daysAfterRain: 3 } as WeatherData,
    wave: 'late',
  });
  assertEquals(buildWhen(ctx, makeRule()), 'Пізня хвиля, до заморозків');
});

Deno.test('buildWhen: поза вікном, wave=spring → найближчі дні', () => {
  const ctx = makeCtx({
    weather: { daysAfterRain: 3 } as WeatherData,
    wave: 'spring',
  });
  assertEquals(buildWhen(ctx, makeRule()), 'Найближчі 2–4 дні');
});

Deno.test('buildWhen: вузьке вікна rule (1–2), 7 днів → хвильовий дефолт', () => {
  const ctx = makeCtx(); // 7, поза [1, 2]
  const rule = makeRule({ daysAfterRainMin: 1, daysAfterRainMax: 2 });
  assertEquals(buildWhen(ctx, rule), 'Весь період осінньої хвилі');
});

// ─── buildWarnings ───────────────────────────────────────────
Deno.test('buildWarnings: wave=summer2 → попередження про червивість', () => {
  const w = buildWarnings(makeScored(), makeCtx({ wave: 'summer2' }));
  assert(w.some(x => x.includes('червиві')));
});

Deno.test('buildWarnings: wave=autumn → міцні і чисті', () => {
  const w = buildWarnings(makeScored(), makeCtx({ wave: 'autumn' }));
  assert(w.some(x => x.includes('міцні')));
  assert(w.some(x => x.includes('заморозків')));
});

Deno.test('buildWarnings: forestTypeUnknown → Уточніть тип лісу', () => {
  const w = buildWarnings(makeScored(), makeCtx({ forestTypeUnknown: true }));
  assert(w.some(x => x.includes('Уточніть тип лісу')));
});

Deno.test('buildWarnings: звичайний стан (spring) → порожній список', () => {
  const w = buildWarnings(makeScored(), makeCtx({ wave: 'spring', forestTypeUnknown: false }));
  assertEquals(w, []);
});

Deno.test('buildWarnings: top1=null не ламає виклик', () => {
  const w = buildWarnings(null, makeCtx({ wave: 'summer2', forestTypeUnknown: true }));
  assertEquals(w.length, 2);
});
