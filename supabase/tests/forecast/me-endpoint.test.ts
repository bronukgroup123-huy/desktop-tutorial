import { assertEquals } from 'jsr:@std/assert';
import {
  validateUpdateMe,
  handleMeRequest,
  handlePatchMe,
} from '../../functions/_shared/forecast/me-endpoint.ts';
import type { MeDbClient } from '../../functions/_shared/forecast/me-endpoint.ts';

// Мок Supabase-клієнта: from('users'|'regions') thenable-ланцюжок + update + rpc
function makeDbMock(cfg: {
  user?: Record<string, unknown> | null;
  region?: Record<string, unknown> | null;
  rpc?: { data: unknown; error: unknown };
  updateError?: unknown;
} = {}): { db: MeDbClient; calls: string[] } {
  const calls: string[] = [];

  const db = {
    from(table: string) {
      calls.push(`from:${table}`);
      // універсальний thenable-ланцюжок: update|select|eq → maybeSingle або await
      const builder: Record<string, any> = {
        eq(col: string, val: unknown) {
          calls.push(`eq:${table}.${col}:${String(val)}`);
          return builder;
        },
        select(cols: string) {
          calls.push(`select:${table}.${cols}`);
          return builder;
        },
        update(obj: Record<string, unknown>) {
          calls.push(`update:${table}:${JSON.stringify(obj)}`);
          return builder;
        },
        maybeSingle() {
          calls.push(`maybeSingle:${table}`);
          if (table === 'users') {
            return Promise.resolve({ data: cfg.user ?? null, error: null });
          }
          return Promise.resolve({ data: cfg.region ?? null, error: null });
        },
        then(resolve: (v: unknown) => void) {
          const val = cfg.updateError != null
            ? { data: null, error: cfg.updateError }
            : { data: { id: 'u-1' }, error: null };
          return Promise.resolve(val).then(resolve);
        },
      };
      return builder;
    },
    rpc(fn: string, params: Record<string, unknown>) {
      calls.push(`rpc:${fn}(${JSON.stringify(params)})`);
      return Promise.resolve(cfg.rpc ?? { data: null, error: null });
    },
  };

  return { db: db as unknown as MeDbClient, calls };
}

const USER_ROW = {
  id: 'u-1',
  name: 'Олег',
  rating: 42,
  total_verified_picks: 7,
  home_region_id: 1,
  created_at: '2026-09-01T10:00:00Z',
};

const REGION_ROW = { id: 1, slug: 'kyiv', name: 'Київ' };

// ─── validateUpdateMe ───────────────────────────────────────

Deno.test('me validate: {} → 400 invalid_body', () => {
  assertEquals(validateUpdateMe({}), { ok: false, error: 'invalid_body', status: 400 });
});

Deno.test('me validate: { name: "Олег" } → ok', () => {
  assertEquals(validateUpdateMe({ name: 'Олег' }), { ok: true, input: { name: 'Олег' } });
});

Deno.test('me validate: { name: "" } → 400 invalid_name', () => {
  assertEquals(validateUpdateMe({ name: '' }), { ok: false, error: 'invalid_name', status: 400 });
});

Deno.test('me validate: { name: 123 } → 400 invalid_name', () => {
  assertEquals(validateUpdateMe({ name: 123 }), { ok: false, error: 'invalid_name', status: 400 });
});

Deno.test('me validate: name 51 символ → 400', () => {
  assertEquals(validateUpdateMe({ name: 'a'.repeat(51) }), { ok: false, error: 'invalid_name', status: 400 });
});

Deno.test('me validate: { home_region_slug: "kyiv" } → ok', () => {
  assertEquals(validateUpdateMe({ home_region_slug: 'kyiv' }), { ok: true, input: { home_region_slug: 'kyiv' } });
});

Deno.test('me validate: { home_region_slug: "INVALID!" } → 400', () => {
  assertEquals(validateUpdateMe({ home_region_slug: 'INVALID!' }), { ok: false, error: 'invalid_region_slug', status: 400 });
});

Deno.test('me validate: unknown fields ignored', () => {
  assertEquals(validateUpdateMe({ name: 'Олег', extra: 'x' }), { ok: true, input: { name: 'Олег' } });
});

Deno.test('me validate: name trim', () => {
  assertEquals(validateUpdateMe({ name: '  Олег  ' }), { ok: true, input: { name: 'Олег' } });
});

// ─── GET /me ────────────────────────────────────────────────

Deno.test('me GET: mock db → 200 + профіль з home_region', async () => {
  const { db, calls } = makeDbMock({ user: USER_ROW, region: REGION_ROW });
  const res = await handleMeRequest(db, 'u-1', new Request('http://localhost/me'));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body, {
    data: {
      id: 'u-1',
      name: 'Олег',
      rating: 42,
      total_verified_picks: 7,
      home_region: { id: 1, slug: 'kyiv', name: 'Київ' },
      created_at: '2026-09-01T10:00:00Z',
    },
  });
  assertEquals(calls.includes('eq:users.id:u-1'), true);
  assertEquals(calls.includes('eq:regions.id:1'), true);
});

Deno.test('me GET: users row missing → 404', async () => {
  const { db } = makeDbMock({ user: null });
  const res = await handleMeRequest(db, 'u-1', new Request('http://localhost/me'));
  assertEquals(res.status, 404);
  assertEquals(await res.json(), { error: 'me_not_found' });
});

Deno.test('me GET: home_region_id=null → home_region null', async () => {
  const { db } = makeDbMock({ user: { ...USER_ROW, home_region_id: null } });
  const res = await handleMeRequest(db, 'u-1', new Request('http://localhost/me'));
  const body = await res.json();
  assertEquals(body.data.home_region, null);
});

// ─── PATCH /me ──────────────────────────────────────────────

Deno.test('me PATCH: невідомий slug → 404 region_not_found', async () => {
  const { db } = makeDbMock({ user: USER_ROW, rpc: { data: [], error: null } });
  const res = await handlePatchMe(
    db, 'u-1',
    new Request('http://localhost/me', { method: 'PATCH', body: JSON.stringify({ home_region_slug: 'atlantis' }) }),
  );
  assertEquals(res.status, 404);
  assertEquals(await res.json(), { error: 'region_not_found' });
});

Deno.test('me PATCH: успіх → 200 + оновлений профіль', async () => {
  const { db, calls } = makeDbMock({
    user: USER_ROW,
    region: REGION_ROW,
    rpc: { data: [{ id: 1, slug: 'kyiv', name: 'Київ' }], error: null },
  });
  const res = await handlePatchMe(
    db, 'u-1',
    new Request('http://localhost/me', {
      method: 'PATCH',
      body: JSON.stringify({ name: 'Олег', home_region_slug: 'kyiv' }),
    }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.data.name, 'Олег');
  assertEquals(body.data.home_region, { id: 1, slug: 'kyiv', name: 'Київ' });
  assertEquals(calls.includes('rpc:find_region_by_slug({"slug_input":"kyiv"})'), true);
  assertEquals(calls.includes('update:users:{"name":"Олег","home_region_id":1}'), true);
  assertEquals(calls.includes('eq:users.id:u-1'), true);
});

Deno.test('me PATCH: invalid json → 400', async () => {
  const { db } = makeDbMock({ user: USER_ROW });
  const res = await handlePatchMe(
    db, 'u-1',
    new Request('http://localhost/me', { method: 'PATCH', body: 'not json' }),
  );
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'invalid_json' });
});

Deno.test('me PATCH: {} → 400 invalid_body', async () => {
  const { db } = makeDbMock({ user: USER_ROW });
  const res = await handlePatchMe(
    db, 'u-1',
    new Request('http://localhost/me', { method: 'PATCH', body: JSON.stringify({}) }),
  );
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'invalid_body' });
});

Deno.test('me PATCH: тільки name — без RPC', async () => {
  const { db, calls } = makeDbMock({ user: USER_ROW });
  const res = await handlePatchMe(
    db, 'u-1',
    new Request('http://localhost/me', { method: 'PATCH', body: JSON.stringify({ name: 'Петро' }) }),
  );
  assertEquals(res.status, 200);
  assertEquals(calls.some((c) => c.startsWith('rpc:')), false);
  assertEquals(calls.includes('update:users:{"name":"Петро"}'), true);
});

// ─── method dispatch ────────────────────────────────────────

Deno.test('me dispatch: OPTIONS → 204', async () => {
  const { db } = makeDbMock({ user: USER_ROW });
  const res = await handleMeRequest(db, 'u-1', new Request('http://localhost/me', { method: 'OPTIONS' }));
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), '*');
});

Deno.test('me dispatch: DELETE → 405', async () => {
  const { db } = makeDbMock({ user: USER_ROW });
  const res = await handleMeRequest(db, 'u-1', new Request('http://localhost/me', { method: 'DELETE' }));
  assertEquals(res.status, 405);
  assertEquals(await res.json(), { error: 'method_not_allowed' });
});
