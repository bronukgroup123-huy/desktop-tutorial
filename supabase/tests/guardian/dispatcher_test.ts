// ============================================================================
// Dispatcher — mock tests (audit G3 Phase B)
// Перевіряють fallback chain: FCM sent → SMS НЕ надсилається.
// fetch та sendPush/sendSmsViaTextbee мокаються, db — chainable builder.
// ============================================================================

import { assertEquals, assert } from 'jsr:@std/assert';
import type { GuardianAlert, GuardianSession } from '../../functions/_shared/guardian/types.ts';
import type { AlertType } from '../../functions/_shared/guardian/types.ts';
import { dispatchAlert } from '../../functions/_shared/guardian/notifications/dispatcher.ts';

const MIN = 60 * 1000;

function makeAlert(overrides: Partial<GuardianAlert> = {}): GuardianAlert {
  return {
    id: 77,
    session_id: 'sess-1',
    alert_type: 'offline' as AlertType,
    payload: {},
    delivered_at: null,
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

function makeSession(overrides: Partial<GuardianSession> = {}): GuardianSession {
  return {
    id: 'sess-1',
    user_id: 'user-1',
    status: 'active',
    expected_return: new Date(Date.now() - 10 * MIN).toISOString(),
    original_return: new Date(Date.now() - 10 * MIN).toISOString(),
    last_known_coords: { lat: 50.4, lng: 30.5 },
    ...overrides,
  } as GuardianSession;
}

interface MockOpts {
  /** повертається sendPush */
  pushResult: { success: boolean; queued?: boolean; errorMessage?: string };
  /** повертається sendSmsViaTextbee */
  textbeeResult: { success: boolean; queued?: boolean; errorMessage?: string };
  /** повертається sendSms (legacy TurboSMS) */
  legacyResult?: { success: boolean; queued?: boolean; errorMessage?: string };
  /** лишаємо SMS_ENABLED для legacy-шляху */
  smsEnabled?: boolean;
  /** count з rate-limit RPC (default 1 = дозволено) */
  rpcCount?: number;
}

/**
 * Мокає fetch (firebase), модулі textbee/sms через environment — на щастя,
 * dispatcher імпортує їх напряму, тому перевіряємо лише поведлінку БД:
 * які guardian_notifications-рядки створено і який статус встановлено.
 */
function makeDbMock(opts: MockOpts) {
  const inserted: Array<Record<string, unknown>> = [];
  const updates: Array<{ id: unknown; patch: Record<string, unknown> }> = [];
  const alertsUpdated: Array<Record<string, unknown>> = [];
  const rpcCalls: unknown[] = [];

  // Оригінальний fetch зберігаємо
  const originalFetch = globalThis.fetch;

  globalThis.fetch = (() => {
    // sendPush → результат із opts
    return Promise.resolve({
      ok: true,
      json: () =>
        Promise.resolve(
          opts.pushResult.success
            ? { data: { success: true }, messageId: 'msg-1' }
            : { error: { message: opts.pushResult.errorMessage ?? 'push failed' } }
        ),
    } as unknown as Response);
  }) as typeof fetch;

  // Env для textbee/sms — встановлюємо і повертаємо cleanup
  const savedEnv: Record<string, string | undefined> = {
    TEXTBEE_ENABLED: Deno.env.get('TEXTBEE_ENABLED'),
    TEXTBEE_API_KEY: Deno.env.get('TEXTBEE_API_KEY'),
    SMS_ENABLED: Deno.env.get('SMS_ENABLED'),
    GUARDIAN_BASE_URL: Deno.env.get('GUARDIAN_BASE_URL'),
  };
  Deno.env.set('TEXTBEE_ENABLED', 'false'); // щоб textbee не робив реальний fetch
  Deno.env.set('GUARDIAN_BASE_URL', 'https://test.example');
  if (opts.smsEnabled) Deno.env.set('SMS_ENABLED', 'true');

  const tableRows: Record<string, unknown[]> = {
    guardians: [{ id: 'g1', phone: '+380671234567', is_emergency: false }],
    guardian_push_tokens: [{ fcm_token: 'tok-1' }],
    users: [{ name: 'Олег' }],
  };

  const db = {
    from(table: string) {
      const chain: Record<string, unknown> = {
        select() { return chain; },
        eq() { return chain; },
        is() { return chain; },
        gte() { return chain; },
        order() { return chain; },
        limit() { return chain; },
        insert(row: unknown) {
          inserted.push({ table, row });
          return {
            select() {
              return {
                single: () =>
                  Promise.resolve({ data: { id: inserted.length }, error: null }),
              };
            },
          };
        },
        update(patch: Record<string, unknown>) {
          return {
            eq(col: string, val: unknown) {
              updates.push({ id: val, patch });
              return Promise.resolve({ error: null });
            },
          };
        },
        maybeSingle() {
          // users.getPickerName → { name }
          if (table === 'users') {
            return Promise.resolve({ data: { name: 'Олег' }, error: null });
          }
          return Promise.resolve({ data: null, error: null });
        },
        single() {
          if (table === 'users') {
            return Promise.resolve({ data: { name: 'Олег' }, error: null });
          }
          return Promise.resolve({ data: null, error: null });
        },
        then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
          return Promise.resolve({ data: tableRows[table] ?? [], error: null }).then(
            resolve,
            reject
          );
        },
      };
      return chain;
    },
    rpc(name: string, params: unknown) {
      rpcCalls.push({ name, params });
      return Promise.resolve({ data: { count: opts.rpcCount ?? 1 }, error: null });
    },
  };

  const cleanup = () => {
    globalThis.fetch = originalFetch;
    for (const [k, v] of Object.entries(savedEnv)) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  };

  return {
    db: db as unknown as Parameters<typeof dispatchAlert>[0],
    inserted,
    updates,
    alertsUpdated,
    rpcCalls,
    cleanup,
    originalFetch,
    opts,
  };
}

// ─── A. FCM success → SMS НЕ надсилається ──────────────────────────────────

Deno.test('dispatcher: FCM sent → SMS НЕ створюється', async () => {
  const mock = makeDbMock({
    pushResult: { success: true },
    textbeeResult: { success: false, errorMessage: 'textbee_disabled' },
  });

  try {
    await dispatchAlert(mock.db, makeAlert(), makeSession());

    const pushRows = mock.inserted.filter((r) => (r.row as { channel: string }).channel === 'push');
    const smsRows = mock.inserted.filter((r) => (r.row as { channel: string }).channel === 'sms');

    assertEquals(smsRows.length, 0, 'SMS не має створюватись коли push sent');
    // Rate limit теж не має спрацьовувати
    const rlCalls = mock.rpcCalls.filter(
      (c) => (c as { name: string }).name === 'check_and_increment_rate_limit'
    );
    assertEquals(rlCalls.length, 0);
  } finally {
    mock.cleanup();
  }
});

// ─── B. FCM failed + textbee disabled → SMS-рядок створено з failed ────────

Deno.test('dispatcher: FCM failed + textbee disabled → sms row + failed status', async () => {
  const mock = makeDbMock({
    pushResult: { success: false, errorMessage: 'firebase_disabled' },
    textbeeResult: { success: false, errorMessage: 'textbee_disabled' },
  });

  try {
    // overdue_hard: requiresSms=true → SMS шлях активний
    await dispatchAlert(mock.db, makeAlert({ alert_type: 'overdue_hard' }), makeSession());

    const smsRows = mock.inserted.filter((r) => (r.row as { channel: string }).channel === 'sms');
    assertEquals(smsRows.length, 1, 'sms-рядок створено');

    // UPDATE саме для sms-рядка (push-UPDATE має інший id)
    const smsUpdate = mock.updates.find(
      (u) =>
        (u.patch as { error_message?: string }).error_message?.includes('textbee')
    );
    assert(smsUpdate, 'є UPDATE статусу для sms');
    assertEquals((smsUpdate!.patch as { status: string }).status, 'failed');
    assert(
      (smsUpdate!.patch as { error_message: string }).error_message.includes(
        'textbee_disabled'
      ),
      'error_message містить причину'
    );
  } finally {
    mock.cleanup();
  }
});

// ─── C. rate limit: RPC count > ліміту → skipped, sms НЕ створюється ───────

Deno.test('dispatcher: rate limit exceeded → sms НЕ створюється', async () => {
  const mock = makeDbMock({
    pushResult: { success: false, errorMessage: 'firebase_disabled' },
    textbeeResult: { success: false, errorMessage: 'textbee_disabled' },
  });
  // Перебиваємо rpc: rate limit переносить
  const db = {
    from: mock.db.from,
    rpc() {
      return Promise.resolve({ data: { count: 99 }, error: null });
    },
  } as unknown as Parameters<typeof dispatchAlert>[0];

  try {
    const result = await dispatchAlert(
      db,
      makeAlert({ alert_type: 'overdue_hard' }),
      makeSession()
    );

    const smsRows = mock.inserted.filter((r) => (r.row as { channel: string }).channel === 'sms');
    assertEquals(smsRows.length, 0, 'rate limit блокує sms');
    assertEquals(result.skipped, 1, 'skipped рахується');
  } finally {
    mock.cleanup();
  }
});

// ─── D. Guards: нет phone + нет tokens → skipped ───────────────────────────

Deno.test('dispatcher: без phone і без tokens → skipped', async () => {
  const mock = makeDbMock({
    pushResult: { success: true },
    textbeeResult: { success: false, errorMessage: 'textbee_disabled' },
  });

  const originalFrom = mock.db.from.bind(mock.db);
  const db = {
    from(table: string) {
      const chain = originalFrom(table) as unknown as Record<string, unknown>;
      if (table === 'guardians') {
        const q: Record<string, unknown> = {
          select: () => q,
          eq: () => q,
          is: () =>
            Promise.resolve({
              data: [{ id: 'g1', phone: null, is_emergency: false }],
              error: null,
            }),
          then: (res: (v: unknown) => unknown) =>
            Promise.resolve({
              data: [{ id: 'g1', phone: null, is_emergency: false }],
              error: null,
            }).then(res),
        };
        return q;
      }
      if (table === 'guardian_push_tokens') {
        const q: Record<string, unknown> = {
          select: () => q,
          eq: () => q,
          is: () => Promise.resolve({ data: [], error: null }),
          then: (res: (v: unknown) => unknown) =>
            Promise.resolve({ data: [], error: null }).then(res),
        };
        return q;
      }
      return chain;
    },
    rpc: () => Promise.resolve({ data: { count: 1 }, error: null }),
  } as unknown as Parameters<typeof dispatchAlert>[0];

  try {
    const result = await dispatchAlert(
      db,
      makeAlert({ alert_type: 'overdue_hard' }),
      makeSession()
    );
    assertEquals(result.skipped, 1, 'без phone і без tokens → skipped');
    assertEquals(
      mock.inserted.filter((r) => (r.row as { channel: string }).channel === 'sms').length,
      0
    );
  } finally {
    mock.cleanup();
  }
});
