// ============================================================================
// SOS — unit tests (audit G5)
// Мок db: chainable query builder (той самий патерн, що tick.test.ts).
// ============================================================================
import { assert, assertEquals } from 'jsr:@std/assert';
import { activateSos, cancelSos } from '../../functions/_shared/guardian/sos.ts';
import type { GuardianSession } from '../../functions/_shared/guardian/types.ts';

const SESSION_ID = 'sess-sos-1';

function makeSession(overrides: Partial<GuardianSession> = {}): GuardianSession {
  return {
    id: SESSION_ID,
    user_id: 'user-1',
    status: 'active',
    previous_status: null,
    expected_return: new Date(Date.now() + 3600000).toISOString(),
    original_return: new Date(Date.now() + 3600000).toISOString(),
    started_at: new Date(Date.now() - 3600000).toISOString(),
    closing_started_at: null,
    closed_at: null,
    recoverable_until: null,
    last_known_coords: null,
    last_known_at: new Date(Date.now() - 300000).toISOString(),
    last_battery_pct: 80,
    last_signal_strength: 4,
    exit_detected_at: null,
    sos_activated_at: null,
    overdue_level: null,
    settings: {
      overdue_thresholds: { soft: 0, medium: 30, hard: 90 },
      stationary_threshold_min: 30,
      offline_threshold_min: 60,
      grace_period_min: 5,
      recovery_window_min: 30,
    },
    created_at: new Date(Date.now() - 3600000).toISOString(),
    updated_at: new Date(Date.now() - 3600000).toISOString(),
    ...overrides,
  } as GuardianSession;
}

interface UpdateRecord {
  updates: Record<string, unknown>;
  eqs: Array<[string, unknown]>;
}

interface MockOpts {
  session: GuardianSession;
  existingSosAlertId: number | null;
}

function makeDbMock(opts: MockOpts) {
  const updates: UpdateRecord[] = [];
  const alertsInserted: Array<{ alert_type: string; payload: unknown }> = [];

  const db = {
    from(table: string) {
      const eqs: Array<[string, unknown]> = [];

      const chain = {
        select() { return chain; },
        insert(row: unknown) {
          if (table === 'guardian_alerts') {
            alertsInserted.push(row as { alert_type: string; payload: unknown });
          }
          return {
            select() {
              return {
                single() {
                  return Promise.resolve({ data: { id: 999 }, error: null });
                },
              };
            },
          };
        },
        update(upd: Record<string, unknown>) {
          updates.push({ updates: upd, eqs });
          return chain;
        },
        eq(col: string, val: unknown) { eqs.push([col, val]); return chain; },
        order() { return chain; },
        limit() { return chain; },
        maybeSingle() {
          if (table === 'guardian_alerts') {
            if (opts.existingSosAlertId !== null) {
              return Promise.resolve({ data: { id: opts.existingSosAlertId }, error: null });
            }
            return Promise.resolve({ data: null, error: null });
          }
          return Promise.resolve({ data: null, error: null });
        },
        single() {
          return Promise.resolve({ data: opts.session, error: null });
        },
        then(
          resolve: (v: unknown) => unknown,
          reject?: (e: unknown) => unknown
        ) {
          return Promise.resolve({ data: null, error: null }).then(resolve, reject);
        },
      };
      return chain;
    },
    rpc() {
      return Promise.resolve({ data: null, error: null });
    },
  };

  return {
    db: db as unknown,
    updates,
    alertsInserted,
  };
}

Deno.test('activateSos: first activation sets status=sos and saves previous_status', async () => {
  const session = makeSession({ status: 'active', previous_status: null });
  const { db, updates, alertsInserted } = makeDbMock({
    session,
    existingSosAlertId: null,
  });

  const result = await activateSos(db as any, session);

  assertEquals(result.previous_status, 'active');
  assertEquals(result.alert_id, 999);

  // UPDATE викликався з правильним eq("status", "active")
  assertEquals(updates.length, 1);
  assertEquals(updates[0].updates.status, 'sos');
  assertEquals(updates[0].updates.previous_status, 'active');
  assertEquals(typeof updates[0].updates.sos_activated_at, 'string');
  assertEquals(updates[0].eqs.some(([c, v]) => c === 'status' && v === 'active'), true);

  // alert створюється
  assertEquals(alertsInserted.length, 1);
  assertEquals(alertsInserted[0].alert_type, 'sos');
});

Deno.test('activateSos: idempotency — second call returns existing alert, no UPDATE', async () => {
  const session = makeSession({ status: 'sos', previous_status: 'active' });
  const { db, updates, alertsInserted } = makeDbMock({
    session,
    existingSosAlertId: 42,
  });

  const result = await activateSos(db as any, session);

  assertEquals(result.alert_id, 42);
  assertEquals(result.previous_status, 'sos');

  // UPDATE НЕ викликався (idempotency — early return)
  assertEquals(updates.length, 0);
  assertEquals(alertsInserted.length, 0);
});

Deno.test('activateSos: closing status → invalidTransition', async () => {
  const session = makeSession({ status: 'closing' });
  const { db } = makeDbMock({
    session,
    existingSosAlertId: null,
  });

  let caught: unknown = null;
  try {
    await activateSos(db as any, session);
  } catch (e) {
    caught = e;
  }
  assert(caught instanceof Error);
  assert((caught as Error).message.includes('Cannot transition'));
});

Deno.test('cancelSos: returns to previous_status', async () => {
  const session = makeSession({ status: 'sos', previous_status: 'stale' });
  const { db, updates, alertsInserted } = makeDbMock({
    session,
    existingSosAlertId: null,
  });

  const result = await cancelSos(db as any, session);

  // UPDATE з правильним target status та previous_status=null
  assertEquals(updates.length, 1);
  assertEquals(updates[0].updates.status, 'stale');
  assertEquals(updates[0].updates.previous_status, null);
  assertEquals(updates[0].eqs.some(([c, v]) => c === 'status' && v === 'sos'), true);

  // alert recovered з sos_cancelled
  assertEquals(alertsInserted.length, 1);
  assertEquals(alertsInserted[0].alert_type, 'recovered');
  assertEquals((alertsInserted[0].payload as any).action, 'sos_cancelled');
});

Deno.test('cancelSos: null previous_status → fallback active', async () => {
  const session = makeSession({ status: 'sos', previous_status: null });
  const { db, updates } = makeDbMock({
    session,
    existingSosAlertId: null,
  });

  const result = await cancelSos(db as any, session);

  assertEquals(updates.length, 1);
  assertEquals(updates[0].updates.status, 'active');
});

Deno.test('cancelSos: not in sos → invalidTransition', async () => {
  const session = makeSession({ status: 'active' });
  const { db } = makeDbMock({
    session,
    existingSosAlertId: null,
  });

  let caught: unknown = null;
  try {
    await cancelSos(db as any, session);
  } catch (e) {
    caught = e;
  }
  assert(caught instanceof Error);
  assert((caught as Error).message.includes('Cannot transition'));
});
