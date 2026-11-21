// ============================================================================
// v1-guardian — Наглядач лише в застосунку, серед друзів (ADR-022; BACKEND_PLAN B4.4,
// B4.7, B4.8, B4.9, B4.11)
//
// GET  v1-guardian               → { guardians, invites, watching, hike, watched, limits, telegram }
// GET  v1-guardian?hike=<id>[&since=<ISO>] → { hike } — похід для Наглядача / власника:
//      статус, останнє місце, батарея, маршрут, трек (з `since` — лише нові точки),
//      «Передати рятувальникам» (координати великими цифрами + текст SMS на 112)
// POST v1-guardian { action, ... }:
//      invite | accept_invite | decline_invite | remove | resign   — Наглядачі (згода один раз)
//      start { route, expected_return, guardian_ids, client_id, checklist_done? } — «Йду в ліс»
//      track { hike_id, points, battery? }                         — живий трек
//      ok | extend { hike_id }                                     — «Все добре?» / +1 год
//      sos | sos_cancel | finish { hike_id, used_home_nav? }
//      telegram_link | telegram_unlink                             — тривоги в Telegram
//
// Правила: гість — 403 registration_required (ADR-001); Наглядач — лише друг, що погодився;
// 1 Наглядач у поході безкоштовно, до 3 — Pro (`pro_required`); маршрут обов'язковий.
// Координати й трек — лише власнику й Наглядачам незакритого походу; після «Я вдома» трек
// видаляється. Push і Telegram — **без координат** («🔴 @Олена — SOS. Відкрийте застосунок»).
// «Все добре?» і тривоги за розкладом — v1-guardian-tick (`handleGuardianTick`).
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
import { publicAvatar } from "./avatars.ts";

export interface GuardianDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export interface PushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface GuardianDeps {
  db: GuardianDb;
  verify: TokenVerifier;
  send?: (token: string, msg: PushMessage, urgent: boolean) => Promise<{ ok: boolean; unregistered?: boolean }>;
  /** Telegram: надіслати текст у чат; немає бота — undefined. */
  telegram?: (chatId: number, text: string) => Promise<boolean>;
  /** Ім'я бота (@…) для посилання «Отримувати тривоги в Telegram»; немає — Telegram вимкнено. */
  telegramBot?: string | null;
  /** Pro `guardians_3` (B6.3): до 3 Наглядачів у поході. */
  hasGuardians3?: (userId: string) => Promise<boolean>;
  now?: () => Date;
  /** Випадковий код для Telegram (тести). */
  randomCode?: () => string;
}

export const FREE_GUARDIANS = 1;
export const PRO_GUARDIANS = 3;
export const MAX_LINKS = 10;
export const MAX_ROUTE_POINTS = 50;
export const MAX_TRACK_BATCH = 500;
export const LOW_ACCURACY_M = 100;
export const CHECK_ANSWER_MIN = 15;
export const OK_SNOOZE_MIN = 30;
export const EXTEND_MIN = 60;
export const MIN_RETURN_MIN = 10;
export const MAX_RETURN_H = 24;
/** Без сигналу довше — Наглядач бачить «немає зв'язку N хв». */
export const NO_SIGNAL_MIN = 20;

export type HikeStatus = "active" | "check" | "alert" | "sos" | "closed";

// ─── Допоміжне ─────────────────────────────────────────────────────────────

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-guardian] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

function bad(message: string): HttpError {
  return new HttpError(422, "validation_error", message);
}

/** «18:30» за Києвом. */
export function kyivTime(iso: string | Date): string {
  return new Intl.DateTimeFormat("uk-UA", { timeZone: "Europe/Kyiv", hour: "2-digit", minute: "2-digit", hour12: false })
    .format(new Date(iso));
}

/** «5 хв тому» / «2 год 10 хв тому». */
export function agoLabel(iso: string | null, now: Date): string | null {
  if (!iso) return null;
  const min = Math.max(0, Math.round((now.getTime() - new Date(iso).getTime()) / 60000));
  if (min < 1) return "щойно";
  if (min < 60) return `${min} хв тому`;
  const h = Math.floor(min / 60), m = min % 60;
  return m === 0 ? `${h} год тому` : `${h} год ${m} хв тому`;
}

interface UserRow {
  id: string;
  handle: string | null;
  name: string | null;
  avatar: Record<string, unknown> | null;
}

function person(u: UserRow | undefined, id: string) {
  return {
    id,
    handle: u?.handle ?? null,
    name: u?.name ?? null,
    avatar: publicAvatar(u?.avatar),
  };
}

const at = (u: UserRow | undefined) => (u?.handle ? `@${u.handle}` : "Грибник");

async function loadUsers(db: GuardianDb, ids: string[]): Promise<Map<string, UserRow>> {
  const uniq = [...new Set(ids)];
  if (uniq.length === 0) return new Map();
  const { data, error } = await db.from("users").select("id, handle, name, avatar").in("id", uniq);
  if (error) dbFail("users select", error);
  return new Map(((data ?? []) as UserRow[]).map((u) => [u.id, u]));
}

async function requireMe(db: GuardianDb, user: AuthUser): Promise<UserRow> {
  assertRegistered(user);
  const { data, error } = await db.from("users").select("id, handle, name, avatar").eq("id", user.id).maybeSingle();
  if (error) dbFail("users select", error);
  const row = data as UserRow | null;
  if (!row) throw new HttpError(404, "me_not_found", "Профіль не знайдено");
  if (!row.handle) throw new HttpError(409, "profile_required", "Спершу придумайте нік — так друзі вас знайдуть");
  return row;
}

async function areFriends(db: GuardianDb, a: string, b: string): Promise<boolean> {
  const { data, error } = await db.rpc("are_friends", { p_a: a, p_b: b });
  if (error) dbFail("are_friends", error);
  return data === true;
}

// ─── Сповіщення (без координат) ────────────────────────────────────────────

async function pushTo(deps: GuardianDeps, userId: string, msg: PushMessage, urgent: boolean): Promise<void> {
  if (!deps.send) return;
  try {
    const { data, error } = await deps.db.rpc("push_tokens_of", { p_user: userId });
    if (error) return;
    for (const token of ((data ?? []) as string[]).slice(0, 5)) {
      const r = await deps.send(token, msg, urgent);
      if (r.unregistered) await deps.db.from("push_devices").delete().eq("token", token);
    }
  } catch (e) {
    console.error("[v1-guardian] push failed:", e);
  }
}

async function telegramTo(deps: GuardianDeps, userIds: string[], text: string): Promise<void> {
  if (!deps.telegram || userIds.length === 0) return;
  try {
    const { data, error } = await deps.db.from("guardian_telegram").select("user_id, chat_id").in("user_id", userIds);
    if (error) return;
    for (const r of (data ?? []) as Array<{ chat_id: number }>) await deps.telegram(Number(r.chat_id), text);
  } catch (e) {
    console.error("[v1-guardian] telegram failed:", e);
  }
}

export type GuardianEvent = "start" | "alert" | "sos" | "sos_cancel" | "ok" | "extend" | "finish" | "autoclose";

/** Текст Наглядачам: лише хто й що; місце — тільки в застосунку після входу (§22.2). */
export function guardianMessage(ev: GuardianEvent, who: string, expectedReturn: string): PushMessage & { urgent: boolean } {
  const back = kyivTime(expectedReturn);
  const m: Record<GuardianEvent, [string, string, boolean]> = {
    start: ["Ви — Наглядач", `${who} вирушає в ліс · повернення до ${back}. Відкрийте застосунок, щоб бачити похід`, false],
    alert: ["🟠 Немає відповіді", `${who} не відповідає на «Все добре?». Відкрийте застосунок`, true],
    sos: ["🔴 SOS", `${who} — SOS. Відкрийте застосунок`, true],
    sos_cancel: ["SOS скасовано", `${who}: SOS скасовано, все гаразд`, true],
    ok: ["Все добре", `${who} відповідає: все добре`, false],
    extend: ["Похід продовжено", `${who} продовжує похід до ${back}`, false],
    finish: ["Вдома", `${who} вдома. Похід завершено`, false],
    autoclose: ["Похід закрито", `Похід ${who} закрито автоматично`, false],
  };
  const [title, body, urgent] = m[ev];
  return { title, body, urgent, data: { type: `hike_${ev}` } };
}

async function notifyGuardians(deps: GuardianDeps, hike: HikeRow, owner: UserRow | undefined, ev: GuardianEvent): Promise<void> {
  const ids = await hikeGuardianIds(deps.db, hike.id);
  const msg = guardianMessage(ev, at(owner), hike.expected_return);
  msg.data.hike_id = hike.id;
  for (const g of ids) await pushTo(deps, g, msg, msg.urgent);
  await telegramTo(deps, ids, `${msg.title}\n${msg.body}`);
}

// ─── Походи ────────────────────────────────────────────────────────────────

export interface HikeRow {
  id: string;
  owner_id: string;
  client_id?: string | null;
  status: HikeStatus;
  route: Array<{ lat: number; lng: number; label: string }>;
  started_at: string;
  expected_return: string;
  last_lat: number | null;
  last_lng: number | null;
  last_accuracy: number | null;
  last_at: string | null;
  last_signal_at: string | null;
  battery: number | null;
  gps_issue_at: string | null;
  check_sent_at: string | null;
  alert_sent_at: string | null;
  sos_at: string | null;
  closed_at: string | null;
}

const HIKE_COLS =
  "id, owner_id, client_id, status, route, started_at, expected_return, last_lat, last_lng, last_accuracy, last_at, last_signal_at, battery, gps_issue_at, check_sent_at, alert_sent_at, sos_at, closed_at";

async function loadHike(db: GuardianDb, id: string): Promise<HikeRow | null> {
  const { data, error } = await db.from("hikes").select(HIKE_COLS).eq("id", id).maybeSingle();
  if (error) dbFail("hikes select", error);
  return (data as HikeRow | null) ?? null;
}

async function openHikeOf(db: GuardianDb, ownerId: string): Promise<HikeRow | null> {
  const { data, error } = await db.from("hikes").select(HIKE_COLS).eq("owner_id", ownerId).neq("status", "closed").maybeSingle();
  if (error) dbFail("hikes select", error);
  return (data as HikeRow | null) ?? null;
}

async function hikeGuardianIds(db: GuardianDb, hikeId: string): Promise<string[]> {
  const { data, error } = await db.from("hike_guardians").select("guardian_id").eq("hike_id", hikeId);
  if (error) dbFail("hike_guardians select", error);
  return ((data ?? []) as Array<{ guardian_id: string }>).map((r) => r.guardian_id);
}

/** Мій похід — і для дій: лише власник, лише незакритий. */
async function myOpenHike(db: GuardianDb, me: string, hikeId: unknown): Promise<HikeRow> {
  if (typeof hikeId !== "string" || !UUID_RE.test(hikeId)) throw bad("hike_id — ідентифікатор походу");
  const h = await loadHike(db, hikeId);
  if (!h || h.owner_id !== me) throw new HttpError(404, "hike_not_found", "Похід не знайдено");
  if (h.status === "closed") throw new HttpError(409, "hike_closed", "Похід уже завершено");
  return h;
}

const STATUS_LABEL: Record<HikeStatus, string> = {
  active: "У поході",
  check: "Питаємо «Все добре?»",
  alert: "Не відповідає на «Все добре?»",
  sos: "SOS",
  closed: "Вдома",
};

interface ActionButton {
  id: string;
  label: string;
  style: "primary" | "secondary" | "danger";
}

/** Кнопки грибника для стану походу (Thin Client). */
export function ownerActions(status: HikeStatus): ActionButton[] {
  const extend: ActionButton = { id: "extend", label: "Продовжити на годину", style: "secondary" };
  const finish: ActionButton = { id: "finish", label: "Я вдома", style: "primary" };
  switch (status) {
    case "active":
      return [extend, finish];
    case "check":
    case "alert":
      return [{ id: "ok", label: "Так, все добре", style: "primary" }, extend, { ...finish, style: "secondary" }];
    case "sos":
      return [{ id: "sos_cancel", label: "Скасувати SOS", style: "danger" }, { ...finish, style: "secondary" }];
    case "closed":
      return [];
  }
}

function ownerView(h: HikeRow, guardians: Map<string, UserRow>, guardianIds: string[], now: Date) {
  const back = kyivTime(h.expected_return);
  return {
    id: h.id,
    status: h.status,
    status_label: STATUS_LABEL[h.status],
    detail_label: h.status === "active"
      ? `Повернення до ${back}`
      : h.status === "check"
      ? `Час повернення настав. Без відповіді за ${CHECK_ANSWER_MIN} хв сповістимо Наглядача`
      : h.status === "alert"
      ? "Наглядача сповіщено. Відповідайте, якщо все гаразд"
      : h.status === "sos"
      ? "Наглядачів сповіщено. Зателефонуйте 112, якщо можете"
      : null,
    ask_ok: h.status === "check" || h.status === "alert",
    started_at: h.started_at,
    expected_return: h.expected_return,
    expected_return_label: back,
    guardians: guardianIds.map((id) => person(guardians.get(id), id)),
    last_signal_label: agoLabel(h.last_signal_at, now),
    actions: ownerActions(h.status),
  };
}

function coordsLabel(lat: number, lng: number): string {
  return `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
}

/** Що бачить Наглядач у картці грибника (без маршруту й треку — вони в `?hike=`). */
function watchedSummary(h: HikeRow, owner: UserRow | undefined, now: Date) {
  const silentMin = h.last_signal_at ? (now.getTime() - new Date(h.last_signal_at).getTime()) / 60000 : null;
  const gpsIssue = h.gps_issue_at !== null && now.getTime() - new Date(h.gps_issue_at).getTime() < 30 * 60000;
  const back = kyivTime(h.expected_return);
  return {
    hike_id: h.id,
    owner: person(owner, h.owner_id),
    status: h.status,
    status_label: STATUS_LABEL[h.status],
    detail_label: h.status === "active" || h.status === "check" ? `Повернення до ${back}` : h.status === "alert"
      ? `Мав(ла) повернутися о ${back} і не відповідає`
      : h.status === "sos"
      ? "Натиснуто SOS"
      : null,
    alarm: h.status === "alert" || h.status === "sos",
    expected_return: h.expected_return,
    battery: h.battery,
    battery_label: h.battery === null ? null : `Батарея ${h.battery} %`,
    last_signal_at: h.last_signal_at,
    last_signal_label: h.last_signal_at === null ? "Ще немає сигналу" : `Останній сигнал ${agoLabel(h.last_signal_at, now)}`,
    no_signal: silentMin !== null && silentMin >= NO_SIGNAL_MIN,
    gps_issue_label: gpsIssue ? "Можливі збої GPS — місце може бути неточним" : null,
    last: h.last_lat === null || h.last_lng === null
      ? null
      : { lat: h.last_lat, lng: h.last_lng, accuracy: h.last_accuracy, at: h.last_at },
  };
}

// ─── GET ───────────────────────────────────────────────────────────────────

async function overview(deps: GuardianDeps, me: UserRow, now: Date) {
  const db = deps.db;
  const [{ data: mine, error: e1 }, { data: asked, error: e2 }, { data: hg, error: e3 }] = await Promise.all([
    db.from("guardian_links").select("guardian_id, status, created_at").eq("owner_id", me.id),
    db.from("guardian_links").select("owner_id, status, created_at").eq("guardian_id", me.id),
    db.from("hike_guardians").select("hike_id").eq("guardian_id", me.id),
  ]);
  if (e1) dbFail("guardian_links select", e1);
  if (e2) dbFail("guardian_links select", e2);
  if (e3) dbFail("hike_guardians select", e3);
  const myLinks = (mine ?? []) as Array<{ guardian_id: string; status: string }>;
  const askedLinks = (asked ?? []) as Array<{ owner_id: string; status: string }>;
  const watchedIds = ((hg ?? []) as Array<{ hike_id: string }>).map((r) => r.hike_id);

  const hike = await openHikeOf(db, me.id);
  const hikeGuards = hike ? await hikeGuardianIds(db, hike.id) : [];

  let watchedHikes: HikeRow[] = [];
  if (watchedIds.length > 0) {
    const { data, error } = await db.from("hikes").select(HIKE_COLS).in("id", watchedIds).neq("status", "closed");
    if (error) dbFail("hikes select", error);
    watchedHikes = (data ?? []) as HikeRow[];
  }

  const users = await loadUsers(db, [
    ...myLinks.map((l) => l.guardian_id),
    ...askedLinks.map((l) => l.owner_id),
    ...hikeGuards,
    ...watchedHikes.map((h) => h.owner_id),
  ]);

  const max = (await deps.hasGuardians3?.(me.id)) ? PRO_GUARDIANS : FREE_GUARDIANS;
  let telegram = { available: false, linked: false };
  if (deps.telegramBot) {
    const { data, error } = await db.from("guardian_telegram").select("user_id").eq("user_id", me.id).maybeSingle();
    if (error) dbFail("guardian_telegram select", error);
    telegram = { available: true, linked: data !== null };
  }

  return {
    guardians: myLinks.map((l) => ({
      ...person(users.get(l.guardian_id), l.guardian_id),
      status: l.status,
      status_label: l.status === "accepted" ? "Наглядач" : "Чекаємо згоди",
      actions: [{ id: "remove", label: l.status === "accepted" ? "Прибрати з Наглядачів" : "Скасувати прохання", style: "secondary" }],
    })),
    invites: askedLinks.filter((l) => l.status === "pending").map((l) => {
      const u = users.get(l.owner_id);
      return {
        ...person(u, l.owner_id),
        label: `${at(u)} просить вас бути Наглядачем: бачити похід, поки він триває, і отримувати тривоги`,
        actions: [
          { id: "accept_invite", label: "Так, буду", style: "primary" },
          { id: "decline_invite", label: "Ні", style: "secondary" },
        ],
      };
    }),
    watching: askedLinks.filter((l) => l.status === "accepted").map((l) => ({
      ...person(users.get(l.owner_id), l.owner_id),
      actions: [{ id: "resign", label: "Більше не бути Наглядачем", style: "secondary" }],
    })),
    hike: hike ? ownerView(hike, users, hikeGuards, now) : null,
    watched: watchedHikes
      .map((h) => watchedSummary(h, users.get(h.owner_id), now))
      .sort((a, b) => Number(b.alarm) - Number(a.alarm)),
    limits: {
      max_guardians_per_hike: max,
      label: max === FREE_GUARDIANS ? "1 Наглядач у поході · до 3 — у Pro" : `До ${max} Наглядачів у поході`,
    },
    telegram,
  };
}

async function hikeDetail(deps: GuardianDeps, me: UserRow, hikeId: string, sinceRaw: string | null, now: Date) {
  if (!UUID_RE.test(hikeId)) throw bad("hike — ідентифікатор походу");
  const h = await loadHike(deps.db, hikeId);
  // Не власник і не Наглядач незакритого походу — для нього походу немає (B4.9).
  const guards = h ? await hikeGuardianIds(deps.db, h.id) : [];
  const isOwner = h?.owner_id === me.id;
  if (!h || (!isOwner && (h.status === "closed" || !guards.includes(me.id)))) {
    throw new HttpError(404, "hike_not_found", "Похід не знайдено або вже завершено");
  }
  let since: Date | null = null;
  if (sinceRaw) {
    since = new Date(sinceRaw);
    if (Number.isNaN(since.getTime())) throw bad("since — час ISO 8601");
  }
  let q = deps.db.from("hike_points").select("lat, lng, accuracy, low_accuracy, recorded_at").eq("hike_id", h.id);
  if (since) q = q.gt("recorded_at", since.toISOString());
  const { data, error } = await q.order("recorded_at").limit(5000);
  if (error) dbFail("hike_points select", error);
  const users = await loadUsers(deps.db, [h.owner_id, ...guards]);
  const owner = users.get(h.owner_id);
  const summary = watchedSummary(h, owner, now);
  const last = summary.last;
  const who = owner?.name ? `${owner.name} (${at(owner)})` : at(owner);
  return {
    hike: {
      ...summary,
      is_owner: isOwner,
      route: h.route,
      track: ((data ?? []) as Array<{ lat: number; lng: number; accuracy: number | null; low_accuracy: boolean; recorded_at: string }>)
        .map((p) => ({ lat: p.lat, lng: p.lng, accuracy: p.accuracy, low_accuracy: p.low_accuracy, t: p.recorded_at })),
      guardians: guards.map((id) => person(users.get(id), id)),
      // «Передати рятувальникам» (§22.2): координати великими цифрами й готовий текст SMS на 112 —
      // без посилань.
      rescue: last === null ? null : {
        coords_label: coordsLabel(last.lat, last.lng),
        at_label: last.at ? `Останнє місце о ${kyivTime(last.at)}` : null,
        sms_text: `Потрібна допомога: грибник ${who} у лісі. Останнє місце: ${coordsLabel(last.lat, last.lng)}` +
          `${last.at ? ` о ${kyivTime(last.at)}` : ""}` +
          `${last.accuracy ? ` (точність ~${Math.round(last.accuracy)} м)` : ""}. Мав(ла) повернутися о ${kyivTime(h.expected_return)}.`,
        call_label: "Подзвонити 112",
      },
      server_time: now.toISOString(),
    },
  };
}

// ─── POST: Наглядачі ───────────────────────────────────────────────────────

function targetId(b: Record<string, unknown>): string {
  if (typeof b.user_id !== "string" || !UUID_RE.test(b.user_id)) throw new HttpError(400, "invalid_user_id", "user_id — ідентифікатор користувача");
  return b.user_id.toLowerCase();
}

async function invite(deps: GuardianDeps, me: UserRow, b: Record<string, unknown>, now: Date) {
  const g = targetId(b);
  if (g === me.id) throw new HttpError(422, "invalid_target", "Не можна бути Наглядачем собі");
  if (!(await areFriends(deps.db, me.id, g))) {
    throw new HttpError(403, "not_friends", "Наглядача обирають серед друзів — спершу додайте в друзі");
  }
  const { data: existing, error } = await deps.db.from("guardian_links").select("guardian_id, status").eq("owner_id", me.id);
  if (error) dbFail("guardian_links select", error);
  const rows = (existing ?? []) as Array<{ guardian_id: string; status: string }>;
  const already = rows.find((r) => r.guardian_id === g);
  if (already) return { status: already.status, done_label: already.status === "accepted" ? "Уже ваш Наглядач" : "Прохання вже надіслано" };
  if (rows.length >= MAX_LINKS) throw new HttpError(409, "guardians_limit", `До ${MAX_LINKS} Наглядачів`);
  const { error: e2 } = await deps.db.from("guardian_links").insert({ owner_id: me.id, guardian_id: g, status: "pending", created_at: now.toISOString() });
  if (e2) dbFail("guardian_links insert", e2);
  await pushTo(deps, g, {
    title: "Прохання бути Наглядачем",
    body: `${at(me)} просить вас бути Наглядачем у поході`,
    data: { type: "guardian_invite" },
  }, false);
  return { status: "pending", done_label: "Прохання надіслано" };
}

async function answerInvite(deps: GuardianDeps, me: UserRow, b: Record<string, unknown>, accept: boolean, now: Date) {
  const owner = targetId(b);
  const { data, error } = await deps.db.from("guardian_links").select("status").eq("owner_id", owner).eq("guardian_id", me.id).maybeSingle();
  if (error) dbFail("guardian_links select", error);
  if (!data || (data as { status: string }).status !== "pending") throw new HttpError(409, "no_invite", "Прохання немає");
  if (!accept) {
    const { error: e } = await deps.db.from("guardian_links").delete().eq("owner_id", owner).eq("guardian_id", me.id);
    if (e) dbFail("guardian_links delete", e);
    return { status: "none", done_label: "Відхилено" };
  }
  const { error: e } = await deps.db.from("guardian_links").update({ status: "accepted", responded_at: now.toISOString() })
    .eq("owner_id", owner).eq("guardian_id", me.id);
  if (e) dbFail("guardian_links update", e);
  await pushTo(deps, owner, { title: "Новий Наглядач", body: `${at(me)} тепер ваш Наглядач`, data: { type: "guardian_accepted" } }, false);
  return { status: "accepted", done_label: "Тепер ви Наглядач" };
}

async function unlink(deps: GuardianDeps, me: UserRow, b: Record<string, unknown>, asOwner: boolean) {
  const other = targetId(b);
  const [owner, guardian] = asOwner ? [me.id, other] : [other, me.id];
  const { error } = await deps.db.from("guardian_links").delete().eq("owner_id", owner).eq("guardian_id", guardian);
  if (error) dbFail("guardian_links delete", error);
  return { status: "none", done_label: asOwner ? "Прибрано з Наглядачів" : "Ви більше не Наглядач" };
}

// ─── POST: похід ───────────────────────────────────────────────────────────

function num(v: unknown, min: number, max: number): number | null {
  return typeof v === "number" && Number.isFinite(v) && v >= min && v <= max ? v : null;
}

export function validateRoute(raw: unknown): Array<{ lat: number; lng: number; label: string }> {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new HttpError(422, "route_required", "Без маршруту похід не почати: додайте хоча б точку старту");
  }
  if (raw.length > MAX_ROUTE_POINTS) throw bad(`Маршрут — до ${MAX_ROUTE_POINTS} точок`);
  return raw.map((p, i) => {
    const o = (p ?? {}) as Record<string, unknown>;
    const lat = num(o.lat, -90, 90), lng = num(o.lng, -180, 180);
    if (lat === null || lng === null) throw bad(`Точка маршруту ${i + 1}: потрібні lat і lng`);
    // deno-lint-ignore no-control-regex
    const label = typeof o.label === "string" ? o.label.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 40) : "";
    return { lat, lng, label: label || (i === 0 ? "Старт" : `Точка ${i}`) };
  });
}

async function start(deps: GuardianDeps, me: UserRow, b: Record<string, unknown>, now: Date) {
  const route = validateRoute(b.route);
  const ret = typeof b.expected_return === "string" ? new Date(b.expected_return) : null;
  if (!ret || Number.isNaN(ret.getTime())) throw bad("expected_return — час повернення (ISO 8601)");
  if (ret.getTime() < now.getTime() + MIN_RETURN_MIN * 60000) throw bad(`Час повернення — щонайменше через ${MIN_RETURN_MIN} хв`);
  if (ret.getTime() > now.getTime() + MAX_RETURN_H * 3600000) throw bad(`Час повернення — не пізніше ніж через ${MAX_RETURN_H} год`);
  const clientId = typeof b.client_id === "string" && b.client_id.length <= 64 ? b.client_id : null;
  const ids = Array.isArray(b.guardian_ids) ? [...new Set(b.guardian_ids.map(String).map((s) => s.toLowerCase()))] : [];
  if (ids.length === 0) throw new HttpError(422, "guardian_required", "Оберіть Наглядача з друзів");
  if (ids.some((id) => !UUID_RE.test(id))) throw bad("guardian_ids — ідентифікатори друзів");
  const max = (await deps.hasGuardians3?.(me.id)) ? PRO_GUARDIANS : FREE_GUARDIANS;
  if (ids.length > max) {
    throw new HttpError(403, "pro_required", `Безкоштовно — ${FREE_GUARDIANS} Наглядач у поході. До ${PRO_GUARDIANS} — у Pro`);
  }

  const open = await openHikeOf(deps.db, me.id);
  if (open) {
    if (clientId && open.client_id === clientId) return { hike: ownerView(open, await loadUsers(deps.db, ids), await hikeGuardianIds(deps.db, open.id), now) };
    throw new HttpError(409, "hike_already_active", "Попередній похід ще не завершено — натисніть «Я вдома»");
  }

  const { data: links, error } = await deps.db.from("guardian_links").select("guardian_id, status").eq("owner_id", me.id).in("guardian_id", ids);
  if (error) dbFail("guardian_links select", error);
  const accepted = new Set(((links ?? []) as Array<{ guardian_id: string; status: string }>).filter((l) => l.status === "accepted").map((l) => l.guardian_id));
  if (ids.some((id) => !accepted.has(id))) {
    throw new HttpError(403, "guardian_not_accepted", "Наглядач ще не погодився — попросіть друга підтвердити в застосунку");
  }

  const row = {
    owner_id: me.id,
    client_id: clientId,
    status: "active",
    route,
    started_at: now.toISOString(),
    expected_return: ret.toISOString(),
    last_signal_at: now.toISOString(),
    // Перед стартом пройдено чек-лист (трофей «Готовий до лісу»).
    checklist_done: b.checklist_done === true,
  };
  const { data: created, error: e2 } = await deps.db.from("hikes").insert(row).select(HIKE_COLS).single();
  if (e2 && (e2 as { code?: string }).code === "23505") {
    throw new HttpError(409, "hike_already_active", "Попередній похід ще не завершено — натисніть «Я вдома»");
  }
  if (e2 || !created) dbFail("hikes insert", e2);
  const hike = created as HikeRow;
  const { error: e3 } = await deps.db.from("hike_guardians").insert(ids.map((g) => ({ hike_id: hike.id, guardian_id: g })));
  if (e3) dbFail("hike_guardians insert", e3);
  await notifyGuardians(deps, hike, me, "start");
  return { hike: ownerView(hike, await loadUsers(deps.db, ids), ids, now) };
}

interface InPoint {
  lat: number;
  lng: number;
  accuracy: number | null;
  recorded_at: string;
  low_accuracy: boolean;
}

export function validatePoints(raw: unknown, startedAt: Date, now: Date): InPoint[] {
  if (!Array.isArray(raw)) throw bad("points — масив точок");
  if (raw.length > MAX_TRACK_BATCH) throw bad(`До ${MAX_TRACK_BATCH} точок за раз`);
  const out: InPoint[] = [];
  for (const p of raw) {
    const o = (p ?? {}) as Record<string, unknown>;
    const lat = num(o.lat, -90, 90), lng = num(o.lng, -180, 180);
    const t = typeof o.t === "string" ? new Date(o.t) : null;
    if (lat === null || lng === null || !t || Number.isNaN(t.getTime())) throw bad("Точка треку: lat, lng, t");
    // Точки з минулого (до старту) і з майбутнього — відкидаємо мовчки (годинник телефону).
    if (t.getTime() < startedAt.getTime() - 5 * 60000 || t.getTime() > now.getTime() + 2 * 60000) continue;
    const acc = num(o.acc, 0, 100000);
    out.push({ lat, lng, accuracy: acc, recorded_at: t.toISOString(), low_accuracy: acc !== null && acc > LOW_ACCURACY_M });
  }
  return out.sort((a, b) => a.recorded_at.localeCompare(b.recorded_at));
}

async function track(deps: GuardianDeps, me: UserRow, b: Record<string, unknown>, now: Date) {
  const h = await myOpenHike(deps.db, me.id, b.hike_id);
  const points = validatePoints(b.points, new Date(h.started_at), now);
  const battery = b.battery === undefined || b.battery === null ? null : num(b.battery, 0, 100);
  if (points.length > 0) {
    const { error } = await deps.db.from("hike_points")
      .upsert(points.map((p) => ({ hike_id: h.id, ...p })), { onConflict: "hike_id,recorded_at", ignoreDuplicates: true });
    if (error) dbFail("hike_points upsert", error);
  }
  const patch: Record<string, unknown> = { last_signal_at: now.toISOString() };
  if (battery !== null) patch.battery = Math.round(battery);
  const good = points.filter((p) => !p.low_accuracy);
  const newest = good[good.length - 1];
  if (newest && (!h.last_at || newest.recorded_at > h.last_at)) {
    patch.last_lat = newest.lat;
    patch.last_lng = newest.lng;
    patch.last_accuracy = newest.accuracy;
    patch.last_at = newest.recorded_at;
  }
  if (points.some((p) => p.low_accuracy)) patch.gps_issue_at = now.toISOString();
  const { error } = await deps.db.from("hikes").update(patch).eq("id", h.id);
  if (error) dbFail("hikes update", error);
  const guards = await hikeGuardianIds(deps.db, h.id);
  return { hike: ownerView({ ...h, ...patch } as HikeRow, await loadUsers(deps.db, guards), guards, now), accepted: points.length };
}

async function setStatus(deps: GuardianDeps, me: UserRow, b: Record<string, unknown>, action: string, now: Date) {
  const h = await myOpenHike(deps.db, me.id, b.hike_id);
  const wasAlarm = h.status === "alert" || h.status === "sos";
  let patch: Record<string, unknown>;
  let ev: GuardianEvent | null = null;
  let done: string;
  switch (action) {
    case "ok": {
      // «Так, все добре» — спитаємо ще раз за 30 хв, якщо не повернеться.
      const next = new Date(Math.max(new Date(h.expected_return).getTime(), now.getTime()) + (h.status === "active" ? 0 : OK_SNOOZE_MIN * 60000));
      patch = { status: h.status === "sos" ? "sos" : "active", expected_return: next.toISOString(), check_sent_at: null, alert_sent_at: null };
      ev = h.status === "alert" ? "ok" : null;
      done = `Добре! Спитаємо ще раз о ${kyivTime(next)}`;
      break;
    }
    case "extend": {
      const next = new Date(Math.max(new Date(h.expected_return).getTime(), now.getTime()) + EXTEND_MIN * 60000);
      if (next.getTime() > new Date(h.started_at).getTime() + 2 * MAX_RETURN_H * 3600000) {
        throw new HttpError(409, "extend_limit", "Похід уже дуже довгий — завершіть його й почніть новий");
      }
      patch = { status: h.status === "sos" ? "sos" : "active", expected_return: next.toISOString(), check_sent_at: null, alert_sent_at: null };
      ev = "extend";
      done = `Повернення до ${kyivTime(next)}`;
      break;
    }
    case "sos":
      if (h.status === "sos") return { hike: ownerView(h, new Map(), await hikeGuardianIds(deps.db, h.id), now), done_label: "SOS уже надіслано" };
      patch = { status: "sos", sos_at: now.toISOString() };
      ev = "sos";
      done = "Наглядачів сповіщено";
      break;
    case "sos_cancel":
      if (h.status !== "sos") throw new HttpError(409, "no_sos", "SOS не було");
      patch = { status: new Date(h.expected_return) <= now ? "check" : "active", sos_at: null, check_sent_at: new Date(h.expected_return) <= now ? now.toISOString() : null };
      ev = "sos_cancel";
      done = "SOS скасовано";
      break;
    default: // finish
      // used_home_nav — повернулися за допомогою «Додому» (трофей «Своїм слідом»).
      patch = { status: "closed", closed_at: now.toISOString(), closed_reason: "home", used_home_nav: b.used_home_nav === true };
      ev = "finish";
      done = "Гарного відпочинку! Трек видалено з сервера";
  }
  const { data, error } = await deps.db.from("hikes").update(patch).eq("id", h.id).neq("status", "closed").select(HIKE_COLS).maybeSingle();
  if (error) dbFail("hikes update", error);
  if (!data) throw new HttpError(409, "hike_closed", "Похід уже завершено");
  const updated = data as HikeRow;
  // «Все добре»/продовження під час тривоги — Наглядачам обов'язково; без тривоги «Вдома» теж.
  if (ev && (ev !== "ok" || wasAlarm)) await notifyGuardians(deps, updated, me, ev);
  const guards = action === "finish" ? [] : await hikeGuardianIds(deps.db, h.id);
  return { hike: action === "finish" ? null : ownerView(updated, await loadUsers(deps.db, guards), guards, now), done_label: done };
}

// ─── Telegram ──────────────────────────────────────────────────────────────

async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function randomCode(): string {
  const b = new Uint8Array(18);
  crypto.getRandomValues(b);
  return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function telegramLink(deps: GuardianDeps, me: UserRow, now: Date) {
  if (!deps.telegramBot) throw new HttpError(503, "telegram_unavailable", "Telegram поки не підключено");
  const code = (deps.randomCode ?? randomCode)();
  await deps.db.from("telegram_link_codes").delete().eq("user_id", me.id);
  const { error } = await deps.db.from("telegram_link_codes").insert({
    code_hash: await sha256(code), user_id: me.id, expires_at: new Date(now.getTime() + 15 * 60000).toISOString(),
  });
  if (error) dbFail("telegram_link_codes insert", error);
  return {
    url: `https://t.me/${deps.telegramBot.replace(/^@/, "")}?start=${code}`,
    label: "Відкрийте Telegram і натисніть «Start» — бот запам'ятає ваш чат для тривог (без координат)",
    expires_in_min: 15,
  };
}

async function telegramUnlink(deps: GuardianDeps, me: UserRow) {
  const { error } = await deps.db.from("guardian_telegram").delete().eq("user_id", me.id);
  if (error) dbFail("guardian_telegram delete", error);
  return { done_label: "Telegram відключено" };
}

// ─── Обробник ──────────────────────────────────────────────────────────────

export async function handleGuardian(req: Request, deps: GuardianDeps): Promise<Response> {
  assertMethod(req, ["GET", "POST"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-guardian");
  const user = await requireUser(req, deps.verify);
  const me = await requireMe(deps.db, user);
  const now = deps.now ? deps.now() : new Date();

  if (req.method === "GET") {
    const p = new URL(req.url).searchParams;
    const hike = p.get("hike");
    if (hike !== null) return ok(await hikeDetail(deps, me, hike, p.get("since"), now), req);
    return ok(await overview(deps, me, now), req);
  }

  const body = await readJson(req);
  if (body === null || typeof body !== "object" || Array.isArray(body)) throw new HttpError(400, "invalid_body", "Очікується { action, ... }");
  const b = body as Record<string, unknown>;
  switch (b.action) {
    case "invite":
      return ok(await invite(deps, me, b, now), req);
    case "accept_invite":
      return ok(await answerInvite(deps, me, b, true, now), req);
    case "decline_invite":
      return ok(await answerInvite(deps, me, b, false, now), req);
    case "remove":
      return ok(await unlink(deps, me, b, true), req);
    case "resign":
      return ok(await unlink(deps, me, b, false), req);
    case "start":
      return ok(await start(deps, me, b, now), req);
    case "track":
      return ok(await track(deps, me, b, now), req);
    case "ok":
    case "extend":
    case "sos":
    case "sos_cancel":
    case "finish":
      return ok(await setStatus(deps, me, b, b.action, now), req);
    case "telegram_link":
      return ok(await telegramLink(deps, me, now), req);
    case "telegram_unlink":
      return ok(await telegramUnlink(deps, me), req);
    default:
      throw new HttpError(400, "invalid_action", "Невідома дія");
  }
}

// ─── Розклад (v1-guardian-tick) ────────────────────────────────────────────

export interface TickDeps extends Omit<GuardianDeps, "verify"> {
  serviceKey: string;
}

/** Щохвилини (pg_cron): «Все добре?» у час повернення, тривога за 15 хв без відповіді, автозакриття. */
export async function handleGuardianTick(req: Request, deps: TickDeps): Promise<Response> {
  if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Лише POST");
  const auth = req.headers.get("Authorization") ?? "";
  if (!deps.serviceKey || auth !== `Bearer ${deps.serviceKey}`) throw new HttpError(401, "unauthorized", "Лише для розкладу");
  const now = deps.now ? deps.now() : new Date();
  const { data, error } = await deps.db.rpc("hike_tick", { p_now: now.toISOString() });
  if (error) dbFail("hike_tick", error);
  const events = (data ?? []) as Array<{ hike_id: string; kind: "check" | "alert" | "autoclose"; owner_id: string }>;
  const owners = await loadUsers(deps.db, events.map((e) => e.owner_id));
  const fullDeps = deps as unknown as GuardianDeps;
  for (const e of events) {
    const owner = owners.get(e.owner_id);
    if (e.kind === "check") {
      await pushTo(fullDeps, e.owner_id, {
        title: "Все добре?",
        body: `Настав час повернення. Відповідайте — інакше за ${CHECK_ANSWER_MIN} хв сповістимо Наглядача`,
        data: { type: "hike_check", hike_id: e.hike_id },
      }, true);
      continue;
    }
    const h = await loadHike(deps.db, e.hike_id);
    if (!h) continue;
    if (e.kind === "alert") {
      await notifyGuardians(fullDeps, h, owner, "alert");
      await pushTo(fullDeps, e.owner_id, {
        title: "Наглядача сповіщено",
        body: "Ви не відповіли на «Все добре?». Якщо все гаразд — відкрийте застосунок і натисніть «Так, все добре»",
        data: { type: "hike_alert_owner", hike_id: e.hike_id },
      }, true);
    } else {
      await notifyGuardians(fullDeps, h, owner, "autoclose");
    }
  }
  return ok({ events: events.length }, req);
}

// ─── Telegram webhook (v1-telegram-webhook) ────────────────────────────────

export interface TelegramWebhookDeps {
  db: GuardianDb;
  secret: string;
  telegram: (chatId: number, text: string) => Promise<boolean>;
  now?: () => Date;
}

/** /start <код> — прив'язати чат до акаунта; /stop — відв'язати. Відповідь Telegram — завжди 200. */
export async function handleTelegramWebhook(req: Request, deps: TelegramWebhookDeps): Promise<Response> {
  if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Лише POST");
  if (!deps.secret || req.headers.get("X-Telegram-Bot-Api-Secret-Token") !== deps.secret) {
    throw new HttpError(401, "unauthorized", "Невірний секрет");
  }
  const update = (await readJson(req)) as { message?: { chat?: { id?: number; type?: string }; text?: string } };
  const chatId = update?.message?.chat?.id;
  const text = (update?.message?.text ?? "").trim();
  if (typeof chatId !== "number" || update.message?.chat?.type !== "private") return ok({ ignored: true }, req);
  const now = deps.now ? deps.now() : new Date();

  if (/^\/stop\b/.test(text)) {
    await deps.db.from("guardian_telegram").delete().eq("chat_id", chatId);
    await deps.telegram(chatId, "Готово: тривоги Наглядача більше не надходитимуть у цей чат.");
    return ok({ unlinked: true }, req);
  }
  const m = /^\/start\s+([A-Za-z0-9_-]{16,64})$/.exec(text);
  if (!m) {
    await deps.telegram(chatId, "Щоб отримувати тривоги Наглядача, відкрийте «Грибний Радар» → «Безпека» → «Отримувати тривоги в Telegram».");
    return ok({ ignored: true }, req);
  }
  const hash = await sha256(m[1]);
  const { data, error } = await deps.db.from("telegram_link_codes").select("user_id, expires_at").eq("code_hash", hash).maybeSingle();
  if (error) dbFail("telegram_link_codes select", error);
  const row = data as { user_id: string; expires_at: string } | null;
  if (!row || new Date(row.expires_at) < now) {
    await deps.telegram(chatId, "Посилання застаріло. Відкрийте застосунок і натисніть «Отримувати тривоги в Telegram» ще раз.");
    return ok({ linked: false }, req);
  }
  await deps.db.from("telegram_link_codes").delete().eq("code_hash", hash);
  await deps.db.from("guardian_telegram").delete().eq("chat_id", chatId);
  const { error: e2 } = await deps.db.from("guardian_telegram")
    .upsert({ user_id: row.user_id, chat_id: chatId, linked_at: now.toISOString() }, { onConflict: "user_id" });
  if (e2) dbFail("guardian_telegram upsert", e2);
  await deps.telegram(chatId, "Готово! Тривоги Наглядача надходитимуть сюди — без координат: місце видно лише в застосунку. Відключити — /stop");
  return ok({ linked: true }, req);
}
