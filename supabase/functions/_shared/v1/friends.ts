// ============================================================================
// v1-friends — друзі «як в Instagram» (ADR-021 §21.1; BACKEND_PLAN B9.2)
//
// GET  v1-friends                    → { friends, incoming, outgoing, blocked, counts, limits }
// GET  v1-friends?q=<нік>            → { results }               — пошук за початком @ніка
// GET  v1-friends?user=<id|нік>      → { profile }               — публічний профіль (§21.2)
// POST v1-friends { action, user_id, reason?, comment? } → { user } — запит, прийняти, відхилити,
//      скасувати, видалити, заблокувати, розблокувати, поскаржитися
// PUT  v1-friends/push { token, platform } → { registered }       — пристрій для push друзів
//
// Лише для акаунта з ніком: гостю — 403 registration_required (ADR-001), без ніка — 409
// profile_required. Логіка й ліміти (20 запитів/добу, 200 друзів, 30 днів після відхилення) —
// у SQL `friend_action` (атомарно). Кнопки й підписи — із сервера (Thin Client): `actions`.
// Push — лише «запит у друзі» і «прийнято»; відхилення, видалення й блок — мовчки.
// Профіль ніколи не містить координат, телефону, email, точок і області (§21.2).
// ============================================================================

import {
  assertMethod,
  assertRegistered,
  enforceRateLimit,
  HttpError,
  ok,
  readJson,
  requireUser,
  type AuthUser,
  type TokenVerifier,
} from "../http.ts";
import { defaultAvatar, handleKey, levelOf, normalizeApostrophes } from "./profile-rules.ts";
import { publicAvatar } from "./avatar-catalog.ts";

export interface FriendsDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export interface PushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface FriendsDeps {
  db: FriendsDb;
  verify: TokenVerifier;
  /** Надіслати push на токен; `unregistered` — токен більше не дійсний. */
  send?: (token: string, msg: PushMessage) => Promise<{ ok: boolean; unregistered?: boolean }>;
  now?: () => Date;
}

export type Relation = "none" | "outgoing" | "incoming" | "friends" | "blocked";
export type FriendAction = "request" | "accept" | "decline" | "cancel" | "remove" | "block" | "unblock" | "report";

export const FRIEND_ACTIONS: FriendAction[] = ["request", "accept", "decline", "cancel", "remove", "block", "unblock", "report"];
export const REPORT_REASONS = ["spam", "abuse", "impersonation", "inappropriate", "other"] as const;
export const REPORT_REASON_LABELS: Record<(typeof REPORT_REASONS)[number], string> = {
  spam: "Спам або реклама",
  abuse: "Образи чи погрози",
  impersonation: "Видає себе за іншого",
  inappropriate: "Непристойний нік чи аватар",
  other: "Інше",
};
export const SEARCH_MIN = 2;
export const SEARCH_LIMIT = 20;
export const MAX_FRIENDS = 200;

export const RELATION_LABEL: Record<Relation, string | null> = {
  none: null,
  outgoing: "Запит надіслано",
  incoming: "Хоче додати вас у друзі",
  friends: "У друзях",
  blocked: "Заблоковано",
};

export interface ActionButton {
  id: FriendAction;
  label: string;
  /** primary — головна кнопка; secondary — поруч; menu — у меню «⋮»; danger — у меню, червоним. */
  style: "primary" | "secondary" | "menu" | "danger";
  /** Питання перед дією (видалити, заблокувати) — null, якщо підтвердження не потрібне. */
  confirm_label: string | null;
}

/** Кнопки для стану пари (сервер вирішує, що показати; клієнт не тримає таблиці переходів). */
export function actionsFor(relation: Relation, handle: string | null): ActionButton[] {
  const who = handle ? `@${handle}` : "цього користувача";
  const block: ActionButton = {
    id: "block", label: "Заблокувати", style: "danger",
    confirm_label: `Заблокувати ${who}? Ви зникнете одне для одного: профіль, пошук, запити.`,
  };
  const report: ActionButton = { id: "report", label: "Поскаржитися", style: "menu", confirm_label: null };
  switch (relation) {
    case "none":
      return [{ id: "request", label: "Додати в друзі", style: "primary", confirm_label: null }, report, block];
    case "outgoing":
      return [{ id: "cancel", label: "Скасувати запит", style: "secondary", confirm_label: null }, report, block];
    case "incoming":
      return [
        { id: "accept", label: "Прийняти", style: "primary", confirm_label: null },
        { id: "decline", label: "Відхилити", style: "secondary", confirm_label: null },
        report,
        block,
      ];
    case "friends":
      return [
        { id: "remove", label: "Видалити з друзів", style: "menu", confirm_label: `Видалити ${who} з друзів? Повідомлення не буде.` },
        report,
        block,
      ];
    case "blocked":
      return [{ id: "unblock", label: "Розблокувати", style: "secondary", confirm_label: null }, report];
  }
}

// ─── Картка користувача ────────────────────────────────────────────────────

interface UserRow {
  id: string;
  handle: string | null;
  name: string | null;
  avatar: Record<string, unknown> | null;
  rating: number | null;
}

export function userCard(row: UserRow, relation: Relation) {
  const rating = Number(row.rating ?? 0);
  const level = levelOf(rating);
  return {
    id: row.id,
    handle: row.handle,
    name: row.name,
    avatar: publicAvatar(row.avatar ?? defaultAvatar(row.id)),
    level: { id: level.id, label: level.label },
    relation,
    relation_label: RELATION_LABEL[relation],
    actions: actionsFor(relation, row.handle),
  };
}

// ─── Допоміжне ─────────────────────────────────────────────────────────────

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-friends] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ACTION_ERROR_STATUS: Record<string, number> = {
  invalid_target: 422,
  user_not_found: 404,
  blocked_by_you: 409,
  request_cooldown: 429,
  daily_limit: 429,
  friends_limit: 409,
  friends_limit_other: 409,
  no_request: 409,
  invalid_action: 400,
};

interface Me {
  id: string;
  handle: string;
}

/** Акаунт із ніком: гостю — 403, без ніка — 409 (спершу крок «Профіль»). */
async function requireProfile(db: FriendsDb, user: AuthUser): Promise<Me> {
  assertRegistered(user);
  const { data, error } = await db.from("users").select("id, handle").eq("id", user.id).maybeSingle();
  if (error) dbFail("users select", error);
  const row = data as { id: string; handle: string | null } | null;
  if (!row) throw new HttpError(404, "me_not_found", "Профіль не знайдено");
  if (!row.handle) throw new HttpError(409, "profile_required", "Спершу придумайте нік — так друзі вас знайдуть");
  return { id: row.id, handle: row.handle };
}

async function loadUser(db: FriendsDb, by: { id?: string; handleKey?: string }): Promise<UserRow | null> {
  let q = db.from("users").select("id, handle, name, avatar, rating");
  q = by.id ? q.eq("id", by.id) : q.eq("handle_key", by.handleKey);
  const { data, error } = await q.maybeSingle();
  if (error) dbFail("users select", error);
  return (data as UserRow | null) ?? null;
}

async function relationOf(db: FriendsDb, me: string, other: string): Promise<Relation | "hidden"> {
  const { data, error } = await db.rpc("friend_relation", { p_user: me, p_target: other });
  if (error) dbFail("friend_relation", error);
  return (data as Relation | "hidden" | null) ?? "none";
}

// ─── GET ───────────────────────────────────────────────────────────────────

async function listFriends(db: FriendsDb, me: Me) {
  const { data, error } = await db.rpc("friend_list", { p_user: me.id });
  if (error) dbFail("friend_list", error);
  const rows = (data ?? []) as Array<UserRow & { kind: "friend" | "incoming" | "outgoing" | "blocked"; since: string }>;
  const out = { friends: [] as unknown[], incoming: [] as unknown[], outgoing: [] as unknown[], blocked: [] as unknown[] };
  const rel: Record<string, Relation> = { friend: "friends", incoming: "incoming", outgoing: "outgoing", blocked: "blocked" };
  for (const r of rows) {
    const card = { ...userCard(r, rel[r.kind]), since: r.since };
    if (r.kind === "friend") out.friends.push(card);
    else if (r.kind === "incoming") out.incoming.push(card);
    else if (r.kind === "outgoing") out.outgoing.push(card);
    else out.blocked.push(card);
  }
  // Друзі — за абеткою ніка; запити — найновіші згори (порядок із SQL).
  (out.friends as Array<{ handle: string | null }>).sort((a, b) => (a.handle ?? "").localeCompare(b.handle ?? "", "uk"));
  return {
    ...out,
    counts: { friends: out.friends.length, incoming: out.incoming.length },
    limits: { max_friends: MAX_FRIENDS, label: `До ${MAX_FRIENDS} друзів` },
    my_handle: me.handle,
  };
}

export function normalizeQuery(raw: string): string {
  return handleKey(normalizeApostrophes(raw.trim().replace(/^@+/, "")));
}

async function search(db: FriendsDb, me: Me, raw: string) {
  const q = normalizeQuery(raw);
  if ([...q].length < SEARCH_MIN) {
    return { results: [], hint_label: `Введіть щонайменше ${SEARCH_MIN} літери ніка` };
  }
  if ([...q].length > 20) return { results: [], hint_label: "Такого ніка немає" };
  const { data, error } = await db.rpc("search_users_by_handle", { p_user: me.id, p_prefix: q, p_limit: SEARCH_LIMIT });
  if (error) dbFail("search_users_by_handle", error);
  const rows = (data ?? []) as Array<UserRow & { relation: Relation | "hidden" }>;
  const results = rows.filter((r) => r.relation !== "hidden").map((r) => userCard(r, r.relation as Relation));
  return { results, hint_label: results.length === 0 ? `Нікого з ніком «@${raw.trim().replace(/^@+/, "")}…» не знайдено` : null };
}

async function profile(db: FriendsDb, me: Me, raw: string) {
  const key = raw.trim();
  const row = UUID_RE.test(key) ? await loadUser(db, { id: key }) : await loadUser(db, { handleKey: normalizeQuery(key) });
  if (!row || !row.handle) throw new HttpError(404, "user_not_found", "Користувача не знайдено");
  const relation = row.id === me.id ? "none" : await relationOf(db, me.id, row.id);
  if (relation === "hidden") throw new HttpError(404, "user_not_found", "Користувача не знайдено");
  const { data: cnt, error } = await db.rpc("friend_count", { p_user: row.id });
  if (error) dbFail("friend_count", error);
  const card = userCard(row, relation);
  return {
    profile: {
      ...card,
      is_me: row.id === me.id,
      actions: row.id === me.id ? [] : card.actions,
      rating: Number(row.rating ?? 0),
      friends_count: Number(cnt ?? 0),
      // Трофеї й подарунки — B9.3 / B9.6; поки порожні, щоб клієнт уже мав місце для них.
      trophies: [],
      gifts: [],
    },
  };
}

// ─── POST ──────────────────────────────────────────────────────────────────

interface ActionInput {
  action: FriendAction;
  userId: string;
  reason?: (typeof REPORT_REASONS)[number];
  comment?: string | null;
  alsoBlock?: boolean;
}

export function validateAction(body: unknown): ActionInput {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "invalid_body", "Очікується { action, user_id }");
  }
  const b = body as Record<string, unknown>;
  if (typeof b.action !== "string" || !FRIEND_ACTIONS.includes(b.action as FriendAction)) {
    throw new HttpError(400, "invalid_action", "Невідома дія");
  }
  if (typeof b.user_id !== "string" || !UUID_RE.test(b.user_id)) {
    throw new HttpError(400, "invalid_user_id", "user_id — ідентифікатор користувача");
  }
  const input: ActionInput = { action: b.action as FriendAction, userId: b.user_id.toLowerCase() };
  if (input.action === "report") {
    if (typeof b.reason !== "string" || !(REPORT_REASONS as readonly string[]).includes(b.reason)) {
      throw new HttpError(400, "invalid_reason", "Оберіть причину скарги");
    }
    input.reason = b.reason as ActionInput["reason"];
    if (b.comment !== undefined && b.comment !== null) {
      if (typeof b.comment !== "string") throw new HttpError(400, "invalid_comment", "Коментар — рядок");
      // deno-lint-ignore no-control-regex
      const c = b.comment.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
      if ([...c].length > 500) throw new HttpError(400, "invalid_comment", "Коментар — до 500 символів");
      input.comment = c || null;
    }
    input.alsoBlock = b.block === true;
  }
  return input;
}

async function notify(deps: FriendsDeps, to: string, msg: PushMessage): Promise<void> {
  if (!deps.send) return;
  try {
    const { data, error } = await deps.db.rpc("push_tokens_of", { p_user: to });
    if (error) return;
    for (const token of ((data ?? []) as string[]).slice(0, 5)) {
      const r = await deps.send(token, msg);
      if (r.unregistered) await deps.db.from("push_devices").delete().eq("token", token);
    }
  } catch (e) {
    // Push — не головне: дія вже виконана, збій сповіщення її не скасовує.
    console.error("[v1-friends] push failed:", e);
  }
}

async function doAction(deps: FriendsDeps, me: Me, input: ActionInput, now: Date) {
  const target = await loadUser(deps.db, { id: input.userId });
  if (!target || !target.handle) throw new HttpError(404, "user_not_found", "Користувача не знайдено");

  if (input.action === "report") {
    if (target.id === me.id) throw new HttpError(422, "invalid_target", "Не можна поскаржитися на себе");
    const rel = await relationOf(deps.db, me.id, target.id);
    if (rel === "hidden") throw new HttpError(404, "user_not_found", "Користувача не знайдено");
    const { error } = await deps.db.from("user_reports").insert({
      reporter_id: me.id, target_id: target.id, reason: input.reason, comment: input.comment ?? null,
      created_at: now.toISOString(),
    });
    if (error) dbFail("user_reports insert", error);
    if (!input.alsoBlock) {
      return { user: userCard(target, rel), done_label: "Скаргу надіслано. Дякуємо — розберемося" };
    }
  }

  const action = input.action === "report" ? "block" : input.action;
  const { data, error } = await deps.db.rpc("friend_action", {
    p_user: me.id, p_target: target.id, p_action: action, p_now: now.toISOString(),
  });
  if (error) dbFail("friend_action", error);
  const res = (data ?? {}) as { ok?: boolean; code?: string; message?: string; relation?: Relation; notify?: string | null };
  if (res.ok !== true) {
    const code = res.code ?? "friend_action_failed";
    throw new HttpError(ACTION_ERROR_STATUS[code] ?? 409, code, res.message);
  }
  const relation = res.relation ?? "none";

  if (res.notify === "request") {
    await notify(deps, target.id, {
      title: "Запит у друзі",
      body: `@${me.handle} хоче додати вас у друзі`,
      data: { type: "friend_request", handle: me.handle },
    });
  } else if (res.notify === "accepted") {
    await notify(deps, target.id, {
      title: "Нові друзі",
      body: `Ви з @${me.handle} тепер друзі`,
      data: { type: "friend_accepted", handle: me.handle },
    });
  }
  return { user: userCard(target, relation), done_label: DONE_LABEL[input.action] ?? null };
}

const DONE_LABEL: Partial<Record<FriendAction, string>> = {
  request: "Запит надіслано",
  accept: "Тепер ви друзі",
  decline: "Запит відхилено",
  cancel: "Запит скасовано",
  remove: "Видалено з друзів",
  block: "Заблоковано",
  unblock: "Розблоковано",
  report: "Скаргу надіслано, користувача заблоковано",
};

async function registerPush(req: Request, db: FriendsDb, me: Me) {
  const body = await readJson(req);
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(422, "validation_error", "Очікується { token, platform }");
  }
  const b = body as Record<string, unknown>;
  if (typeof b.token !== "string" || b.token.length < 20 || b.token.length > 4096 || /\s/.test(b.token)) {
    throw new HttpError(422, "validation_error", "token — токен пристрою");
  }
  if (b.platform !== "android" && b.platform !== "ios") throw new HttpError(422, "validation_error", "platform — android або ios");
  const { error } = await db.rpc("register_push_device_social", { p_user_id: me.id, p_token: b.token, p_platform: b.platform });
  if (error) dbFail("register_push_device_social", error);
  return { registered: true };
}

// ─── Обробник ──────────────────────────────────────────────────────────────

export async function handleFriends(req: Request, deps: FriendsDeps): Promise<Response> {
  assertMethod(req, ["GET", "POST", "PUT"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-friends");
  const user = await requireUser(req, deps.verify);
  const me = await requireProfile(deps.db, user);
  const now = deps.now ? deps.now() : new Date();
  const url = new URL(req.url);

  if (req.method === "PUT") {
    if (!/\/push\/?$/.test(url.pathname)) throw new HttpError(404, "not_found", "Невідомий шлях");
    return ok(await registerPush(req, deps.db, me), req);
  }
  if (req.method === "POST") return ok(await doAction(deps, me, validateAction(await readJson(req)), now), req);

  const q = url.searchParams.get("q");
  if (q !== null) return ok(await search(deps.db, me, q), req);
  const who = url.searchParams.get("user");
  if (who !== null) return ok(await profile(deps.db, me, who), req);
  return ok(await listFriends(deps.db, me), req);
}
