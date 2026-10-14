// ============================================================================
// Regression Runner — Golden Dataset (аудит C)
// ============================================================================
// Проганяє кожен запис golden-dataset.json через ForecastEngine з:
//   - моканим fetch → weather_payload із датасету (без живих Open-Meteo)
//   - моканим db → rules-subset.json + regions + forest zone RPC
//
// Метрики (план v6.0 §18.3):
//   Precision = TP / (TP + FP)   [target ≥ 0.5]
//   Recall    = TP / (TP + FN)   [target ≥ 0.3]
//   Top1      = частка записів із top1.mushroom_type === expected.top1_slug
// Прогноз "дано" = top1 !== null && noDataReason === undefined
// (buildFallback може дати ненульовий top1 з noDataReason — це НЕ прогноз).
//
// Запуск:
//   deno test supabase/tests/forecast/regression.test.ts --allow-net --allow-read
// ============================================================================

import { assertEquals, assert } from 'jsr:@std/assert';
import { ForecastEngine } from '../../functions/_shared/forecast/engine.ts';
import { loadFeatureFlags } from '../../functions/_shared/forecast/flags.ts';
import { isInSeason } from '../../functions/_shared/forecast/constants.ts';
import type { ForecastDbClient } from '../../functions/_shared/forecast/context.ts';
import type { DbClient } from '../../functions/_shared/forecast/db.ts';
import type {
  ForecastInput, ForecastResult, ScoredSpecies, SpeciesRule,
} from '../../functions/_shared/forecast/types.ts';

// ─── Fixtures ──────────────────────────────────────────────────

interface GoldenRecord {
  id: string;
  description: string;
  input: Omit<ForecastInput, 'date'> & { date: string };
  weather_payload: {
    hourly: Record<string, number>;
    daily: Record<string, number | number[]>;
  };
  weather_summary: Record<string, unknown>;
  expected: {
    top1_slug: string | null;
    top1_wave: string | null;
    actual_found: boolean;
  };
}

const REGION_NAMES: Record<number, string> = { 1: 'Київська', 13: 'Львівська' };

const HOURLY_LEN = 30 * 24;
const DAILY_LEN = 30;

// ─── Fixtures (lazy: без --allow-read — graceful skip) ─────────

interface Fixtures {
  records: GoldenRecord[];
  rules: Record<string, unknown>[];
}

let fixturesCache: Fixtures | null = null;

async function loadFixtures(): Promise<Fixtures | null> {
  if (fixturesCache) return fixturesCache;
  try {
    const datasetText = await Deno.readTextFile(
      new URL('../fixtures/golden-dataset.json', import.meta.url),
    );
    const rulesText = await Deno.readTextFile(
      new URL('../fixtures/rules-subset.json', import.meta.url),
    );
    fixturesCache = {
      records: (JSON.parse(datasetText) as { records: GoldenRecord[] }).records,
      rules: JSON.parse(rulesText) as Record<string, unknown>[],
    };
    return fixturesCache;
  } catch (e) {
    const name = e instanceof Error ? e.name : '';
    if (name === 'PermissionDenied' || name === 'NotCapable') {
      console.warn(
        '⚠ regression: немає дозволу --allow-read — golden dataset skipped. ' +
        'Запуск: deno test supabase/tests/forecast/regression.test.ts --allow-net --allow-read',
      );
      return null;
    }
    throw e;
  }
}

// ─── Helpers ───────────────────────────────────────────────────

/** Скаляр → масив заповнення; масив → як є. Час — умовні індекси. */
function expandPayload(p: GoldenRecord['weather_payload']): Record<string, unknown> {
  const hourly: Record<string, unknown> = {};
  for (const [key, val] of Object.entries(p.hourly)) {
    hourly[key] = Array.isArray(val) ? val : Array(HOURLY_LEN).fill(val);
  }
  const daily: Record<string, unknown> = {};
  for (const [key, val] of Object.entries(p.daily)) {
    daily[key] = Array.isArray(val) ? val : Array(DAILY_LEN).fill(val);
  }
  return {
    hourly: { time: Array.from({ length: HOURLY_LEN }, (_, i) => `h${i}`), ...hourly },
    daily: { time: Array.from({ length: DAILY_LEN }, (_, i) => `d${i}`), ...daily },
  };
}

function makeDbMock(rules: Record<string, unknown>[], homeRegionId: number | null) {
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
            return Promise.resolve({ data: rules, error: null }).then(resolve, reject);
          }
          if (table === 'feature_flags') {
            return Promise.resolve({ data: [], error: null }).then(resolve, reject);
          }
          if (table === 'mushroom_picks') {
            return Promise.resolve({ count: 0, error: null }).then(resolve, reject);
          }
          return Promise.resolve({ data: null, error: null }).then(resolve, reject);
        },
        maybeSingle() {
          if (table === 'regions' && homeRegionId !== null && REGION_NAMES[homeRegionId]) {
            return Promise.resolve({
              data: { id: homeRegionId, name: REGION_NAMES[homeRegionId] },
              error: null,
            });
          }
          return Promise.resolve({ data: null, error: null });
        },
      };
      return chain;
    },
    rpc(fn: string) {
      if (fn === 'find_zone_by_point') {
        return Promise.resolve({
          data: {
            id: 'zone-1',
            forest_type: null,
            stand_age_years: 50,
            stand_age_source: 'test',
            stand_age_confidence: 0.9,
            relief_type: 'plain',
            light_type: null,
          },
          error: null,
        });
      }
      if (fn === 'point_in_region') {
        return Promise.resolve({ data: true, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return db as unknown as ForecastDbClient & DbClient;
}

async function runRecord(
  rec: GoldenRecord,
  rules: Record<string, unknown>[],
): Promise<ForecastResult> {
  const db = makeDbMock(rules, rec.input.homeRegionId);
  const flags = await loadFeatureFlags(db);
  const input: ForecastInput = {
    ...rec.input,
    date: new Date(rec.input.date),
  } as ForecastInput;

  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify(expandPayload(rec.weather_payload)), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    )) as typeof globalThis.fetch;
  try {
    return await ForecastEngine.forecast(input, db, flags);
  } finally {
    globalThis.fetch = originalFetch;
  }
}

interface RecordResult {
  rec: GoldenRecord;
  top1: ScoredSpecies | null;
  noDataReason: string | undefined;
  predicted: boolean;        // top1 !== null && !noDataReason
  slugMatch: boolean | null; // null — не оцінюється (очікувалось no_data)
  waveMatch: boolean | null;
}

// ─── Metrics ───────────────────────────────────────────────────

function computePrecision(results: RecordResult[]): { value: number; tp: number; fp: number } {
  const tp = results.filter((r) => r.rec.expected.actual_found && r.predicted).length;
  const fp = results.filter((r) => !r.rec.expected.actual_found && r.predicted).length;
  const denom = tp + fp;
  return { value: denom === 0 ? 1 : tp / denom, tp, fp };
}

function computeRecall(results: RecordResult[]): { value: number; tp: number; fn: number } {
  const tp = results.filter((r) => r.rec.expected.actual_found && r.predicted).length;
  const fn = results.filter((r) => r.rec.expected.actual_found && !r.predicted).length;
  const denom = tp + fn;
  return { value: denom === 0 ? 1 : tp / denom, tp, fn };
}

function computeTop1(results: RecordResult[]): { value: number; ok: number; n: number } {
  const judged = results.filter((r) => r.rec.expected.top1_slug !== null);
  const ok = judged.filter((r) => r.slugMatch === true).length;
  return { value: judged.length === 0 ? 1 : ok / judged.length, ok, n: judged.length };
}

function formatRegressionReport(results: RecordResult[]): string {
  const lines: string[] = ['', '=== GOLDEN DATASET REGRESSION ==='];
  for (const r of results) {
    lines.push(`${r.rec.id} | ${r.rec.description}`);
    if (r.top1) {
      const flag = r.noDataReason ? ' (fallback)' : '';
      lines.push(
        `  → top1: ${r.top1.name_ua} / ${r.top1.mushroom_type}, ` +
        `wave=${r.top1.wave}, score=${r.top1.score.toFixed(2)}, ` +
        `prob=${r.top1.probability}${flag}` +
        (r.noDataReason ? `, noDataReason="${r.noDataReason}"` : ''),
      );
    } else {
      lines.push(
        `  → top1: null, noDataReason="${r.noDataReason ?? '—'}"`,
      );
    }
    if (r.slugMatch !== null) {
      lines.push(`  ✓ slug ${r.slugMatch ? 'OK' : 'MISMATCH'}, wave ${r.waveMatch ? 'OK' : 'MISMATCH'}`);
    }
    lines.push('');
  }
  lines.push('----------------------------------------');
  const p = computePrecision(results);
  const rc = computeRecall(results);
  const t = computeTop1(results);
  lines.push(`Precision: ${p.value.toFixed(2)} (TP=${p.tp}, FP=${p.fp})  [target ≥ 0.5]`);
  lines.push(`Recall:    ${rc.value.toFixed(2)} (TP=${rc.tp}, FN=${rc.fn})  [target ≥ 0.3]`);
  lines.push(`Top1:      ${t.value.toFixed(2)} (${t.ok}/${t.n} slug matched)`);
  lines.push('========================================');
  return lines.join('\n');
}

// ─── Тест ──────────────────────────────────────────────────────

Deno.test('regression: golden dataset — ForecastEngine Precision/Recall', async () => {
  const fixtures = await loadFixtures();
  if (!fixtures) return;

  const records = fixtures.records;
  const RULES = fixtures.rules;

  if (records.length === 0) {
    console.warn('⚠ Golden dataset empty — skipping regression run');
    return;
  }

  const results: RecordResult[] = [];

  for (const rec of records) {
    const res = await runRecord(rec, RULES);
    const predicted = res.top1 !== null && res.noDataReason === undefined;

    let slugMatch: boolean | null = null;
    let waveMatch: boolean | null = null;
    if (rec.expected.top1_slug !== null) {
      slugMatch = res.top1?.mushroom_type === rec.expected.top1_slug;
      waveMatch = res.top1?.wave === (rec.expected.top1_wave ?? null);
    }

    results.push({
      rec,
      top1: res.top1,
      noDataReason: res.noDataReason,
      predicted,
      slugMatch,
      waveMatch,
    });
  }

  console.log(formatRegressionReport(results));

  // ─── Per-record assertions (регресійний guard) ───
  for (const r of results) {
    if (r.rec.expected.top1_slug !== null) {
      assertEquals(
        r.top1?.mushroom_type,
        r.rec.expected.top1_slug,
        `${r.rec.id}: top1 slug mismatch`,
      );
      assertEquals(
        r.top1?.wave,
        r.rec.expected.top1_wave ?? null,
        `${r.rec.id}: top1 wave mismatch (detectWave regression!)`,
      );
    } else {
      assertEquals(
        r.top1,
        null,
        `${r.rec.id}: очікувався top1=null (поза сезоном)`,
      );
      assert(
        r.noDataReason !== undefined,
        `${r.rec.id}: очікувався noDataReason`,
      );
    }
  }

  // ─── Метрики (план v6.0 §18.3) ───
  const precision = computePrecision(results);
  const recall = computeRecall(results);
  const top1 = computeTop1(results);

  assert(precision.value >= 0.5, `Precision ${precision.value.toFixed(2)} < 0.5`);
  assert(recall.value >= 0.3, `Recall ${recall.value.toFixed(2)} < 0.3`);
  assertEquals(top1.value, 1, 'Top1 slug accuracy < 100%');
});

// ─── Season-чек flammulina_velutipes (сезон через рік) ─────────

Deno.test('regression: flammulina_velutipes — сезон через рік (10-01..03-31)', async () => {
  const fixtures = await loadFixtures();
  if (!fixtures) return;

  const rule = fixtures.rules.find((r) => r.mushroom_type === 'flammulina_velutipes');
  assert(rule !== undefined, 'flammulina_velutipes відсутній у rules-subset');

  const nov = isInSeason('11-15', String(rule?.season_start), String(rule?.season_end));
  const apr = isInSeason('04-20', String(rule?.season_start), String(rule?.season_end));

  console.log(
    `flamulina season check: 11-15 in [${rule?.season_start}..${rule?.season_end}] → ${nov} | ` +
    `04-20 → ${apr}`,
  );

  assert(nov, '11-15 має бути in-season для зимового опенька');
  assert(!apr, '04-20 має бути NOT in-season для зимового опенька');
});
