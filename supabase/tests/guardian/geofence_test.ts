// ============================================================================
// Geofence — unit tests (audit G4)
// Мок db: chainable query builder + rpc мок.
// ============================================================================
import { assertEquals, assert } from 'jsr:@std/assert';
import { detectForestExit } from '../../functions/_shared/guardian/geofence.ts';
import type { ExitDetectionResult } from '../../functions/_shared/guardian/geofence.ts';

const SESSION_ID = 'sess-geo-1';

function trackPoint(lat: number, lng: number, was_offline = false) {
  return {
    coords: { type: 'Point', coordinates: [lng, lat] },
    recorded_at: new Date().toISOString(),
    was_offline,
  };
}

function makeDbMock(opts: {
  rpcStates: Array<'inside' | 'outside' | 'unknown'>;
  points: Array<{ lat: number; lng: number; was_offline?: boolean }>;
  rpcError?: boolean;
}) {
  const rpcCalls: Array<{ p_lat: number; p_lng: number }> = [];
  let rpcIndex = 0;

  const db = {
    from(table: string) {
      const chain = {
        select() { return chain; },
        eq() { return chain; },
        order() { return chain; },
        limit() { return chain; },
        then(
          resolve: (v: unknown) => unknown,
          reject?: (e: unknown) => unknown
        ) {
          const points = opts.points.map(p => trackPoint(p.lat, p.lng, p.was_offline));
          return Promise.resolve({ data: points, error: null }).then(resolve, reject);
        },
      };
      return chain;
    },
    rpc(_fn: string, params: { p_lat: number; p_lng: number }) {
      rpcCalls.push(params);
      if (opts.rpcError) {
        return Promise.resolve({ data: null, error: { message: 'rpc down' } });
      }
      const state = opts.rpcStates[rpcIndex] ?? 'inside';
      rpcIndex++;
      return Promise.resolve({ data: state, error: null });
    },
  };

  return { db: db as unknown, rpcCalls };
}

Deno.test('geofence: empty points → not confirmed exit', async () => {
  const { db } = makeDbMock({ rpcStates: [], points: [] });
  const result = await detectForestExit(db as any, SESSION_ID);
  assertEquals(result.isConfirmedExit, false);
  assertEquals(result.consecutiveOutsideCount, 0);
  assertEquals(result.totalChecked, 0);
});

Deno.test('geofence: 3 consecutive outside → confirmed exit', async () => {
  const { db } = makeDbMock({
    rpcStates: ['outside', 'outside', 'outside'],
    points: [
      { lat: 48.5, lng: 24.5 },
      { lat: 48.51, lng: 24.51 },
      { lat: 48.52, lng: 24.52 },
    ],
  });
  const result = await detectForestExit(db as any, SESSION_ID);
  assertEquals(result.isConfirmedExit, true);
  assertEquals(result.consecutiveOutsideCount, 3);
});

Deno.test('geofence: 2 consecutive outside → NOT confirmed (поріг 3)', async () => {
  const { db } = makeDbMock({
    rpcStates: ['outside', 'outside'],
    points: [
      { lat: 48.5, lng: 24.5 },
      { lat: 48.51, lng: 24.51 },
    ],
  });
  const result = await detectForestExit(db as any, SESSION_ID);
  assertEquals(result.isConfirmedExit, false);
  assertEquals(result.consecutiveOutsideCount, 2);
});

Deno.test('geofence: inside resets counter', async () => {
  const { db } = makeDbMock({
    rpcStates: ['outside', 'outside', 'inside', 'outside'],
    points: [
      { lat: 48.5, lng: 24.5 },
      { lat: 48.51, lng: 24.51 },
      { lat: 48.52, lng: 24.52 },
      { lat: 48.53, lng: 24.53 },
    ],
  });
  const result = await detectForestExit(db as any, SESSION_ID);
  // 'inside' на 3-й точці → скидання і break, 4-я точка не обробляється
  assertEquals(result.isConfirmedExit, false);
  assertEquals(result.consecutiveOutsideCount, 0);
});

Deno.test('geofence: unknown does not count (5 unknown → not confirmed)', async () => {
  const { db } = makeDbMock({
    rpcStates: ['unknown', 'unknown', 'unknown', 'unknown', 'unknown'],
    points: [
      { lat: 48.5, lng: 24.5 },
      { lat: 48.51, lng: 24.51 },
      { lat: 48.52, lng: 24.52 },
      { lat: 48.53, lng: 24.53 },
      { lat: 48.54, lng: 24.54 },
    ],
  });
  const result = await detectForestExit(db as any, SESSION_ID);
  assertEquals(result.isConfirmedExit, false);
  assertEquals(result.consecutiveOutsideCount, 0);
  assertEquals(result.hadUnknown, true);
});

Deno.test('geofence: was_offline points skipped', async () => {
  const { db } = makeDbMock({
    rpcStates: ['outside', 'outside'], // тільки 2 не-offline точки мають被 обробити
    points: [
      { lat: 48.5, lng: 24.5, was_offline: true },
      { lat: 48.51, lng: 24.51 },
      { lat: 48.52, lng: 24.52 },
    ],
  });
  const result = await detectForestExit(db as any, SESSION_ID);
  assertEquals(result.isConfirmedExit, false); // тільки 2 outside → не достатньо для 3
  assertEquals(result.consecutiveOutsideCount, 2);
});

Deno.test('geofence: mixed 2 outside + 1 inside + 2 outside → false (після inside скинуто)', async () => {
  const { db } = makeDbMock({
    rpcStates: ['outside', 'outside', 'inside', 'outside', 'outside'],
    points: [
      { lat: 48.5, lng: 24.5 },
      { lat: 48.51, lng: 24.51 },
      { lat: 48.52, lng: 24.52 },
      { lat: 48.53, lng: 24.53 },
      { lat: 48.54, lng: 24.54 },
    ],
  });
  const result = await detectForestExit(db as any, SESSION_ID);
  // 'inside' на 3-й точці → break, інші не обробляються
  assertEquals(result.isConfirmedExit, false);
  assertEquals(result.consecutiveOutsideCount, 0);
});
