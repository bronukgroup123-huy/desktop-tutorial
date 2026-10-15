// ============================================================================
// Rate limit — unit tests (audit G3 Phase B)
// Мок db (chainable builder + rpc), як engine.test.ts.
// ============================================================================

import { assertEquals, assert } from 'jsr:@std/assert';
import {
  checkAndIncrementRateLimit,
  RATE_LIMITS,
  rateLimitExceeded,
} from '../../functions/_shared/guardian/notifications/rate-limit.ts';

function makeDb(opts: {
  rpcResult?: { data: { count: number } | null; error: unknown };
  upsertResult?: { data: { count: number } | null; error: unknown };
  rpcShouldFail?: boolean;
}) {
  const rpcCalls: unknown[] = [];
  const upsertCalls: unknown[] = [];

  const db = {
    rpc(name: string, params: unknown) {
      rpcCalls.push({ name, params });
      if (opts.rpcShouldFail) {
        return Promise.resolve({ data: null, error: { message: 'rpc missing' } });
      }
      return Promise.resolve(
        opts.rpcResult ?? { data: { count: 1 }, error: null }
      );
    },
    from(table: string) {
      assertEquals(table, 'notification_rate_limit');
      const chain: Record<string, unknown> = {
        upsert(row: unknown, cfg: unknown) {
          upsertCalls.push({ row, cfg });
          return chain;
        },
        select() { return chain; },
        then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
          return Promise.resolve(
            opts.upsertResult ?? { data: { count: 1 }, error: null }
          ).then(resolve, reject);
        },
        single() {
          return Promise.resolve(
            opts.upsertResult ?? { data: { count: 1 }, error: null }
          );
        },
      };
      return chain;
    },
  };

  return {
    db: db as unknown as Parameters<typeof checkAndIncrementRateLimit>[0],
    rpcCalls,
    upsertCalls,
  };
}

// ─── RPC-шлях (основний) ────────────────────────────────────────────────────

Deno.test('rate-limit: RPC success, count=1 → allowed', async () => {
  const { db, rpcCalls } = makeDb({ rpcResult: { data: { count: 1 }, error: null } });
  const r = await checkAndIncrementRateLimit(db, 'u1', 'sms');

  assertEquals(r.allowed, true);
  assertEquals(r.count, 1);
  assertEquals(r.remaining, RATE_LIMITS.sms - 1);
  assertEquals(rpcCalls.length, 1);
  assertEquals(
    (rpcCalls[0] as { name: string }).name,
    'check_and_increment_rate_limit'
  );
});

Deno.test('rate-limit: count=5 (ліміт) → дозволено', async () => {
  const { db } = makeDb({ rpcResult: { data: { count: 5 }, error: null } });
  const r = await checkAndIncrementRateLimit(db, 'u1', 'sms');

  assertEquals(r.allowed, true, '5/5 ще в межах');
  assertEquals(r.remaining, 0);
});

Deno.test('rate-limit: count=6 → ЗАБЛОКОВАНО (ліміт 5/год)', async () => {
  const { db } = makeDb({ rpcResult: { data: { count: 6 }, error: null } });
  const r = await checkAndIncrementRateLimit(db, 'u1', 'sms');

  assertEquals(r.allowed, false);
  assertEquals(r.remaining, 0);
  assertEquals(rateLimitExceeded(r), true);
});

Deno.test('rate-limit: telegram ліміт > sms ліміту', async () => {
  const { db } = makeDb({ rpcResult: { data: { count: 7 }, error: null } });
  const rSms = await checkAndIncrementRateLimit(db, 'u1', 'sms');
  const rTg = await checkAndIncrementRateLimit(db, 'u1', 'telegram');

  assertEquals(rSms.allowed, false, '7 > 5');
  assertEquals(rTg.allowed, true, '7 <= 10');
});

Deno.test('rate-limit: explicit limit override', async () => {
  const { db } = makeDb({ rpcResult: { data: { count: 2 }, error: null } });
  const r = await checkAndIncrementRateLimit(db, 'u1', 'sms', 1);
  assertEquals(r.allowed, false, 'limit=1, count=2');
});

Deno.test('rate-limit: RPC fail → fallback upsert', async () => {
  const { db, upsertCalls } = makeDb({
    rpcShouldFail: true,
    upsertResult: { data: { count: 3 }, error: null },
  });
  const r = await checkAndIncrementRateLimit(db, 'u1', 'sms');

  assertEquals(r.count, 3);
  assertEquals(r.allowed, true, '3 <= 5');
  assertEquals(upsertCalls.length, 1);
  assertEquals(
    (upsertCalls[0] as { cfg: { onConflict: string } }).cfg.onConflict,
    'user_id,channel,window_start'
  );
});

Deno.test('rate-limit: RPC і upsert обидва fail → fail-open (не блокуємо тривогу)', async () => {
  const { db } = makeDb({
    rpcShouldFail: true,
    upsertResult: { data: null, error: { message: 'denied' } },
  });
  const r = await checkAndIncrementRateLimit(db, 'u1', 'sms');

  // Для безпекових нотифікацій краще надіслати, ніж втратити тривогу.
  assertEquals(r.allowed, true);
  assertEquals(r.count, 1);
});

Deno.test('rate-limit: різні users — незалежні лічильники', async () => {
  const counts: Record<string, number> = { u1: 1, u2: 1 };
  const db = {
    rpc(_n: string, params: unknown) {
      const p = params as { p_user_id: string };
      return Promise.resolve({ data: { count: counts[p.p_user_id] }, error: null });
    },
  } as unknown as Parameters<typeof checkAndIncrementRateLimit>[0];

  const a = await checkAndIncrementRateLimit(db, 'u1', 'sms');
  const b = await checkAndIncrementRateLimit(db, 'u2', 'sms');

  assertEquals(a.allowed, true);
  assertEquals(b.allowed, true);
});

// ─── Race-safety (документуємо контракт, не симулюємо паралелізм) ───────────

Deno.test('rate-limit: ON CONFLICT DO UPDATE — атомарний інкремент (контракт)', async () => {
  const { db, rpcCalls } = makeDb({ rpcResult: { data: { count: 5 }, error: null } });

  await checkAndIncrementRateLimit(db, 'u1', 'sms');

  const call = rpcCalls[0] as { name: string; params: Record<string, unknown> };
  assertEquals(call.name, 'check_and_increment_rate_limit');
  assert('p_user_id' in call.params);
  assert('p_channel' in call.params);
  assert('p_window_start' in call.params);

  // Міграція 20260912000019 використовує ON CONFLICT DO UPDATE,
  // тому паралельні виклики не втрачають інкременти.
  assert(call.params.p_window_start !== undefined, 'window_start передається');
});
