import { assertEquals } from 'jsr:@std/assert';
import {
  parsePicksQuery,
  handlePicksListRequest,
  periodCutoffMs,
  extractLatLng,
  PICKS_DEFAULT_LIMIT,
  PICKS_MAX_LIMIT,
} from '../../functions/_shared/forecast/picks-list.ts';
import type { PicksListDbClient } from '../../functions/_shared/forecast/picks-list.ts';

// Мок-клієнти: read.from('mushroom_picks') + admin.from(users|regions|catalog) +
// admin.storage.createSignedUrls + admin.rpc — все ланцюжки thenable.
function makeClients(cfg: {
  picks?: { data: unknown; error: unknown; count?: number };
  users?: { data: unknown; error?: unknown };
  regions?: { data: unknown; error?: unknown };
  catalog?: { data: unknown; error?: unknown };
  rpc?: { data: unknown; error: unknown };
  signed?: { data: unknown; error?: unknown };
} = {}): { readDb: PicksListDbClient; adminDb: PicksListDbClient; calls: string[] } {
  const calls: string[] = [];

  function makeBuilder(responses: Record<string, () => any>) {
    const builder = {
      select(cols: string, opts?: Record<string, unknown>) {
        calls.push(`select:${cols}:${JSON.stringify(opts ?? {})}`);
        return builder;
      },
      eq(col: string, val: unknown) { calls.push(`eq:${col}:${String(val)}`); return builder; },
      in(col: string, vals: unknown[]) {
        calls.push(`in:${col}:${JSON.stringify(vals)}`);
        return builder;
      },
      gte(col: string, val: unknown) { calls.push(`gte:${col}:${String(val)}`); return builder; },
      order(col: string, opts?: { ascending?: boolean }) {
        calls.push(`order:${col}:${opts?.ascending}`);
        return builder;
      },
      range(from: number, to: number) { calls.push(`range:${from}:${to}`); return builder; },
      then(resolve: (v: unknown) => void) {
        const response = responses.last();
        return Promise.resolve(response).then(resolve);
      },
    };
    return builder;
  }

  const readDb = {
    from(table: string) {
      calls.push(`read.from:${table}`);
      // read-ланцюжок завершується останнім thenable-await (picks)
      return makeBuilder({
        last: () => cfg.picks ?? { data: [], error: null, count: 0 },
      });
    },
    storage: { from: () => ({ createSignedUrls: () => Promise.resolve({ data: null, error: null }) }) },
    rpc: () => Promise.resolve({ data: null, error: null }),
  };

  const adminTables: Record<string, () => any> = {
    users: () => cfg.users ?? { data: [], error: null },
    regions: () => cfg.regions ?? { data: [], error: null },
    mushroom_catalog: () => cfg.catalog ?? { data: [], error: null },
  };
  const adminDb = {
    from(table: string) {
      calls.push(`admin.from:${table}`);
      const response = adminTables[table];
      if (!response) throw new Error(`unexpected admin table: ${table}`);
      return makeBuilder({ last: response });
    },
    storage: {
      from(bucket: string) {
        calls.push(`storage.from:${bucket}`);
        return {
          createSignedUrls(paths: string[], expiresIn: number) {
            calls.push(`createSignedUrls:${paths.join('|')}:${expiresIn}`);
            return Promise.resolve(cfg.signed ?? { data: [], error: null });
          },
        };
      },
    },
    rpc(fn: string, params: Record<string, unknown>) {
      calls.push(`rpc:${fn}(${JSON.stringify(params)})`);
      return Promise.resolve(cfg.rpc ?? { data: null, error: null });
    },
  };

  return { readDb: readDb as unknown as PicksListDbClient, adminDb: adminDb as unknown as PicksListDbClient, calls };
}

const NOW = new Date('2026-10-13T12:00:00Z');

const PICK_ROW = {
  id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  user_id: 'u-1',
  mushroom_type: 'boletus_edulis',
  forest_type: 'pine',
  pick_type: 'public',
  verification_status: 'verified',
  weight: 1.5,
  is_indicator: false,
  is_negative: false,
  created_at: '2026-10-13T08:00:00Z',
  photo_url: 'u-1/a1b2c3d4.jpg',
  geom: { type: 'Point', coordinates: [30.52, 50.45] },
};

// ─── parsePicksQuery ────────────────────────────────────────

Deno.test('picks parse: empty → defaults {scope:public, period:week, limit:20, offset:0}', () => {
  assertEquals(parsePicksQuery(new URL('http://localhost/picks')), {
    scope: 'public', period: 'week', limit: PICKS_DEFAULT_LIMIT, offset: 0,
  });
});

Deno.test('picks parse: limit=100 → error (max 50)', () => {
  assertEquals(PICKS_MAX_LIMIT, 50);
  assertEquals(parsePicksQuery(new URL('http://localhost/picks?limit=100')), { error: 'limit_out_of_range' });
});

Deno.test('picks parse: scope=invalid → error', () => {
  assertEquals(parsePicksQuery(new URL('http://localhost/picks?scope=everyone')), { error: 'invalid_scope' });
});

Deno.test('picks parse: period=invalid → error', () => {
  assertEquals(parsePicksQuery(new URL('http://localhost/picks?period=year')), { error: 'invalid_period' });
});

Deno.test('picks parse: mushroom_type=too_long → error', () => {
  const long = 'a'.repeat(65);
  assertEquals(parsePicksQuery(new URL(`http://localhost/picks?mushroom_type=${long}`)), { error: 'invalid_mushroom_type' });
});

Deno.test('picks parse: валідний mushroom_type + region_slug', () => {
  assertEquals(parsePicksQuery(new URL('http://localhost/picks?mushroom_type=boletus_edulis&region_slug=kyivska')), {
    scope: 'public', period: 'week', limit: 20, offset: 0,
    mushroomType: 'boletus_edulis', regionSlug: 'kyivska',
  });
});

// ─── handlePicksListRequest: auth + method ──────────────────

Deno.test('picks handler: scope=mine без userId → 401', async () => {
  const { readDb, adminDb } = makeClients();
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?scope=mine'), NOW);
  assertEquals(res.status, 401);
  assertEquals(await res.json(), { error: 'unauthorized' });
});

Deno.test('picks handler: scope=friends без userId → 401', async () => {
  const { readDb, adminDb } = makeClients();
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?scope=friends'), NOW);
  assertEquals(res.status, 401);
});

Deno.test('picks handler: OPTIONS → 204', async () => {
  const { readDb, adminDb } = makeClients();
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks', { method: 'OPTIONS' }), NOW);
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), '*');
});

Deno.test('picks handler: POST → 405', async () => {
  const { readDb, adminDb } = makeClients();
  const res = await handlePicksListRequest(readDb, adminDb, 'u-1', new Request('http://localhost/picks', { method: 'POST' }), NOW);
  assertEquals(res.status, 405);
  assertEquals(await res.json(), { error: 'method_not_allowed' });
});

// ─── handlePicksListRequest: public feed + mapping ──────────

Deno.test('picks handler: public → 200 + мапінг (users/regions/catalog/signed URL)', async () => {
  const { readDb, adminDb, calls } = makeClients({
    picks: { data: [PICK_ROW], error: null, count: 42 },
    users: { data: [{ id: 'u-1', name: 'Олег', home_region_id: 1 }] },
    regions: { data: [{ id: 1, name: 'Київська' }] },
    catalog: { data: [{ id: 'boletus_edulis', name_ua: 'Білий гриб' }] },
    signed: { data: [{ path: 'u-1/a1b2c3d4.jpg', signedUrl: 'https://signed.test/photo?token=x' }] },
  });

  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks'), NOW);

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.total, 42);
  assertEquals(body.limit, 20);
  assertEquals(body.offset, 0);
  assertEquals(body.data.length, 1);
  const item = body.data[0];
  assertEquals(item.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890');
  assertEquals(item.user_id, 'u-1');
  assertEquals(item.user_name, 'Олег');
  assertEquals(item.region_name, 'Київська');
  assertEquals(item.mushroom_type, 'boletus_edulis');
  assertEquals(item.name_ua, 'Білий гриб');
  assertEquals(item.photo_url, 'https://signed.test/photo?token=x');
  assertEquals(item.lat, 50.45);
  assertEquals(item.lng, 30.52);
  assertEquals(item.forest_type, 'pine');
  assertEquals(item.verification_status, 'verified');
  assertEquals(item.weight, 1.5);
  assertEquals(item.is_indicator, false);
  assertEquals(item.is_negative, false);
  assertEquals(item.created_at, '2026-10-13T08:00:00Z');
  // фільтри + пагінація + сортування
  assertEquals(calls.includes('eq:pick_type:public'), true);
  assertEquals(calls.includes('order:created_at:false'), true);
  assertEquals(calls.includes('range:0:19'), true);
  // signed URL batch (один виклик, TTL 600)
  assertEquals(calls.includes('createSignedUrls:u-1/a1b2c3d4.jpg:600'), true);
});

Deno.test('picks handler: mine → eq user_id + period gte', async () => {
  const { readDb, adminDb, calls } = makeClients({
    picks: { data: [], error: null, count: 0 },
  });
  const res = await handlePicksListRequest(readDb, adminDb, 'u-1', new Request('http://localhost/picks?scope=mine&period=24h'), NOW);
  assertEquals(res.status, 200);
  assertEquals(calls.includes('eq:user_id:u-1'), true);
  // 24h до NOW
  assertEquals(calls.some((c) => c.startsWith('gte:created_at:2026-10-12T12:00:00.000Z')), true);
});

Deno.test('picks handler: period=all → без gte', async () => {
  const { readDb, adminDb, calls } = makeClients({ picks: { data: [], error: null, count: 0 } });
  await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?period=all'), NOW);
  assertEquals(calls.some((c) => c.startsWith('gte:')), false);
});

Deno.test('picks handler: mushroom_type фільтр', async () => {
  const { readDb, adminDb, calls } = makeClients({ picks: { data: [], error: null, count: 0 } });
  await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?mushroom_type=boletus_edulis'), NOW);
  assertEquals(calls.includes('eq:mushroom_type:boletus_edulis'), true);
});

// ─── scope=region ───────────────────────────────────────────

Deno.test('picks handler: region без region_slug → 400', async () => {
  const { readDb, adminDb } = makeClients();
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?scope=region'), NOW);
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'missing_region_slug' });
});

Deno.test('picks handler: region unknown slug → 404', async () => {
  const { readDb, adminDb } = makeClients({ rpc: { data: [], error: null } });
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?scope=region&region_slug=atlantis'), NOW);
  assertEquals(res.status, 404);
  assertEquals(await res.json(), { error: 'region_not_found' });
});

Deno.test('picks handler: region → in(user_id, authors of region)', async () => {
  const { readDb, adminDb, calls } = makeClients({
    rpc: { data: [{ id: 1, name: 'Київська', slug: 'kyivska' }], error: null },
    users: { data: [{ id: 'u-1' }, { id: 'u-2' }] },
    picks: { data: [], error: null, count: 0 },
  });
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?scope=region&region_slug=kyivska'), NOW);
  assertEquals(res.status, 200);
  assertEquals(calls.includes('rpc:find_region_by_slug({"slug_input":"kyivska"})'), true);
  assertEquals(calls.includes('eq:home_region_id:1'), true);
  assertEquals(calls.includes('in:user_id:["u-1","u-2"]'), true);
});

Deno.test('picks handler: region без авторів → 200 порожній', async () => {
  const { readDb, adminDb } = makeClients({
    rpc: { data: [{ id: 7, name: 'Порожня', slug: 'empty' }], error: null },
    users: { data: [] },
  });
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks?scope=region&region_slug=empty'), NOW);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { data: [], total: 0, limit: 20, offset: 0 });
});

// ─── error paths ────────────────────────────────────────────

Deno.test('picks handler: picks query error → 500', async () => {
  const { readDb, adminDb } = makeClients({ picks: { data: null, error: { message: 'boom' } } });
  const res = await handlePicksListRequest(readDb, adminDb, null, new Request('http://localhost/picks'), NOW);
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'db_error' });
});

// ─── pure helpers ───────────────────────────────────────────

Deno.test('picks helpers: periodCutoffMs + extractLatLng', () => {
  assertEquals(periodCutoffMs('all', NOW), null);
  assertEquals(periodCutoffMs('24h', NOW), Date.parse('2026-10-12T12:00:00Z'));
  assertEquals(periodCutoffMs('week', NOW), Date.parse('2026-10-06T12:00:00Z'));
  assertEquals(extractLatLng({ type: 'Point', coordinates: [30.52, 50.45] }), { lat: 50.45, lng: 30.52 });
  assertEquals(extractLatLng(null), { lat: null, lng: null });
  assertEquals(extractLatLng('garbage'), { lat: null, lng: null });
});
