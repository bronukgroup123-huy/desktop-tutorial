// ============================================================================
// GET / PATCH v1-me — профіль, онбординг і Home Region
// (BACKEND_PLAN B1.3, B1.6, B1.9; ADR-001, ADR-016)
//
// GET    → { data: profile }   (ім'я, @нік, аватар, рівень, онбординг, область)
// GET    ?check_handle=<нік> → { data: { handle, available, reason } }
// GET    ?trophies=1 → { data: { trophies, earned_count, total, new_labels } } — трофеї-медальйони
// GET    ?avatars=1 → { data: { current, can_change, reason_label, groups } } — вибір готового аватара
// GET    ?export=1 → { data: { file_name, export } } — усі свої дані одним JSON (GDPR, B6.1); і гостю
// PATCH  { name?, handle?, avatar?, home_region_slug?, accept_terms_version? } → { data: profile }
// DELETE → { data: { deleted: true } } — видалити акаунт (вимога Google Play)
//
// Ім'я, нік і аватар — лише після входу через Google / Apple (ADR-021 §21.2.1): гостю 403.
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
import {
  HANDLE_CHANGE_DAYS,
  handleKey,
  isValidName,
  levelOf,
  validateHandle,
  validateName,
} from "./profile-rules.ts";
import { type Avatar, avatarChoices, publicAvatar, validatePresetAvatar } from "./avatars.ts";
import { countFinds, refreshTrophies, TROPHIES } from "./trophy-catalog.ts";

/** Поточна версія EULA / Privacy Policy. Зміна версії → користувач знову бачить крок згоди. */
export const CURRENT_TERMS_VERSION = "2026-11";
export const CONSENT_DOCS = ["eula", "privacy"] as const;

export const ME_SLUG_REGEX = /^[a-z0-9][a-z0-9_-]{1,31}$/;
export const ONBOARDING_FIX_WINDOW_MS = 24 * 60 * 60 * 1000;

export type NextStep = "select_region" | "accept_terms" | "profile" | "done";

export const NEXT_STEP_LABEL: Record<NextStep, string> = {
  select_region: "Оберіть свою область",
  accept_terms: "Прийміть умови користування та політику конфіденційності",
  profile: "Як вас звати? Придумайте нік",
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
  handle?: string;
  /** Готовий аватар `{ kind: "preset", id }` — перевіряється з рівнем під час збереження. */
  avatar?: Record<string, unknown>;
  home_region_slug?: string;
  accept_terms_version?: string;
}

export function validateUpdateMe(body: unknown): UpdateMeInput {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "invalid_body", "Очікується JSON-об'єкт");
  }
  const obj = body as Record<string, unknown>;
  const input: UpdateMeInput = {};

  if (obj.name !== undefined) input.name = validateName(obj.name);
  if (obj.handle !== undefined) input.handle = validateHandle(obj.handle);
  if (obj.avatar !== undefined) {
    if (obj.avatar === null || typeof obj.avatar !== "object" || Array.isArray(obj.avatar)) {
      throw new HttpError(400, "invalid_avatar", "Оберіть один із готових аватарів");
    }
    input.avatar = obj.avatar as Record<string, unknown>;
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
  handle: string | null;
  handle_changed_at: string | null;
  avatar: Record<string, unknown> | null;
  rating: number;
  total_verified_picks: number;
  home_region_id: number | null;
  created_at: string;
  /** Сертифікат знань (B3.10): Грибознавець / Грибний Майстер (ADR-013). */
  knowledge_certified_at?: string | null;
}

async function loadUser(db: MeDb, userId: string): Promise<UserRow> {
  const { data, error } = await db
    .from("users")
    .select("id, name, handle, handle_changed_at, avatar, rating, total_verified_picks, home_region_id, created_at, knowledge_certified_at")
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
  // Ім'я й нік — лише в акаунті (Google / Apple); гість їх не має (ADR-021 §21.2.1).
  const profileDone = ctx.user.isAnonymous || (row.handle !== null && isValidName(row.name));
  const nextStep: NextStep = !regionDone
    ? "select_region"
    : !termsDone
    ? "accept_terms"
    : !profileDone
    ? "profile"
    : "done";
  const change = regionDone
    ? decideRegionChange(log, ctx.now, ctx.hasProRegionChange)
    : { allowed: true, reason_label: "Оберіть свою область" };

  const rating = Number(row.rating);
  // Знахідки — той самий залік, що й для трофеїв (фото на місці, одне місце за день, ≤ 5 на день).
  let finds = Number(row.total_verified_picks);
  if (!ctx.user.isAnonymous) {
    const f = await countFinds(ctx.db, ctx.user.id);
    if (f !== null) finds = f;
  }
  return {
    id: row.id,
    // Гостю — без імені й ніка (старі імена з Google латиницею — до кроку «Профіль» не показуємо).
    name: ctx.user.isAnonymous || !isValidName(row.name) ? null : row.name,
    handle: ctx.user.isAnonymous ? null : row.handle,
    // Готовий аватар; старі гриби й наліпки конструктора — перший «Мандрівник».
    avatar: publicAvatar(row.avatar),
    level: levelOf(rating, !!row.knowledge_certified_at),
    picks: await pickPermissions(ctx),
    handle_change: handleChangeInfo(row, ctx.now),
    rating,
    total_verified_picks: finds,
    home_region: homeRegion,
    created_at: row.created_at,
    is_guest: ctx.user.isAnonymous,
    onboarding: {
      region_done: regionDone,
      terms_done: termsDone,
      profile_done: profileDone,
      terms_version: CURRENT_TERMS_VERSION,
      next_step: nextStep,
      next_step_label: NEXT_STEP_LABEL[nextStep],
    },
    region_change: { allowed: change.allowed, reason_label: change.reason_label },
  };
}

/**
 * Чи може користувач зараз створити точку (PROD-001b, ADR-019 §19.10, ADR-018 §18.2). Вирішує та сама
 * SQL-функція can_create_pick, що й при створенні, — клієнт лише показує дозвіл і підказку.
 * Помилка БД не ламає профіль: picks = null (застосунок дізнається з відповіді на створення).
 */
export interface PickPermissions {
  public_allowed: boolean;
  public_hint_label: string | null;
  private_allowed: boolean;
  private_hint_label: string | null;
}

async function canCreatePick(ctx: MeContext, visibility: "private" | "public") {
  const { data, error } = await ctx.db.rpc("can_create_pick", { p_user_id: ctx.user.id, p_visibility: visibility });
  if (error) throw error;
  const row = (Array.isArray(data) ? data[0] : data) as { allowed?: unknown; message?: unknown } | undefined;
  if (!row) throw new Error("can_create_pick: empty result");
  return { allowed: row.allowed === true, message: typeof row.message === "string" ? row.message : null };
}

async function pickPermissions(ctx: MeContext): Promise<PickPermissions | null> {
  try {
    const [priv, pub] = await Promise.all([
      canCreatePick(ctx, "private"),
      ctx.user.isAnonymous
        ? Promise.resolve({ allowed: false, message: "Публічні точки — після входу через Google або Apple" })
        : canCreatePick(ctx, "public"),
    ]);
    return {
      public_allowed: pub.allowed,
      public_hint_label: pub.allowed ? null : pub.message,
      private_allowed: priv.allowed,
      private_hint_label: priv.allowed ? null : priv.message,
    };
  } catch (e) {
    console.error("[v1-me] can_create_pick failed:", e);
    return null;
  }
}

/** Чи можна зараз змінити нік (раз на 30 днів; перший раз — будь-коли). */
function handleChangeInfo(row: UserRow, now: Date): { allowed: boolean; reason_label: string } {
  if (!row.handle || !row.handle_changed_at) return { allowed: true, reason_label: "Нік можна змінити раз на 30 днів" };
  const next = new Date(new Date(row.handle_changed_at).getTime() + HANDLE_CHANGE_DAYS * 86_400_000);
  if (now >= next) return { allowed: true, reason_label: "Нік можна змінити раз на 30 днів" };
  const d = `${String(next.getUTCDate()).padStart(2, "0")}.${String(next.getUTCMonth() + 1).padStart(2, "0")}.${next.getUTCFullYear()}`;
  return { allowed: false, reason_label: `Нік можна буде змінити з ${d}` };
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
  const personal = input.name !== undefined || input.handle !== undefined || input.avatar !== undefined;
  if (personal && ctx.user.isAnonymous) {
    throw new HttpError(403, "registration_required", "Ім'я, нік і аватар — після входу через Google або Apple");
  }
  if (input.name !== undefined) patch.name = input.name;
  if (input.avatar !== undefined) {
    // Лише готовий аватар зі списку, відкритий рівнем (403 avatar_locked з причиною).
    const current = await loadUser(ctx.db, ctx.user.id);
    patch.avatar = validatePresetAvatar(input.avatar, Number(current.rating)) satisfies Avatar;
  }
  if (input.handle !== undefined) {
    const current = await loadUser(ctx.db, ctx.user.id);
    const key = handleKey(input.handle);
    if (current.handle === null || handleKey(current.handle) !== key) {
      const change = handleChangeInfo(current, ctx.now);
      if (!change.allowed) throw new HttpError(409, "handle_change_too_soon", change.reason_label);
      patch.handle_changed_at = ctx.now.toISOString();
    }
    patch.handle = input.handle;
    patch.handle_key = key;
  }

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
    if (error && (error as { code?: string }).code === "23505") {
      throw new HttpError(409, "handle_taken", `Нік @${input.handle} уже зайнятий — оберіть інший`);
    }
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

/** Чи вільний нік — для підказки під полем вводу (остаточно перевіряє унікальний індекс). */
export async function checkHandle(ctx: MeContext, raw: string): Promise<{ handle: string; available: boolean; reason: string | null }> {
  let h: string;
  try {
    h = validateHandle(raw);
  } catch (e) {
    return { handle: raw, available: false, reason: e instanceof HttpError ? e.message : "Некоректний нік" };
  }
  const { data, error } = await ctx.db.from("users").select("id").eq("handle_key", handleKey(h)).limit(1);
  if (error) dbFail("users handle check", error);
  const taken = ((data ?? []) as Array<{ id: string }>).some((r) => r.id !== ctx.user.id);
  return { handle: h, available: !taken, reason: taken ? `Нік @${h} уже зайнятий` : null };
}

// ─── Експорт своїх даних (B6.1, GDPR) ──────────────────────────────────────

/** Ім'я файлу експорту: дата за Києвом, щоб збігалася з тим, що бачить людина. */
export function exportFileName(now: Date): string {
  const day = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Kyiv" }).format(now);
  return `hrybnyi-radar-dani-${day}.json`;
}

/**
 * Усі дані користувача (SQL `export_user_data`): профіль, згоди, точки, рейтинг, трофеї, ділянки, друзі,
 * Наглядачі, походи з треком. Гостю теж — у нього є точки й ділянки (ADR-001). Окремий, тісніший ліміт:
 * це найважчий запит профілю.
 */
async function exportMyData(db: MeDb, req: Request, user: AuthUser, now: Date): Promise<Record<string, unknown>> {
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(db as any, req, "v1-me-export");
  const { data, error } = await db.rpc("export_user_data", { p_user_id: user.id });
  if (error) dbFail("export_user_data", error);
  if (!data) throw new HttpError(404, "user_not_found", "Профіль не знайдено");
  return { file_name: exportFileName(now), export: data };
}

export async function handleMe(
  req: Request,
  deps: { db: MeDb; verify: TokenVerifier; now?: () => Date },
): Promise<Response> {
  assertMethod(req, ["GET", "PATCH", "DELETE"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-me");
  const user = await requireUser(req, deps.verify);
  const ctx: MeContext = {
    db: deps.db,
    user,
    now: deps.now ? deps.now() : new Date(),
    hasProRegionChange: false, // entitlements з'являться в B6.3
  };

  if (req.method === "DELETE") {
    // Видалити акаунт: auth.users → каскадом профіль, точки, ділянки, згоди (вимога Google Play).
    const { error } = await deps.db.rpc("delete_user_account", { p_user_id: user.id });
    if (error) dbFail("delete_user_account", error);
    return ok({ deleted: true }, req);
  }
  const params = new URL(req.url).searchParams;
  if (req.method === "GET" && params.has("export")) return ok(await exportMyData(deps.db, req, user, ctx.now), req);
  const check = params.get("check_handle");
  if (req.method === "GET" && check !== null) return ok(await checkHandle(ctx, check), req);
  if (req.method === "GET" && params.has("avatars")) {
    const row = await loadUser(ctx.db, user.id);
    return ok(avatarChoices(row.avatar, Number(row.rating), user.isAnonymous), req);
  }
  if (req.method === "GET" && params.has("trophies")) {
    // Трофеї — лише в акаунті (ADR-001: у гостя немає трофеїв). Перерахунок і запис нових — тут.
    if (user.isAnonymous) {
      throw new HttpError(403, "registration_required", "Трофеї — після входу через Google або Apple");
    }
    try {
      const r = await refreshTrophies(ctx.db, user.id, ctx.now);
      const titles = new Map(TROPHIES.map((t) => [t.id, t.title]));
      return ok({
        trophies: r.views,
        earned_count: r.earned.size,
        total: TROPHIES.length,
        new_labels: r.fresh.map((id) => `Новий трофей: «${titles.get(id)}»`),
      }, req);
    } catch (e) {
      dbFail("trophies", e);
    }
  }
  if (req.method === "PATCH") {
    const input = validateUpdateMe(await readJson(req));
    await updateProfile(ctx, input);
  }
  return ok(await buildProfile(ctx), req);
}
