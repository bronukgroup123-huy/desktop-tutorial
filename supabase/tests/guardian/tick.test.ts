// ============================================================================
// Guardian tick — unit tests (audit G1-p2)
// Мок db: chainable query builder (той самий патерн, що engine.test.ts:95-140)
// ============================================================================

import {
  assertEquals,
  assert,
} from 'jsr:@std/assert';
import { processSession } from '../../functions/guardian-tick/index.ts';
import type { GuardianSession } from '../../functions/_shared/guardian/types.ts';

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

function makeSession(overrides: Partial<GuardianSession> = {}): GuardianSession {
  return {
    id: 'sess-1',
    user_id: 'user-1',
    status: 'active',
    previous_status: null,
    expected_return: new Date(Date.now() - 60 * MIN).toISOString(),
    original_return: new Date(Date.now() - 60 * MIN).toISOString(),
    started_at: new Date(Date.now() - 3 * HOUR).toISOString(),
    closing_started_at: null,
    closed_at: null,
    recoverable_until: null,
    last_known_coords: null,
    last_known_at: new Date(Date.now() - 5 * MIN).toISOString(),
    last_battery_pct: 90,
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
    created_at: new Date(Date.now() - 3 * HOUR).toISOString(),
    updated_at: new Date(Date.now() - 3 * HOUR).toISOString(),
    ...overrides,
  } as GuardianSession;
}

interface UpdateRecord {
  updates: Record<string, unknown>;
  eqs: Array<[string, unknown]>;
}

interface MockOpts {
  session: GuardianSession;
  /** alerts, що "вже є" в БД: alert_type → created_at ISO */
  existingAlerts?: Record<string, string>;
  /** трек-точки для analyzeMovement (швидкості) */
  trackSpeeds?: number[];
}

function makeDbMock(opts: MockOpts) {
  const updates: UpdateRecord[] = [];
  const alertsInserted: Array<{ alert_type: string; payload: unknown }> = [];

  const db = {
    from(table: string) {
      const eqs: Array<[string, unknown]> = [];
      const gtes: Array<[string, unknown]> = [];

      /** Знаходить "існуючий" alert з урахуванням gte-фільтра (cooldown) */
      const findExisting = (): { id: number; created_at: string } | null => {
        const typeEq = eqs.find(([c]) => c === 'alert_type');
        if (!typeEq) return null;
        const existing = opts.existingAlerts?.[String(typeEq[1])];
        if (!existing) return null;
        // gte("created_at", cutoff) — фільтр за вікном cooldown
        const gteCreatedAt = gtes.find(([c]) => c === 'created_at');
        if (gteCreatedAt && new Date(existing).getTime() < new Date(String(gteCreatedAt[1])).getTime()) {
          return null;
        }
        return { id: 1, created_at: existing };
      };

      const chain: Record<string, unknown> = {
        select() { return chain; },
        insert(row: unknown) {
          if (table === 'guardian_alerts') {
            alertsInserted.push(row as { alert_type: string; payload: unknown });
          }
          return {
            select() {
              return Promise.resolve({ data: { id: 1 }, error: null });
            },
          };
        },
        update(upd: Record<string, unknown>) {
          updates.push({ updates: upd, eqs });
          return chain;
        },
        eq(col: string, val: unknown) { eqs.push([col, val]); return chain; },
        neq() { return chain; },
        gte(col: string, val: unknown) { gtes.push([col, val]); return chain; },
        order() { return chain; },
        limit() { return chain; },
        maybeSingle() {
          if (table === 'guardian_alerts') {
            return Promise.resolve({ data: findExisting(), error: null });
          }
          return Promise.resolve({ data: null, error: null });
        },
        single() {
          return Promise.resolve({ data: null, error: null });
        },
        then(
          resolve: (v: unknown) => unknown,
          reject?: (e: unknown) => unknown
        ) {
          // guardian_alerts: SELECT без maybeSingle (createAlertOnce dedupe)
          if (table === 'guardian_alerts') {
            return Promise.resolve({ data: findExisting(), error: null }).then(resolve, reject);
          }
          // guardian_track: точки для analyzeMovement
          if (table === 'guardian_track') {
            const rows = (opts.trackSpeeds ?? []).map((speed_kmh) => ({
              speed_kmh,
              recorded_at: new Date().toISOString(),
            }));
            return Promise.resolve({ data: rows, error: null }).then(resolve, reject);
          }
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
    db: db as unknown as Parameters<typeof processSession>[0],
    updates,
    alertsInserted,
  };
}

function makeStats() {
  return {
    sessions_scanned: 0,
    transitions_made: 0,
    alerts_created: 0,
    errors: 0,
    error_details: [] as Array<{ session_id: string; error: string }>,
  };
}

// ─── G2: escalation — overdue_level розсинхронізований зі статусом ──────────

Deno.test('G2: status=active + overdue_level=soft + прострочено 60m → overdue_medium', async () => {
  const session = makeSession({
    status: 'active',
    overdue_level: 'soft',               // ← розсинхрон (імітація recover/sos-cancel)
    original_return: new Date(Date.now() - 60 * MIN).toISOString(),
    last_known_at: new Date(Date.now() - 5 * MIN).toISOString(),
  });
  const { db, updates } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  const statusUpdate = updates.find(
    (u) => u.updates.status !== undefined
  );
  assert(statusUpdate, 'має бути UPDATE зі status');
  assertEquals(statusUpdate!.updates.status, 'overdue_medium');
  assertEquals(statusUpdate!.updates.overdue_level, 'medium');
  assertEquals(stats.errors, 0);
});

Deno.test("G2': sos-cancel шлях — status=active + overdue_level=soft → medium (no duplicate soft)", async () => {
  const session = makeSession({
    status: 'active',
    overdue_level: 'soft',
    original_return: new Date(Date.now() - 10 * MIN).toISOString(),
    last_known_at: new Date(Date.now() - 5 * MIN).toISOString(),
  });
  const { db, updates, alertsInserted } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  // soft → medium: 10m < medium(30), тому target=soft, currentIdx=0,
  // targetIdx=0 → не більше → transition НЕ має бути
  const statusUpdate = updates.find((u) => u.updates.status !== undefined);
  assertEquals(statusUpdate, undefined, '10m прострочення = soft → без нового transition');
  assertEquals(alertsInserted.length, 0);
  assertEquals(stats.errors, 0);
});

// ─── G3: escape-hatch для overdue_hard ───────────────────────────────────────

Deno.test('G3: overdue_hard + останній alert 6h+ → repeat overdue_hard alert', async () => {
  const session = makeSession({
    status: 'overdue_hard',
    overdue_level: 'hard',
    last_known_at: new Date(Date.now() - 5 * MIN).toISOString(),
  });
  const { db, alertsInserted } = makeDbMock({
    session,
    existingAlerts: { overdue_hard: new Date(Date.now() - 7 * HOUR).toISOString() },
  });
  const stats = makeStats();

  await processSession(db, session, stats);

  assertEquals(alertsInserted.length, 1, 'один repeat-алерт');
  assertEquals(alertsInserted[0].alert_type, 'overdue_hard');
  assertEquals((alertsInserted[0].payload as Record<string, unknown>).action, 'still_unresolved');
  assertEquals(stats.errors, 0);
});

Deno.test("G3': overdue_hard + останній alert 2h тому → без alert", async () => {
  const session = makeSession({
    status: 'overdue_hard',
    overdue_level: 'hard',
    last_known_at: new Date(Date.now() - 5 * MIN).toISOString(),
  });
  const { db, alertsInserted } = makeDbMock({
    session,
    existingAlerts: { overdue_hard: new Date(Date.now() - 2 * HOUR).toISOString() },
  });
  const stats = makeStats();

  await processSession(db, session, stats);

  assertEquals(alertsInserted.length, 0);
  assertEquals(stats.errors, 0);
});

// ─── G4: auto-close при last_known_at IS NULL ───────────────────────────────

Deno.test('G4: last_known_at NULL + started_at 25h → finalClose', async () => {
  const session = makeSession({
    status: 'active',
    last_known_at: null,
    started_at: new Date(Date.now() - 25 * HOUR).toISOString(),
  });
  const { db, updates } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  const closeUpdate = updates.find(
    (u) => u.updates.status === 'closed' && u.updates.closed_at !== undefined
  );
  assert(closeUpdate, 'має бути UPDATE status=closed + closed_at');
  assertEquals(closeUpdate!.updates.recoverable_until !== undefined, true);
  assertEquals(stats.errors, 0);
});

Deno.test("G4': last_known_at NULL + started_at 5h → без close", async () => {
  const session = makeSession({
    status: 'active',
    last_known_at: null,
    started_at: new Date(Date.now() - 5 * HOUR).toISOString(),
  });
  const { db, updates } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  const closeUpdate = updates.find((u) => u.updates.status === 'closed');
  assertEquals(closeUpdate, undefined, '5h < 24h → не закриваємо');
  assertEquals(stats.errors, 0);
});

// ─── G5: SOS reminder (Phase 1 — лише alert, без зміни статусу) ─────────────

Deno.test('G5: sos 31m тому + без попередніх alerts → sos_unresolved alert', async () => {
  const session = makeSession({
    status: 'sos',
    sos_activated_at: new Date(Date.now() - 31 * MIN).toISOString(),
  });
  const { db, alertsInserted, updates } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  assertEquals(alertsInserted.length, 1);
  assertEquals(alertsInserted[0].alert_type, 'sos');
  assertEquals(
    (alertsInserted[0].payload as Record<string, unknown>).action,
    'sos_unresolved'
  );
  // Phase 1: статус НЕ змінюється
  assertEquals(
    updates.find((u) => u.updates.status !== undefined),
    undefined,
    'статус не має змінюватись'
  );
  assertEquals(stats.errors, 0);
});

Deno.test("G5': sos 10m тому → без alert", async () => {
  const session = makeSession({
    status: 'sos',
    sos_activated_at: new Date(Date.now() - 10 * MIN).toISOString(),
  });
  const { db, alertsInserted } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  assertEquals(alertsInserted.length, 0);
  assertEquals(stats.errors, 0);
});

Deno.test("G5'': sos 31m тому + попередній alert 20m тому → без повторного", async () => {
  const session = makeSession({
    status: 'sos',
    sos_activated_at: new Date(Date.now() - 60 * MIN).toISOString(),
  });
  const { db, alertsInserted } = makeDbMock({
    session,
    existingAlerts: { sos: new Date(Date.now() - 20 * MIN).toISOString() },
  });
  const stats = makeStats();

  await processSession(db, session, stats);

  assertEquals(alertsInserted.length, 0, 'cooldown 30m ще не минув');
  assertEquals(stats.errors, 0);
});

Deno.test("G5''': sos 31m тому + попередній alert 40m тому → повторний alert", async () => {
  const session = makeSession({
    status: 'sos',
    sos_activated_at: new Date(Date.now() - 90 * MIN).toISOString(),
  });
  const { db, alertsInserted } = makeDbMock({
    session,
    existingAlerts: { sos: new Date(Date.now() - 40 * MIN).toISOString() },
  });
  const stats = makeStats();

  await processSession(db, session, stats);

  assertEquals(alertsInserted.length, 1, 'cooldown минув → reminder');
  assertEquals(alertsInserted[0].alert_type, 'sos');
  assertEquals(stats.errors, 0);
});

// ─── Regression: базові переходи лишаються робочими ────────────────────────

Deno.test('regression: active + свіжий ping + час ще не вийшов → без переходів', async () => {
  const session = makeSession({
    status: 'active',
    original_return: new Date(Date.now() + 30 * MIN).toISOString(),
    expected_return: new Date(Date.now() + 30 * MIN).toISOString(),
    last_known_at: new Date(Date.now() - 5 * MIN).toISOString(),
  });
  const { db, updates } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  assertEquals(updates.find((u) => u.updates.status !== undefined), undefined);
  assertEquals(stats.errors, 0);
});

Deno.test('regression: closing + grace period минув → finalClose', async () => {
  const session = makeSession({
    status: 'closing',
    closing_started_at: new Date(Date.now() - 10 * MIN).toISOString(),
  });
  const { db, updates } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  const closeUpdate = updates.find((u) => u.updates.status === 'closed');
  assert(closeUpdate, 'closing → closed після grace period');
  assertEquals(stats.errors, 0);
});

Deno.test('regression: active + ping 20m тому → stale + offline alert', async () => {
  const session = makeSession({
    status: 'active',
    last_known_at: new Date(Date.now() - 20 * MIN).toISOString(),
    original_return: new Date(Date.now() + 60 * MIN).toISOString(),
  });
  const { db, updates, alertsInserted } = makeDbMock({ session });
  const stats = makeStats();

  await processSession(db, session, stats);

  const staleUpdate = updates.find((u) => u.updates.status === 'stale');
  assert(staleUpdate, 'active → stale через 20m без ping');
  assertEquals(alertsInserted.length, 1);
  assertEquals(alertsInserted[0].alert_type, 'offline');
  assertEquals(stats.errors, 0);
});
