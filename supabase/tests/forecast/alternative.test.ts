import { assertEquals } from 'jsr:@std/assert';
import { pickAlternative } from '../../functions/_shared/forecast/alternative.ts';
import type {
  SpeciesRule, ScoredSpecies, ForecastContext, Wave,
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

function makeScored(mushroomType: string): ScoredSpecies {
  return {
    mushroom_type: mushroomType,
    name_ua: 'X',
    score: 0.6,
    probability: 'medium',
    matched: [],
    missed: [],
    wave: 'summer2',
  } as ScoredSpecies;
}

function makeRulesMap(rules: SpeciesRule[]): Map<string, SpeciesRule> {
  return new Map(rules.map(r => [r.mushroomType, r]));
}

function makeCtx(wave: Wave): ForecastContext {
  return { wave } as ForecastContext;
}

// ─── порог довжини ───────────────────────────────────────────
Deno.test('pickAlternative: sorted.length < 2 → null', () => {
  const top1 = makeScored('boletus_edulis');
  const rules = makeRulesMap([makeRule()]);
  assertEquals(pickAlternative([top1], top1, makeCtx('autumn'), rules), null);
});

// ─── Рівень 1: інший тип лісу ────────────────────────────────
Deno.test('pickAlternative: різні forestType → Рівень 1', () => {
  const top1Rule = makeRule({ forestType: ['pine'] });
  const candRule = makeRule({
    id: 'rule-2', mushroomType: 'russula_vesca',
    nameUa: 'Сироїжка', nameLat: 'Russula vesca', forestType: ['oak'],
  });
  const rules = makeRulesMap([top1Rule, candRule]);
  const top1 = makeScored('boletus_edulis');
  const sorted = [top1, makeScored('russula_vesca')];
  assertEquals(pickAlternative(sorted, top1, makeCtx('summer2'), rules), sorted[1]);
});

// ─── Рівень 1: інша хвиля ────────────────────────────────────
Deno.test('pickAlternative: різні wave-флаги → Рівень 1', () => {
  const top1Rule = makeRule({ forestType: ['pine'], waveSummer2: true });
  const candRule = makeRule({
    id: 'rule-2', mushroomType: 'russula_vesca',
    nameUa: 'Сироїжка', nameLat: 'Russula vesca',
    forestType: ['pine'], waveSummer2: false,
  });
  const rules = makeRulesMap([top1Rule, candRule]);
  const top1 = makeScored('boletus_edulis');
  const sorted = [top1, makeScored('russula_vesca')];
  assertEquals(pickAlternative(sorted, top1, makeCtx('summer2'), rules), sorted[1]);
});

// ─── Рівень 1 не спрацював → Рівень 2 (genus) ────────────────
Deno.test('pickAlternative: однакові forest+wave → Рівень 2 (різний genus)', () => {
  const top1Rule = makeRule({ forestType: ['pine'], waveSummer2: true });
  const candRule = makeRule({
    id: 'rule-2', mushroomType: 'russula_vesca',
    nameUa: 'Сироїжка', nameLat: 'Russula vesca',
    forestType: ['pine'], waveSummer2: true,
  });
  const rules = makeRulesMap([top1Rule, candRule]);
  const top1 = makeScored('boletus_edulis');
  const sorted = [top1, makeScored('russula_vesca')];
  const alt = pickAlternative(sorted, top1, makeCtx('summer2'), rules);
  assertEquals(alt, sorted[1]);
  assertEquals(alt?.mushroom_type, 'russula_vesca');
});

Deno.test('pickAlternative: Рівень 2 пропускає той самий рід ("Boletus edulis" → "Boletus")', () => {
  const top1Rule = makeRule({ forestType: ['pine'], waveSummer2: true });
  // кандидати 1..2: той самий рід; кандидат 3 — інший
  const sameGenus = makeRule({
    id: 'rule-2', mushroomType: 'boletus_aereus',
    nameUa: 'Гладкий дубовик', nameLat: 'Boletus aereus',
    forestType: ['pine'], waveSummer2: true,
  });
  const otherGenus = makeRule({
    id: 'rule-3', mushroomType: 'lactarius_deliciosus',
    nameUa: 'Рижик', nameLat: 'Lactarius deliciosus',
    forestType: ['pine'], waveSummer2: true,
  });
  const rules = makeRulesMap([top1Rule, sameGenus, otherGenus]);
  const top1 = makeScored('boletus_edulis');
  const sorted = [top1, makeScored('boletus_aereus'), makeScored('lactarius_deliciosus')];
  const alt = pickAlternative(sorted, top1, makeCtx('summer2'), rules);
  assertEquals(alt, sorted[2]);
  assertEquals(alt?.mushroom_type, 'lactarius_deliciosus');
});

// ─── Рівень 2 не спрацював → Рівень 3 ────────────────────────
Deno.test('pickAlternative: той самий рід і умови → Рівень 3 (sorted[1])', () => {
  const top1Rule = makeRule({ forestType: ['pine'], waveSummer2: true });
  const candRule = makeRule({
    id: 'rule-2', mushroomType: 'boletus_aereus',
    nameUa: 'Гладкий дубовик', nameLat: 'Boletus aereus',
    forestType: ['pine'], waveSummer2: true,
  });
  const rules = makeRulesMap([top1Rule, candRule]);
  const top1 = makeScored('boletus_edulis');
  const sorted = [top1, makeScored('boletus_aereus')];
  assertEquals(pickAlternative(sorted, top1, makeCtx('summer2'), rules), sorted[1]);
});

// ─── Рівень 1 проскакує невідповідних кандидатів ─────────────
Deno.test('pickAlternative: Рівень 1 шукає першого відмінного не з першої позиції', () => {
  const top1Rule = makeRule({ forestType: ['pine'], waveSummer2: true });
  const sameAsTop = makeRule({
    id: 'rule-2', mushroomType: 'boletus_aereus',
    nameUa: 'Гладкий дубовик', nameLat: 'Boletus aereus',
    forestType: ['pine'], waveSummer2: true,
  });
  const differentForest = makeRule({
    id: 'rule-3', mushroomType: 'russula_vesca',
    nameUa: 'Сироїжка', nameLat: 'Russula vesca',
    forestType: ['oak'], waveSummer2: true,
  });
  const rules = makeRulesMap([top1Rule, sameAsTop, differentForest]);
  const top1 = makeScored('boletus_edulis');
  const sorted = [top1, makeScored('boletus_aereus'), makeScored('russula_vesca')];
  assertEquals(pickAlternative(sorted, top1, makeCtx('summer2'), rules), sorted[2]);
});

// ─── Рівень 1/2 без rules для виду → ніколи не вважається відмінним ──
Deno.test('pickAlternative: правило відсутнє в мапі → Рівень 3', () => {
  const top1Rule = makeRule({ forestType: ['pine'] });
  const rules = makeRulesMap([top1Rule]); // russula відсутня
  const top1 = makeScored('boletus_edulis');
  const sorted = [top1, makeScored('russula_vesca')];
  assertEquals(pickAlternative(sorted, top1, makeCtx('summer2'), rules), sorted[1]);
});
