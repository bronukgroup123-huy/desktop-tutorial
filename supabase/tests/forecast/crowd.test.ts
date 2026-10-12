import { assertEquals, assert } from 'jsr:@std/assert';
import { applyCrowdAdjust } from '../../functions/_shared/forecast/crowd.ts';
import type {
  ScoredSpecies, ProbabilityLevel, ForecastContext, CrowdData,
} from '../../functions/_shared/forecast/types.ts';

function makeCtx(crowd: Partial<CrowdData>): ForecastContext {
  return { crowd: { verifiedPicks7d: 0, negativeReports7d: 0, indicatorSpecies: [], ...crowd } } as ForecastContext;
}

function makeScored(level: ProbabilityLevel): ScoredSpecies {
  return {
    mushroom_type: 'boletus_edulis',
    name_ua: 'Білий',
    score: level === 'no_data' ? 0 : 0.6,
    probability: level,
    matched: [],
    missed: [],
    wave: 'autumn',
  } as ScoredSpecies;
}

// ─── FIX 2.12: no_data НЕ підвищується ───────────────────────
Deno.test('applyCrowdAdjust: no_data не змінюється навіть при 3+ picks', () => {
  const ctx = makeCtx({ verifiedPicks7d: 5 });
  const r = applyCrowdAdjust(makeScored('no_data'), ctx);
  assertEquals(r.probability, 'no_data');
});

Deno.test('applyCrowdAdjust: no_data не змінюється при negatives', () => {
  const ctx = makeCtx({ verifiedPicks7d: 0, negativeReports7d: 2 });
  const r = applyCrowdAdjust(makeScored('no_data'), ctx);
  assertEquals(r.probability, 'no_data');
});

// ─── picks=0 → пониження ─────────────────────────────────────
Deno.test('applyCrowdAdjust: picks=0 → level понижується', () => {
  const ctx = makeCtx({ verifiedPicks7d: 0 });
  assertEquals(applyCrowdAdjust(makeScored('medium'), ctx).probability, 'low');
  assertEquals(applyCrowdAdjust(makeScored('high'), ctx).probability, 'medium');
});

Deno.test('applyCrowdAdjust: picks=0, low → low (clamp на мін)', () => {
  const ctx = makeCtx({ verifiedPicks7d: 0 });
  assertEquals(applyCrowdAdjust(makeScored('low'), ctx).probability, 'low');
});

// ─── picks≥3 → підвищення ────────────────────────────────────
Deno.test('applyCrowdAdjust: picks=3 → level підвищується', () => {
  const ctx = makeCtx({ verifiedPicks7d: 3 });
  assertEquals(applyCrowdAdjust(makeScored('low'), ctx).probability, 'medium');
  assertEquals(applyCrowdAdjust(makeScored('medium'), ctx).probability, 'high');
});

// ─── negatives → пониження, домінує над picks ────────────────
Deno.test('applyCrowdAdjust: negatives=1 → level понижується', () => {
  const ctx = makeCtx({ verifiedPicks7d: 0, negativeReports7d: 1 });
  assertEquals(applyCrowdAdjust(makeScored('medium'), ctx).probability, 'low');
});

Deno.test('applyCrowdAdjust: negatives домінують над picks≥3', () => {
  const ctx = makeCtx({ verifiedPicks7d: 5, negativeReports7d: 2 });
  assertEquals(applyCrowdAdjust(makeScored('high'), ctx).probability, 'medium');
});

// ─── picks 1–2 → без змін ────────────────────────────────────
Deno.test('applyCrowdAdjust: picks=1 → без змін', () => {
  const ctx = makeCtx({ verifiedPicks7d: 1 });
  assertEquals(applyCrowdAdjust(makeScored('medium'), ctx).probability, 'medium');
});

Deno.test('applyCrowdAdjust: picks=2 → без змін', () => {
  const ctx = makeCtx({ verifiedPicks7d: 2 });
  assertEquals(applyCrowdAdjust(makeScored('medium'), ctx).probability, 'medium');
});

// ─── clamp на максимум ───────────────────────────────────────
Deno.test('applyCrowdAdjust: peak + picks=3 → peak (clamp на max)', () => {
  const ctx = makeCtx({ verifiedPicks7d: 4 });
  assertEquals(applyCrowdAdjust(makeScored('peak'), ctx).probability, 'peak');
});

// ─── matched містить причину Краудсорсингу ───────────────────
Deno.test('applyCrowdAdjust: matched містить "Краудсорсинг"', () => {
  const s = makeScored('medium');
  s.matched = ['wave "autumn" allowed'];

  const up = applyCrowdAdjust(s, makeCtx({ verifiedPicks7d: 3 }));
  assert(up.matched.some(x => x.includes('Краудсорсинг')));
  assert(up.matched.some(x => x.includes('3 підтверджених знахідок')));
  assert(up.matched.includes('wave "autumn" allowed')); // існуючі причини збережені

  const down = applyCrowdAdjust(s, makeCtx({ verifiedPicks7d: 0, negativeReports7d: 1 }));
  assert(down.matched.some(x => x.includes('негативних звітів')));
});
