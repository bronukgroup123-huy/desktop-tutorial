// ============================================================================
// GET / PATCH v1-me — профіль, онбординг і Home Region
// (BACKEND_PLAN B1.3, B1.6, B1.9; ADR-001, ADR-016)
//
// GET   → { data: profile }
// PATCH { name?, home_region_slug?, accept_terms_version? } → { data: profile }
//
// Клієнт не вирішує, який екран онбордингу показати і чи можна змінити область:
// сервер віддає onboarding.next_step і region_change.allowed (Thin Client).
// ============================================================================

import {
  assertMethod,
  enforceRateLimit,
  HttpError,
  ok,
  readJson,
  requireUser,
  type AuthUser,
  type TokenVerifier,
} from "../http.ts";

/** Поточна версія EULA / Privacy Policy. Зміна версії → користувач знову бачить крок згоди. */
export const CURRENT_TERMS_VERSION = "2026-11";
export const CONSENT_DOCS = ["eula", "privacy"] as const;

export const ME_NAME_MAX = 50;
export const ME_SLUG_REGEX = /^[a-z0-9][a-z0-9_-]{1,31}$/;
export const ONBOARDING_FIX_WINDOW_MS = 24 * 60 * 60 * 1000;

export type NextStep = "select_region" | "accept_terms" | "done";

export const NEXT_STEP_LABEL: Record<NextStep, string> = {
  select_region: "Оберіть свою область",
  accept_terms: "Прийміть умови користування та політику конфіденційності",
  done: "Готово",
};

// ─── Зміна Home Region (ADR-016) ───────────────────────────────────────────

export type RegionChangeSource = "onboarding" | "onboarding_fix" | "pro" | "support" | "legacy";

export interface RegionChangeLogRow {
  source: RegionChangeSource;
  changed_at: string;
}

export type RegionChangeDecision =
  | { allowed: true; source: RegionChangeSource; reason_label: string }
  | { allowed: false; reason_label: string };

/**
 * Чи може користувач змінити вже обрану область.
 *  1) протягом 24 год після першого вибору — одне безкоштовне виправлення;
 *  2) у Pro — рівно одна зміна за весь час;
 *  3) інакше — тільки через підтримку.
 * `hasProRegionChange` — feature з entitlements (B6.3); до запуску Pro завжди false.
 */
export function decideRegionChange(
  log: RegionChangeLogRow[],
  now: Date,
  hasProRegionChange: boolean,
): RegionChangeDecision {
  const fixUsed = log.some((r) => r.source === "onboarding_fix");
  const proUsed = log.some((r) => r.source === "pro");
  const firstChoice = log
    .filter((r) => r.source === "onboarding")
    .map((r) => new Date(r.changed_at).getTime())
    .sort((a, b) => a - b)[0];

  if (
    firstChoice !== undefined && !fixUsed &&
    now.getTime() - firstChoice <= ONBOARDING_FIX_WINDOW_MS
  ) {
    return {
      allowed: true,
      source: "onboarding_fix",
      reason_label: "Область можна безкоштовно змінити один раз протягом 24 годин після вибору",
    };
  }
  if (hasProRegionChange && !proUsed) {
    return {
      allowed: true,
      source: "pro",
      reason_label: "У Pro область можна змінити один раз",
    };
  }
  return {
    allowed: false,
    reason_label: proUsed
      ? "Область уже змінено. Повторна зміна — тільки через підтримку"
      : "Зміна області доступна один раз у Pro або через підтримку",
  };
}

// ─── Валідація PATCH ───────────────────────────────────────────────────────

export interface UpdateMeInput {
  name?: string;
  home_region_slug?: string;
  accept_terms_version?: string;
}

export function validateUpdateMe(body: unknown): UpdateMeInput {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "invalid_body", "Очікується JSON-об'єкт");
  }
  const obj = body as Record<string, unknown>;
  const input: UpdateMeInput = {};

  if (obj.name !== undefined) {
    if (typeof obj.name !== "string") throw new HttpError(400, "invalid_name", "Ім'я — рядок");
    const name = obj.name.trim();
    if (name.length < 1 || name.length > ME_NAME_MAX) {
      throw new HttpError(400, "invalid_name", `Ім'я — від 1 до ${ME_NAME_MAX} символів`);
    }
    input.name = name;
  }
  if (obj.home_region_slug !== undefined) {
    if (typeof obj.home_region_slug !== "string" || !ME_SLUG_REGEX.test(obj.home_region_slug)) {
      throw new HttpError(400, "invalid_region_slug", "Некоректний slug області");
    }
    input.home_region_slug = obj.home_region_slug;
  }
  if (obj.accept_terms_version !== undefined) {
    if (typeof obj.accept_terms_version !== "string") {
      throw new HttpError(400, "invalid_terms_version", "Версія умов — рядок");
    }
    if (obj.accept_terms_version !== CURRENT_TERMS_VERSION) {
      throw new HttpError(
        409,
        "terms_version_outdated",
        "Умови оновились — перегляньте актуальну версію",
      );
    }
    input.accept_terms_version = obj.accept_terms_version;
  }

  if (Object.keys(input).length === 0) {
    throw new HttpError(400, "invalid_body", "Потрібне хоча б одне поле");
  }
  return input;
}

// ─── Профіль ───────────────────────────────────────────────────────────────

export interface MeDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export interface MeContext {
  db: MeDb;
  user: AuthUser;
  now: Date;
  /** feature region_change_once з entitlements (B6.3). */
  hasProRegionChange: boolean;
}

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-me] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

interface UserRow {
  id: string;
  name: string | null;
  rating: number;
  total_verified_picks: number;
  home_region_id: number | null;
  created_at: string;
}

async function loadUser(db: MeDb, userId: string): Promise<UserRow> {
  const { data, error } = await db
    .from("users")
    .select("id, name, rating, total_verified_picks, home_region_id, created_at")
    .eq("id", userId)
    .maybeSingle();
  if (error) dbFail("users select", error);
  if (!data) throw new HttpError(404, "me_not_found", "Профіль не знайдено");
  return data as UserRow;
}

async function loadRegionLog(db: MeDb, userId: string): Promise<RegionChangeLogRow[]> {
  const { data, error } = await db
    .from("region_change_log")
    .select("source, changed_at")
    .eq("user_id", userId);
  if (error) dbFail("region_change_log select", error);
  return (data ?? []) as RegionChangeLogRow[];
}

async function hasAcceptedTerms(db: MeDb, userId: string): Promise<boolean> {
  const { data, error } = await db
    .from("user_consents")
    .select("doc")
    .eq("user_id", userId)
    .eq("version", CURRENT_TERMS_VERSION);
  if (error) dbFail("user_consents select", error);
  const docs = new Set(((data ?? []) as Array<{ doc: string }>).map((r) => r.doc));
  return CONSENT_DOCS.every((d) => docs.has(d));
}

export async function buildProfile(ctx: MeContext): Promise<Record<string, unknown>> {
  const row = await loadUser(ctx.db, ctx.user.id);

  let homeRegion: { id: number; slug: string; name: string } | null = null;
  if (row.home_region_id !== null) {
    const { data, error } = await ctx.db
      .from("regions")
      .select("id, slug, name")
      .eq("id", row.home_region_id)
      .maybeSingle();
    if (error) dbFail("regions select", error);
    homeRegion = (data as typeof homeRegion) ?? null;
  }

  const [termsDone, log] = await Promise.all([
    hasAcceptedTerms(ctx.db, ctx.user.id),
    loadRegionLog(ctx.db, ctx.user.id),
  ]);

  const regionDone = homeRegion !== null;
  const nextStep: NextStep = !regionDone ? "select_region" : !termsDone ? "accept_terms" : "done";
  const change = regionDone
    ? decideRegionChange(log, ctx.now, ctx.hasProRegionChange)
    : { allowed: true, reason_label: "Оберіть свою область" };

  return {
    id: row.id,
    name: row.name,
    rating: Number(row.rating),
    total_verified_picks: Number(row.total_verified_picks),
    home_region: homeRegion,
    created_at: row.created_at,
    is_guest: ctx.user.isAnonymous,
    onboarding: {
      region_done: regionDone,
      terms_done: termsDone,
      terms_version: CURRENT_TERMS_VERSION,
      next_step: nextStep,
      next_step_label: NEXT_STEP_LABEL[nextStep],
    },
    region_change: { allowed: change.allowed, reason_label: change.reason_label },
  };
}

async function resolveRegionId(db: MeDb, slug: string): Promise<number> {
  const { data, error } = await db.rpc("find_region_by_slug", { slug_input: slug });
  if (error) dbFail("find_region_by_slug", error);
  const region = (Array.isArray(data) ? data[0] : data) as { id: number } | null | undefined;
  if (!region) throw new HttpError(404, "region_not_found", "Область не знайдено");
  return region.id;
}

export async function updateProfile(ctx: MeContext, input: UpdateMeInput): Promise<void> {
  const patch: Record<string, unknown> = {};
  if (input.name !== undefined) patch.name = input.name;

  let logRow: Record<string, unknown> | null = null;
  if (input.home_region_slug !== undefined) {
    const current = await loadUser(ctx.db, ctx.user.id);
    const newId = await resolveRegionId(ctx.db, input.home_region_slug);

    if (current.home_region_id !== newId) {
      let source: RegionChangeSource;
      if (current.home_region_id === null) {
        source = "onboarding";
      } else {
        const decision = decideRegionChange(
          await loadRegionLog(ctx.db, ctx.user.id),
          ctx.now,
          ctx.hasProRegionChange,
        );
        if (!decision.allowed) {
          throw new HttpError(403, "region_change_not_allowed", decision.reason_label);
        }
        source = decision.source;
      }
      patch.home_region_id = newId;
      logRow = {
        user_id: ctx.user.id,
        old_region_id: current.home_region_id,
        new_region_id: newId,
        source,
        changed_at: ctx.now.toISOString(),
      };
    }
  }

  if (Object.keys(patch).length > 0) {
    const { error } = await ctx.db.from("users").update(patch).eq("id", ctx.user.id);
    if (error) dbFail("users update", error);
  }
  if (logRow) {
    const { error } = await ctx.db.from("region_change_log").insert(logRow);
    if (error) dbFail("region_change_log insert", error);
  }
  if (input.accept_terms_version !== undefined) {
    const rows = CONSENT_DOCS.map((doc) => ({
      user_id: ctx.user.id,
      doc,
      version: input.accept_terms_version,
      accepted_at: ctx.now.toISOString(),
    }));
    const { error } = await ctx.db
      .from("user_consents")
      .upsert(rows, { onConflict: "user_id,doc,version", ignoreDuplicates: true });
    if (error) dbFail("user_consents upsert", error);
  }
}

export async function handleMe(
  req: Request,
  deps: { db: MeDb; verify: TokenVerifier; now?: () => Date },
): Promise<Response> {
  assertMethod(req, ["GET", "PATCH"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-me");
  const user = await requireUser(req, deps.verify);
  const ctx: MeContext = {
    db: deps.db,
    user,
    now: deps.now ? deps.now() : new Date(),
    hasProRegionChange: false, // entitlements з'являться в B6.3
  };

  if (req.method === "PATCH") {
    const input = validateUpdateMe(await readJson(req));
    await updateProfile(ctx, input);
  }
  return ok(await buildProfile(ctx), req);
}
