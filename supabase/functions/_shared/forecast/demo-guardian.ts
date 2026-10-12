// ============================================================================
// Demo-Guardian — чиста логіка публічного демо (group 8.8)
//
// Без supabase-js (щоб тести не тягли @types/node — конвенція репо).
// mergeSettings з guardian/db.ts навмисно НЕ імпортується — той модуль
// тягне esm.sh. DEFAULT_SESSION_SETTINGS нижче ДУБЛЮЄ значення з
// guardian/db.ts і має лишатися синхронним із ним.
//
// TODO(V2): міграція на guardian.mushroomradar.com.ua
// після налаштування DNS + окремого Vercel-проєкту.
// Зараз використовуємо GUARDIAN_BASE_URL з CI-secret (buildGuardianUrl).
// ============================================================================

export const DEMO_USER_ID = "00000000-0000-0000-0000-0000000000d1";
export const DEMO_MAX_ACTIVE = 50;
export const DEMO_TTL_HOURS = 2;
export const DEMO_SESSION_HOURS = 1;

export interface DemoCreateResult {
  ok: boolean;
  url?: string;
  sessionId?: string;
  error?: string;
  status?: number;
  message?: string;
}

/** Дубль DEFAULT_SESSION_SETTINGS з _shared/guardian/db.ts */
const DEMO_SESSION_SETTINGS = {
  overdue_thresholds: { soft: 0, medium: 30, hard: 90 },
  stationary_threshold_min: 30,
  offline_threshold_min: 60,
  grace_period_min: 5,
  recovery_window_min: 30,
};

/** SQL inline-cleanup старих demo-сесій (той самий, що в cron-міграції) */
export function buildDemoCleanupSql(): string {
  return `DELETE FROM guardian_sessions
    WHERE settings->>'demo' = 'true'
      AND started_at < now() - interval '${DEMO_TTL_HOURS} hours'`;
}

export function buildDemoSessionInsert(now: Date = new Date()) {
  const expectedReturn = new Date(
    now.getTime() + DEMO_SESSION_HOURS * 3600 * 1000,
  );
  return {
    user_id: DEMO_USER_ID,
    status: "active",
    expected_return: expectedReturn.toISOString(),
    original_return: expectedReturn.toISOString(),
    started_at: now.toISOString(),
    settings: { ...DEMO_SESSION_SETTINGS, demo: true },
  };
}

export function buildDemoGuardianInsert(sessionId: string) {
  return {
    session_id: sessionId,
    name: "Демо-наглядач",
    phone: null,
    is_emergency: false,
    token_hash: "PENDING", // оновлюється після generateGuardianToken
    token_prefix: "PENDING",
  };
}

export function validateDemoLimit(activeCount: number): DemoCreateResult {
  if (activeCount >= DEMO_MAX_ACTIVE) {
    return {
      ok: false,
      error: "demo_limit_reached",
      status: 429,
      message: `Активних демо-сесій уже ${activeCount} (макс ${DEMO_MAX_ACTIVE})`,
    };
  }
  return { ok: true };
}

/** Межа часу для inline-cleanup через PostgREST (.lt) */
export function demoCutoffIso(now: Date = new Date()): string {
  return new Date(now.getTime() - DEMO_TTL_HOURS * 3600 * 1000).toISOString();
}
