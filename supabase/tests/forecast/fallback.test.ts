import { assertEquals, assert } from 'jsr:@std/assert';
import { buildFallback, BASIC_FALLBACK_SPECIES } from '../../functions/_shared/forecast/fallback.ts';
import { matchSeason } from '../../functions/_shared/forecast/matchers.ts';
import type {
  SpeciesRule, ForecastContext, WeatherData, FeatureFlags,
} from '../../functions/_shared/forecast/types.ts';

// ─── Fixtures (дубль scorer.test.ts — тести самостійні) ────────

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

function basicRule(mushroomType: string, nameLat: string, overrides: Partial<SpeciesRule> = {}): SpeciesRule {
  return makeRule({
    id: `rule-${mushroomType}`,
    mushroomType,
    nameUa: 'X',
    nameLat,
    ...overrides,
  });
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
      forestType: null, forestConfirmed: false,
      homeRegionId: null,
    } as ForecastContext['input'],
    weather: makeWeather(),
    crowd: { verifiedPicks7d: 0, negativeReports7d: 0, indicatorSpecies: [] },
    wave: 'autumn',
    forestTypeUnknown: true,
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

// ─── канонізація каталогу ────────────────────────────────────
Deno.test('BASIC_FALLBACK_SPECIES: канонічні ID (не spp)', () => {
  assert(BASIC_FALLBACK_SPECIES.includes('russula_vesca'));
  assert(BASIC_FALLBACK_SPECIES.includes('lycoperdon_perlatum'));
  assert(BASIC_FALLBACK_SPECIES.includes('agaricus_campestris'));
  assert(!BASIC_FALLBACK_SPECIES.includes('russula_spp'));
  assert(!BASIC_FALLBACK_SPECIES.includes('lycoperdon_spp'));
});

// ─── сезонний фільтр (FIX 2.10) ──────────────────────────────
Deno.test('buildFallback: 0 сезонних видів → top1=null + noDataReason', () => {
  const ctx = makeCtx();
  const rules = [basicRule('russula_vesca', 'Russula vesca', { seasonStart: '01-01', seasonEnd: '01-31' })];
  const r = buildFallback(ctx, rules);
  assertEquals(r.top1, null);
  assertEquals(r.alternative, null);
  assertEquals(r.noDataReason, 'Немає даних для поточного сезону.');
  assertEquals(r.warnings[0], 'Поза сезоном активного плодоношення.');
  assertEquals(r.date, '2026-10-11');
  assertEquals(r.forest, 'Ліс: невідомо. Прогноз базовий.');
});

Deno.test('buildFallback: 1 сезонний вид → top1=він, alternative=null', () => {
  const ctx = makeCtx();
  const rules = [basicRule('russula_vesca', 'Russula vesca')];
  const r = buildFallback(ctx, rules);
  assertEquals(r.top1?.mushroom_type, 'russula_vesca');
  assertEquals(r.alternative, null);
  assert(r.top1 !== null && r.top1.score > 0);
  assert(r.warnings.some(w => w.includes('Уточніть тип лісу')));
  assertEquals(r.noDataReason, 'Жоден вид не пройшов фільтр. Показано базовий прогноз.');
});

Deno.test('buildFallback: 3 сезонні види → top1 + alternative', () => {
  const ctx = makeCtx();
  const rules = [
    basicRule('russula_vesca', 'Russula vesca'),
    basicRule('lycoperdon_perlatum', 'Lycoperdon perlatum'),
    basicRule('agaricus_campestris', 'Agaricus campestris'),
  ];
  const r = buildFallback(ctx, rules);
  assert(r.top1 !== null);
  assert(r.alternative !== null);
  assert(r.warnings.some(w => w.includes('Уточніть тип лісу')));
  assert(BASIC_FALLBACK_SPECIES.includes(r.top1!.mushroom_type));
  assert(BASIC_FALLBACK_SPECIES.includes(r.alternative!.mushroom_type));
});

Deno.test('buildFallback: не-fallback види відкидаються', () => {
  const ctx = makeCtx();
  const rules = [
    basicRule('russula_vesca', 'Russula vesca'),
    basicRule('lycoperdon_perlatum', 'Lycoperdon perlatum'),
    basicRule('agaricus_campestris', 'Agaricus campestris'),
    basicRule('boletus_edulis', 'Boletus edulis'),
  ];
  const r = buildFallback(ctx, rules);
  assert(r.top1 !== null && r.top1.mushroom_type !== 'boletus_edulis');
  assert(r.alternative !== null && r.alternative.mushroom_type !== 'boletus_edulis');
});

Deno.test('buildFallback: fallback-види проходять matchSeason у жовтні', () => {
  const ctx = makeCtx(); // 11.10.2026, wave=autumn
  const rules = [
    basicRule('russula_vesca', 'Russula vesca'),
    basicRule('lycoperdon_perlatum', 'Lycoperdon perlatum'),
    basicRule('agaricus_campestris', 'Agaricus campestris'),
  ];
  for (const rule of rules) {
    assertEquals(matchSeason(rule, ctx).hardFail, false);
  }
});

// ─── seasonality через флаг хвилі ────────────────────────────
Deno.test('buildFallback: зимова хвиля → усі базові види поза сезоном', () => {
  const ctx = makeCtx({ wave: 'spring' }); // базові фікстури мають waveSpring: false
  const rules = [
    basicRule('russula_vesca', 'Russula vesca'),
    basicRule('lycoperdon_perlatum', 'Lycoperdon perlatum'),
    basicRule('agaricus_campestris', 'Agaricus campestris'),
  ];
  const r = buildFallback(ctx, rules);
  assertEquals(r.top1, null);
  assertEquals(r.noDataReason, 'Немає даних для поточного сезону.');
});
