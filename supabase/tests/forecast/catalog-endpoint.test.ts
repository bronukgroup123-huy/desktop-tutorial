import { assertEquals } from 'jsr:@std/assert';
import {
  parseCatalogQuery,
  handleCatalogRequest,
  CATALOG_DEFAULT_LIMIT,
  CATALOG_MAX_LIMIT,
} from '../../functions/_shared/forecast/catalog-endpoint.ts';
import type { CatalogDbClient } from '../../functions/_shared/forecast/catalog-endpoint.ts';

// Мок Supabase-клієнта: thenable-ланцюжок from().select().[or|in|contains]().order().range()
function makeDbMock(
  response: { data: unknown; error: unknown; count?: number },
): { db: CatalogDbClient; calls: string[] } {
  const calls: string[] = [];
  const builder = {
    select(cols: string, opts?: Record<string, unknown>) {
      calls.push(`select:${cols}:${JSON.stringify(opts ?? {})}`);
      return builder;
    },
    or(expr: string) { calls.push(`or:${expr}`); return builder; },
    contains(col: string, val: unknown) {
      calls.push(`contains:${col}:${JSON.stringify(val)}`);
      return builder;
    },
    in(col: string, vals: unknown[]) {
      calls.push(`in:${col}:${JSON.stringify(vals)}`);
      return builder;
    },
    order(col: string, opts?: { ascending?: boolean }) {
      calls.push(`order:${col}:${opts?.ascending}`);
      return builder;
    },
    range(from: number, to: number) {
      calls.push(`range:${from}:${to}`);
      return builder;
    },
    then(resolve: (v: unknown) => void) {
      return Promise.resolve(response).then(resolve);
    },
  };
  const db = {
    from(table: string) {
      calls.push(`from:${table}`);
      return builder;
    },
  };
  return { db, calls };
}

const SAMPLE_ROW = {
  id: 'boletus_edulis',
  name_ua: 'Білий гриб',
  name_lat: 'Boletus edulis',
  edibility: 'edible',
  edibility_label: 'Їстівний',
  red_listed: false,
  rarity: '',
  has_photo: true,
  top20: true,
  popular: false,
  months: [6, 7, 8, 9, 10, 11],
  peak_months: [9, 10],
  zones: ['kyivska', 'lvivska'],
  attrs: { color: [], stem: [], tree: ['pine', 'oak'], season: ['summer', 'autumn'] },
  photos: [{ url: 'https://example.test/b.webp' }],
};

// ─── parseCatalogQuery ──────────────────────────────────────

Deno.test('catalog parse: empty query → defaults {limit:50, offset:0}', () => {
  const r = parseCatalogQuery(new URL('http://localhost/catalog'));
  assertEquals(r, { limit: CATALOG_DEFAULT_LIMIT, offset: 0 });
});

Deno.test('catalog parse: limit=200 → error (>100)', () => {
  const r = parseCatalogQuery(new URL('http://localhost/catalog?limit=200'));
  assertEquals(r, { error: 'limit_out_of_range' });
});

Deno.test('catalog parse: limit=abc → error', () => {
  const r = parseCatalogQuery(new URL('http://localhost/catalog?limit=abc'));
  assertEquals(r, { error: 'invalid_pagination' });
});

Deno.test('catalog parse: offset=-1 → error', () => {
  const r = parseCatalogQuery(new URL('http://localhost/catalog?offset=-1'));
  assertEquals(r, { error: 'invalid_offset' });
});

Deno.test('catalog parse: forest=pine,oak → [pine,oak]', () => {
  const r = parseCatalogQuery(new URL('http://localhost/catalog?forest=pine,oak'));
  assertEquals(r, { limit: 50, offset: 0, forest: ['pine', 'oak'] });
});

Deno.test('catalog parse: edible=true → boolean true', () => {
  const r = parseCatalogQuery(new URL('http://localhost/catalog?edible=true'));
  assertEquals('edible' in r && r.edible, true);
});

// ─── handleCatalogRequest ───────────────────────────────────

Deno.test('catalog handler: OPTIONS → 204 + CORS', async () => {
  const { db } = makeDbMock({ data: [], error: null });
  const res = await handleCatalogRequest(db, new Request('http://localhost/catalog', { method: 'OPTIONS' }));
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), '*');
});

Deno.test('catalog handler: non-GET (POST) → 405', async () => {
  const { db } = makeDbMock({ data: [], error: null });
  const res = await handleCatalogRequest(db, new Request('http://localhost/catalog', { method: 'POST' }));
  assertEquals(res.status, 405);
  assertEquals(await res.json(), { error: 'method_not_allowed' });
});

Deno.test('catalog handler: GET → 200 + {data(camelCase), total, limit, offset}', async () => {
  const { db, calls } = makeDbMock({ data: [SAMPLE_ROW], error: null, count: 326 });

  const res = await handleCatalogRequest(db, new Request('http://localhost/catalog?limit=20&offset=40'));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.total, 326);
  assertEquals(body.limit, 20);
  assertEquals(body.offset, 40);
  // camelCase через catalogRowToEntry + пагінація/сортування
  assertEquals(body.data[0].id, 'boletus_edulis');
  assertEquals(body.data[0].nameUa, 'Білий гриб');
  assertEquals(body.data[0].peakMonths, [9, 10]);
  assertEquals(calls, [
    'from:mushroom_catalog',
    'select:id, name_ua, name_lat, edibility, edibility_label, red_listed, rarity, has_photo, top20, popular, months, peak_months, zones, attrs, photos, ai_recognition, features:{"count":"exact"}',
    'order:name_ua:true',
    'range:40:59',
  ]);
});

Deno.test('catalog handler: forest=pine,oak → contains OR по attrs->tree', async () => {
  const { db, calls } = makeDbMock({ data: [], error: null, count: 0 });
  const res = await handleCatalogRequest(db, new Request('http://localhost/catalog?forest=pine,oak'));
  assertEquals(res.status, 200);
  assertEquals(calls.includes('or:attrs->tree.cs.["pine"],attrs->tree.cs.["oak"]'), true);
});

Deno.test('catalog handler: season=autumn → contains attrs->season', async () => {
  const { db, calls } = makeDbMock({ data: [], error: null, count: 0 });
  await handleCatalogRequest(db, new Request('http://localhost/catalog?season=autumn'));
  assertEquals(calls.includes('contains:attrs->season:["autumn"]'), true);
});

Deno.test('catalog handler: season=wintery → 400 invalid_season', async () => {
  const { db } = makeDbMock({ data: [], error: null });
  const res = await handleCatalogRequest(db, new Request('http://localhost/catalog?season=wintery'));
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'invalid_season' });
});

Deno.test('catalog handler: edible=false → edibility IN inedible/poisonous/deadly', async () => {
  const { db, calls } = makeDbMock({ data: [], error: null, count: 0 });
  await handleCatalogRequest(db, new Request('http://localhost/catalog?edible=false'));
  assertEquals(calls.includes('in:edibility:["inedible","poisonous","deadly_poisonous"]'), true);
});

Deno.test('catalog handler: search=білий → ILIKE or з екрануванням', async () => {
  const { db, calls } = makeDbMock({ data: [], error: null, count: 0 });
  await handleCatalogRequest(db, new Request('http://localhost/catalog?search=білий'));
  assertEquals(calls.includes('or:name_ua.ilike.%білий%,name_lat.ilike.%білий%'), true);
});

Deno.test('catalog handler: DB error → 500 db_error', async () => {
  const { db } = makeDbMock({ data: null, error: { message: 'boom' } });
  const res = await handleCatalogRequest(db, new Request('http://localhost/catalog'));
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'db_error' });
});
