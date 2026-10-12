import { assertEquals } from 'jsr:@std/assert';
import { pointInRegion } from '../../functions/_shared/forecast/regions.ts';
import type { ForecastDbClient } from '../../functions/_shared/forecast/context.ts';

// Мок ForecastDbClient: лічильник викликів + керована відповідь rpc
function makeDbMock(
  response: { data: unknown; error: unknown },
): { db: ForecastDbClient; calls: string[] } {
  const calls: string[] = [];
  const db = {
    from() {
      throw new Error('not used');
    },
    rpc(fn: string, params: Record<string, unknown>) {
      calls.push(`${fn}(${JSON.stringify(params)})`);
      return Promise.resolve(response);
    },
  } as unknown as ForecastDbClient;
  return { db, calls };
}

Deno.test('pointInRegion: regionId=null → false без виклику RPC', async () => {
  const { db, calls } = makeDbMock({ data: true, error: null });
  const r = await pointInRegion(db, 50.45, 30.52, null);
  assertEquals(r, false);
  assertEquals(calls.length, 0); // RPC не викликався
});

Deno.test('pointInRegion: RPC → { data: true } → true', async () => {
  const { db, calls } = makeDbMock({ data: true, error: null });
  const r = await pointInRegion(db, 50.45, 30.52, 1);
  assertEquals(r, true);
  assertEquals(calls, ['point_in_region({"lat":50.45,"lng":30.52,"region_id":1})']);
});

Deno.test('pointInRegion: RPC → { data: null, error } → false (graceful)', async () => {
  const { db } = makeDbMock({ data: null, error: { message: 'boom' } });
  const r = await pointInRegion(db, 50.45, 30.52, 1);
  assertEquals(r, false);
});

Deno.test('pointInRegion: RPC → { data: false } → false', async () => {
  const { db } = makeDbMock({ data: false, error: null });
  const r = await pointInRegion(db, 50.45, 30.52, 1);
  assertEquals(r, false);
});
