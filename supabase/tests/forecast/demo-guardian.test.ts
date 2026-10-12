import { assertEquals, assert } from 'jsr:@std/assert';
import {
  DEMO_USER_ID, DEMO_MAX_ACTIVE, DEMO_TTL_HOURS, DEMO_SESSION_HOURS,
  buildDemoCleanupSql, buildDemoSessionInsert, buildDemoGuardianInsert,
  validateDemoLimit, demoCutoffIso,
} from '../../functions/_shared/forecast/demo-guardian.ts';

// Handler (Deno.serve) не тестуємо — чиста логіка ізольована (конвенція 8.6c/8.6d).

// ─── validateDemoLimit ───────────────────────────────────────

Deno.test('validateDemoLimit(49) → ok:true', () => {
  const r = validateDemoLimit(DEMO_MAX_ACTIVE - 1);
  assertEquals(r.ok, true);
});

Deno.test('validateDemoLimit(50) → ok:false / 429 / demo_limit_reached', () => {
  const r = validateDemoLimit(DEMO_MAX_ACTIVE);
  assertEquals(r.ok, false);
  assertEquals(r.error, 'demo_limit_reached');
  assertEquals(r.status, 429);
});

Deno.test('validateDemoLimit(51) → те саме (понад ліміт)', () => {
  const r = validateDemoLimit(DEMO_MAX_ACTIVE + 1);
  assertEquals(r.ok, false);
  assertEquals(r.error, 'demo_limit_reached');
});

Deno.test('validateDemoLimit(0) → ok:true', () => {
  assertEquals(validateDemoLimit(0).ok, true);
});

// ─── buildDemoCleanupSql ─────────────────────────────────────

Deno.test('buildDemoCleanupSql: SQL із demo-маркером і TTL', () => {
  const sql = buildDemoCleanupSql();
  assert(sql.includes("settings->>'demo' = 'true'"));
  assert(sql.includes(`interval '${DEMO_TTL_HOURS} hours'`));
  assert(sql.includes('DELETE FROM guardian_sessions'));
});

// ─── buildDemoSessionInsert ──────────────────────────────────

Deno.test('buildDemoSessionInsert: user/status/demo + expected ≈ start + 1h', () => {
  const now = new Date('2026-10-12T12:00:00Z');
  const s = buildDemoSessionInsert(now);
  assertEquals(s.user_id, DEMO_USER_ID);
  assertEquals(s.status, 'active');
  assertEquals(s.settings.demo, true);
  assertEquals(s.started_at, '2026-10-12T12:00:00.000Z');
  assertEquals(s.expected_return, '2026-10-12T13:00:00.000Z'); // +1h
  assertEquals(s.original_return, '2026-10-12T13:00:00.000Z');
});

Deno.test('buildDemoSessionInsert: settings.demo === true поверх defaults (8.8)', () => {
  const s = buildDemoSessionInsert();
  assertEquals(s.settings.demo, true);
});

Deno.test('buildDemoSessionInsert: mergeSettings-дефолти збережені (8.8)', () => {
  // захист від майбутнього рефакторингу: demo:true НЕ затирає thresholds
  const s = buildDemoSessionInsert();
  assert(s.settings.overdue_thresholds.soft !== undefined);
  assertEquals(s.settings.overdue_thresholds.soft, 0);
  assertEquals(s.settings.overdue_thresholds.medium, 30);
  assertEquals(s.settings.overdue_thresholds.hard, 90);
  assertEquals(s.settings.offline_threshold_min, 60);
  assertEquals(s.settings.recovery_window_min, 30);
});

Deno.test('buildDemoSessionInsert: DEMO_SESSION_HOURS = 1 (константа)', () => {
  assertEquals(DEMO_SESSION_HOURS, 1);
});

// ─── buildDemoGuardianInsert ─────────────────────────────────

Deno.test('buildDemoGuardianInsert: session_id + імʼя + PENDING', () => {
  const g = buildDemoGuardianInsert('sess-uuid');
  assertEquals(g.session_id, 'sess-uuid');
  assertEquals(g.name, 'Демо-наглядач');
  assertEquals(g.is_emergency, false);
  assertEquals(g.token_hash, 'PENDING');
  assertEquals(g.token_prefix, 'PENDING');
  assertEquals(g.phone, null);
});

// ─── demoCutoffIso ───────────────────────────────────────────

Deno.test('demoCutoffIso: now − 2h', () => {
  const now = new Date('2026-10-12T12:00:00Z');
  assertEquals(demoCutoffIso(now), '2026-10-12T10:00:00.000Z');
});
