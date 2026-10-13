import { assertEquals } from 'jsr:@std/assert';
import { handleRegionsRequest } from '../../functions/_shared/forecast/regions-endpoint.ts';
import type { RegionsQueryClient } from '../../functions/_shared/forecast/regions-endpoint.ts';

// Мок Supabase-клієнта: ланцюжок from().select().order() + керована відповідь
function makeDbMock(
  response: { data: unknown; error: unknown },
): { db: RegionsQueryClient; calls: string[] } {
  const calls: string[] = [];
  const db = {
    from(table: string) {
      calls.push(`from:${table}`);
      return {
        select(cols: string) {
          calls.push(`select:${cols}`);
          return {
            order(column: string, opts?: { ascending?: boolean }) {
              calls.push(`order:${column}:${opts?.ascending}`);
              return Promise.resolve(response);
            },
          };
        },
      };
    },
  };
  return { db, calls };
}

// ─── GET /regions ───────────────────────────────────────────

Deno.test('regions endpoint: GET → 200 + {data: [...]}', async () => {
  const rows = [
    { id: 26, name: 'Київ', slug: 'kyiv', koatuu: null, katottg: 'UA8000000000093317' },
    { id: 1, name: 'Вінницька', slug: 'vinnytska', koatuu: '0510000000', katottg: null },
  ];
  const { db, calls } = makeDbMock({ data: rows, error: null });

  const res = await handleRegionsRequest(db, new Request('http://localhost/regions'));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body, { data: rows });
  // лише атрибути, без geometry + сортування по name для стабільного UI
  assertEquals(calls, [
    'from:regions',
    'select:id, name, slug, koatuu, katottg',
    'order:name:true',
  ]);
});

Deno.test('regions endpoint: non-GET (POST) → 405', async () => {
  const { db } = makeDbMock({ data: [], error: null });
  const res = await handleRegionsRequest(
    db,
    new Request('http://localhost/regions', { method: 'POST' }),
  );
  assertEquals(res.status, 405);
  assertEquals(await res.json(), { error: 'method_not_allowed' });
});

Deno.test('regions endpoint: OPTIONS → 204', async () => {
  const { db } = makeDbMock({ data: [], error: null });
  const res = await handleRegionsRequest(
    db,
    new Request('http://localhost/regions', { method: 'OPTIONS' }),
  );
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), '*');
});

Deno.test('regions endpoint: DB error → 500 db_error', async () => {
  const { db } = makeDbMock({ data: null, error: { message: 'boom' } });
  const res = await handleRegionsRequest(db, new Request('http://localhost/regions'));
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'db_error' });
});
