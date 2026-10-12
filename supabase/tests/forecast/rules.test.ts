import { assertEquals, assert } from 'jsr:@std/assert';
import {
  rule1_StandAge,
  rule2_DroughtThenRain,
  rule3_MicrorefugiumBoletus,
  rule4_Waves,
  rule5_Indicators,
  rule6_MyceliumTemp,
  rule8_SeasonMicrorefugium,
  MVP_RULES,
} from '../../functions/_shared/forecast/rules.ts';
import type {
  SpeciesRule, ForecastContext, WeatherData, FeatureFlags,
} from '../../functions/_shared/forecast/types.ts';

// ─── Fixtures (дубль — тести самостійні) ─────────────────────
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

function makeFlags(): FeatureFlags {
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

// ─── Rule 1 — Вік деревостану ────────────────────────────────
Deno.test('rule1: білий, сосняк 10–30 → +0.10', () => {
  const r = rule1_StandAge(makeRule(), makeCtx({ standAge: 20 }));
  assertEquals(r.skip, undefined);
  assertEquals(r.modifier, 0.10);
  assert(r.reason?.includes('Молодий сосняк'));
});

Deno.test('rule1: standAgeUnknown → skip', () => {
  const r = rule1_StandAge(makeRule(), makeCtx({ standAgeUnknown: true, standAge: null }));
  assertEquals(r.skip, true);
});

Deno.test('rule1: білий, деревостан 50+ → −0.05', () => {
  const r = rule1_StandAge(makeRule(), makeCtx({ standAge: 80 }));
  assertEquals(r.modifier, -0.05);
});

Deno.test('rule1: лисичка, березняк 41–60 → +0.15', () => {
  const rule = makeRule({ mushroomType: 'cantharellus_cibarius' });
  const r = rule1_StandAge(rule, makeCtx({ standAge: 50 }));
  assertEquals(r.modifier, 0.15);
});

// ─── Rule 2 — Дощ після посухи ───────────────────────────────
Deno.test('rule2: посуха 15д + дощ 12мм + вікно 7д, normal → +0.20', () => {
  const rule = makeRule({ droughtThenRain: true, rain1dMin: 10, daysAfterRainMin: 5, daysAfterRainMax: 9 });
  const ctx = makeCtx({
    weather: makeWeather({ droughtDays: 15, rain1d: 12, daysAfterRain: 7, soilState: 'normal' }),
  });
  const r = rule2_DroughtThenRain(rule, ctx);
  assertEquals(r.skip, undefined);
  assertEquals(r.modifier, 0.20);
  assert(r.reason?.includes('посухи'));
});

Deno.test('rule2: те ж умови + waterlogged → −0.30', () => {
  const rule = makeRule({ droughtThenRain: true, rain1dMin: 10, daysAfterRainMin: 5, daysAfterRainMax: 9 });
  const ctx = makeCtx({
    weather: makeWeather({ droughtDays: 15, rain1d: 12, daysAfterRain: 7, soilState: 'waterlogged' }),
  });
  const r = rule2_DroughtThenRain(rule, ctx);
  assertEquals(r.modifier, -0.30);
});

Deno.test('rule2: droughtThenRain=false → skip', () => {
  const r = rule2_DroughtThenRain(makeRule({ droughtThenRain: false }), makeCtx());
  assertEquals(r.skip, true);
});

Deno.test('rule2: мало днів посухи → skip', () => {
  const rule = makeRule({ droughtThenRain: true, droughtDaysMin: 14 });
  const ctx = makeCtx({ weather: makeWeather({ droughtDays: 3 }) });
  const r = rule2_DroughtThenRain(rule, ctx);
  assertEquals(r.skip, true);
});

Deno.test('rule2: дощ був, вікно не оптимальне → +0.05', () => {
  const rule = makeRule({ droughtThenRain: true, rain1dMin: 10 });
  const ctx = makeCtx({
    weather: makeWeather({ droughtDays: 15, rain1d: 12, daysAfterRain: 2 }),
  });
  const r = rule2_DroughtThenRain(rule, ctx);
  assertEquals(r.modifier, 0.05);
});

// ─── Rule 3 — Мікрорефугіум білого ───────────────────────────
Deno.test('rule3: білий + soil dry → overrideWhere = microrefugiumDry', () => {
  const rule = makeRule({ microrefugiumDry: 'південний схил' });
  const r = rule3_MicrorefugiumBoletus(rule, makeCtx({
    weather: makeWeather({ soilState: 'dry' }),
  }));
  assertEquals(r.modifier, 0);
  assertEquals(r.overrideWhere, 'південний схил');
});

Deno.test('rule3: лисичка → skip', () => {
  const rule = makeRule({ mushroomType: 'cantharellus_cibarius', microrefugiumDry: 'схил' });
  const r = rule3_MicrorefugiumBoletus(rule, makeCtx({
    weather: makeWeather({ soilState: 'dry' }),
  }));
  assertEquals(r.skip, true);
});

Deno.test('rule3: білий + прохолода (tempAvg7d < tempAvg14d−3) → overrideWhere', () => {
  const rule = makeRule({ microrefugiumDry: 'захисний схил' });
  const ctx = makeCtx({
    weather: makeWeather({ tempAvg7d: 10, tempAvg14d: 15, soilState: 'normal' }),
  });
  const r = rule3_MicrorefugiumBoletus(rule, ctx);
  assertEquals(r.overrideWhere, 'захисний схил');
});

// ─── Rule 4 — Хвиля ──────────────────────────────────────────
Deno.test('rule4: autumn (peak) → +0.15 (без peak-бонусу — він у scorer.ts, 8.7b)', () => {
  const r = rule4_Waves(makeRule(), makeCtx({ wave: 'autumn' }));
  assertEquals(r.modifier, 0.15);
  // FIX 8.7b: reason більше не містить "+ peak" — peak-бонус тільки у scorer.ts
  assert(!r.reason?.includes('+ peak'));
});

Deno.test('rule4: autumn з peakWaves=[\'autumn\'] → modifier 0.15 (регресія 8.7b)', () => {
  // Фіксує: peak-гілка (+0.05) видалена з rule4 назавжди.
  // Раніше було 0.20 (0.15 + 0.05 peak) — дублювало scorer bonus.
  const rule = makeRule({ peakWaves: ['autumn'] });
  const r = rule4_Waves(rule, makeCtx({ wave: 'autumn' }));
  assertEquals(r.modifier, 0.15);
  assertEquals(r.reason, 'Осіння хвиля (пік)');
});

Deno.test('rule4: spring, peakWaves=[] → +0.05', () => {
  const r = rule4_Waves(makeRule({ peakWaves: [] }), makeCtx({ wave: 'spring' }));
  assertEquals(r.modifier, 0.05);
});

// ─── Rule 5 — Види-індикатори ────────────────────────────────
Deno.test('rule5: білий + індикатор знайдено → +0.10', () => {
  const rule = makeRule({ indicatorSpecies: ['amanita_muscaria'] });
  const ctx = makeCtx({
    crowd: { verifiedPicks7d: 3, negativeReports7d: 0, indicatorSpecies: ['amanita_muscaria'] },
  });
  const r = rule5_Indicators(rule, ctx);
  assertEquals(r.skip, undefined);
  assertEquals(r.modifier, 0.10);
  assert(r.reason?.includes('amanita_muscaria'));
});

Deno.test('rule5: білий, crowd порожній → 0', () => {
  const rule = makeRule({ indicatorSpecies: ['amanita_muscaria'] });
  const r = rule5_Indicators(rule, makeCtx());
  assertEquals(r.modifier, 0);
});

Deno.test('rule5: лисичка → skip', () => {
  const rule = makeRule({ mushroomType: 'cantharellus_cibarius', indicatorSpecies: ['amanita_muscaria'] });
  const ctx = makeCtx({
    crowd: { verifiedPicks7d: 3, negativeReports7d: 0, indicatorSpecies: ['amanita_muscaria'] },
  });
  const r = rule5_Indicators(rule, ctx);
  assertEquals(r.skip, true);
});

// ─── Rule 6 — Температура міцелію ────────────────────────────
Deno.test('rule6: tempAvg14d=16 в оптимумі 15–20 → +0.10', () => {
  const rule = makeRule({ myceliumTempMin: 15, myceliumTempMax: 20 });
  const ctx = makeCtx({
    weather: makeWeather({ tempAvg14d: 16, tempMax: 20, tempMin: 10 }),
  });
  const r = rule6_MyceliumTemp(rule, ctx);
  assertEquals(r.modifier, 0.10);
  assert(r.reason?.includes('Стабільна'));
});

Deno.test('rule6: tempMax=30 → −0.15', () => {
  const rule = makeRule({ myceliumTempMin: 15, myceliumTempMax: 20 });
  const ctx = makeCtx({
    weather: makeWeather({ tempAvg14d: 16, tempMax: 30, tempMin: 10 }),
  });
  const r = rule6_MyceliumTemp(rule, ctx);
  assertEquals(r.modifier, -0.15);
  assert(r.reason?.includes('перепади'));
});

Deno.test('rule6: temp поза оптимумом (али в межах) → 0', () => {
  const rule = makeRule({ myceliumTempMin: 20, myceliumTempMax: 25 });
  const ctx = makeCtx({
    weather: makeWeather({ tempAvg14d: 10, tempMax: 18, tempMin: 5 }),
  });
  const r = rule6_MyceliumTemp(rule, ctx);
  assertEquals(r.modifier, 0);
});

// ─── Rule 8 — Сезонний мікрорефугіум ─────────────────────────
Deno.test('rule8: soil dry → overrideWhere = microrefugiumDry', () => {
  const rule = makeRule({ microrefugiumDry: 'південний схил', microrefugiumWet: 'низина' });
  const r = rule8_SeasonMicrorefugium(rule, makeCtx({
    weather: makeWeather({ soilState: 'dry' }),
  }));
  assertEquals(r.modifier, 0);
  assertEquals(r.overrideWhere, 'південний схил');
});

Deno.test('rule8: soil wet → overrideWhere = microrefugiumWet', () => {
  const rule = makeRule({ microrefugiumDry: 'південний схил', microrefugiumWet: 'низина' });
  const r = rule8_SeasonMicrorefugium(rule, makeCtx({
    weather: makeWeather({ soilState: 'wet' }),
  }));
  assertEquals(r.modifier, 0);
  assertEquals(r.overrideWhere, 'низина');
});

Deno.test('rule8: soil normal → 0 без override', () => {
  const rule = makeRule({ microrefugiumDry: 'південний схил', microrefugiumWet: 'низина' });
  const r = rule8_SeasonMicrorefugium(rule, makeCtx());
  assertEquals(r.modifier, 0);
  assertEquals(r.overrideWhere, undefined);
});

// ─── MVP_RULES ───────────────────────────────────────────────
Deno.test('MVP_RULES: 7 правил у правильному порядку', () => {
  assertEquals(MVP_RULES.length, 7);
  assertEquals(MVP_RULES[0], rule1_StandAge);
  assertEquals(MVP_RULES[1], rule2_DroughtThenRain);
  assertEquals(MVP_RULES[2], rule3_MicrorefugiumBoletus);
  assertEquals(MVP_RULES[3], rule4_Waves);
  assertEquals(MVP_RULES[4], rule5_Indicators);
  assertEquals(MVP_RULES[5], rule6_MyceliumTemp);
  assertEquals(MVP_RULES[6], rule8_SeasonMicrorefugium);
});
