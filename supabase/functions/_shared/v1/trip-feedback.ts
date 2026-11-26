// ============================================================================
// «Знайшли?» — чесний відгук після походу (BACKEND_PLAN B3.11; ADR-014, ADR-019 §19.9)
//
// GET  v1-analysis/feedback?lat=&lng=&day=
//   → 200 { data: { ask, title?, subtitle?, explain_label?, answers?, skip_label?, points_label?,
//                   accuracy_label } }
//   Чи питати після «Я вдома»: сервер шукає зв'язок походу з прогнозом ділянки чи походом із Наглядачем
//   і чи на нього вже відповіли. Немає зв'язку — ask = false (не питаємо даремно).
// POST v1-analysis/feedback  { lat, lng, day?, answer: found | not_found }
//   → 200 { data: { message_label, points, points_label, accuracy_label } }
//   422 no_trip_context · 409 already_answered · 400 validation_error
//
// lat/lng — середина треку походу; сервер перевіряє відстань і НЕ зберігає місце. day — київська дата
// походу (сьогодні або вчора; за замовчуванням сьогодні). Бали й довіра — у SQL `submit_trip_feedback`.
// ============================================================================

import { type AuthUser, HttpError, ok, readJson } from "../http.ts";

export interface FeedbackDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

const KYIV_DATE = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Kyiv" });
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

export const FEEDBACK_TITLE = "Знайшли гриби?";

/** ADR-014 §14.1: людина бачить, що чесна відповідь працює на неї. Лише те, що справді відбувається. */
export const FEEDBACK_EXPLAIN =
  "Чим чесніша відповідь, тим точніший прогноз — передусім для вас: ми рахуємо, як часто він справджується " +
  "саме у ваших лісах. «Так» з вашої ділянки допоможе налаштувати прогноз для області.";

export const FEEDBACK_ANSWERS = [
  { id: "found", label: "Так, знайшли" },
  { id: "not_found", label: "Ні, не знайшли" },
] as const;

/** Що сталося з балами — м'яко, без звинувачень (ADR-014 §14.2). */
export const POINTS_LABEL: Record<string, string> = {
  pending: "+2 бали — через добу, після перевірки",
  guest: "Бали за відгуки — після входу через Google або Apple",
  daily_limit: "Бали за відгук — раз на добу. Цей відгук теж допоможе прогнозу",
  contradiction:
    "Цього дня ви поставили точку з фото поруч. Якщо щось знайшли — це «Так». За цю відповідь балів немає",
  low_trust: "Бали за відгуки зараз не нараховуються: кілька відповідей розійшлися з вашими точками",
};

interface Ctx {
  source: "forecast" | "hike";
  area_id: string | null;
  hike_id: string | null;
  title: string | null;
}

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-analysis/feedback] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

function validation(message: string): HttpError {
  return new HttpError(400, "validation_error", message);
}

function coord(raw: unknown, name: string, min: number, max: number): number {
  const n = typeof raw === "string" && raw.trim() !== "" ? Number(raw) : raw;
  if (typeof n !== "number" || !Number.isFinite(n) || n < min || n > max) {
    throw validation(`${name}: число від ${min} до ${max}`);
  }
  return n;
}

function tripDay(raw: unknown, now: Date): string {
  if (raw === undefined || raw === null || raw === "") return KYIV_DATE.format(now);
  if (typeof raw !== "string" || !DAY_RE.test(raw)) throw validation("day: дата YYYY-MM-DD");
  return raw;
}

/** «з 1 разу», «з 2 разів», «з 21 разу». */
export function accuracyLabel(hits: number, total: number): string | null {
  if (total <= 0) return null;
  const word = total % 10 === 1 && total % 100 !== 11 ? "разу" : "разів";
  return `Прогноз для вас збувся ${hits} з ${total} ${word}`;
}

async function accuracy(db: FeedbackDb, userId: string): Promise<string | null> {
  const { data, error } = await db.rpc("trip_feedback_accuracy", { p_user_id: userId });
  if (error) dbFail("trip_feedback_accuracy", error);
  const row = (Array.isArray(data) ? data[0] : data) as { hits?: number; total?: number } | null;
  return accuracyLabel(Number(row?.hits ?? 0), Number(row?.total ?? 0));
}

async function context(db: FeedbackDb, userId: string, day: string, lat: number, lng: number): Promise<Ctx | null> {
  const { data, error } = await db.rpc("trip_feedback_context", { p_user_id: userId, p_day: day, p_lat: lat, p_lng: lng });
  if (error) dbFail("trip_feedback_context", error);
  const row = (Array.isArray(data) ? data[0] : data) as Ctx | null | undefined;
  return row?.source ? row : null;
}

async function answered(db: FeedbackDb, userId: string, day: string, ctx: Ctx): Promise<boolean> {
  let q = db.from("trip_feedback").select("id").eq("user_id", userId).eq("source", ctx.source);
  q = ctx.source === "hike" ? q.eq("hike_id", ctx.hike_id) : q.eq("trip_day", day).eq("area_id", ctx.area_id);
  const { data, error } = await q.limit(1);
  if (error) dbFail("trip_feedback check", error);
  return Array.isArray(data) && data.length > 0;
}

function subtitle(ctx: Ctx): string {
  return ctx.source === "hike" ? "Похід із Наглядачем" : `Біля ділянки «${ctx.title ?? "Моя ділянка"}»`;
}

async function prompt(req: Request, user: AuthUser, db: FeedbackDb, now: Date): Promise<Response> {
  const params = new URL(req.url).searchParams;
  const lat = coord(params.get("lat"), "lat", -90, 90);
  const lng = coord(params.get("lng"), "lng", -180, 180);
  const day = tripDay(params.get("day"), now);
  const ctx = await context(db, user.id, day, lat, lng);
  const accuracy_label = await accuracy(db, user.id);
  if (!ctx || await answered(db, user.id, day, ctx)) return ok({ ask: false, accuracy_label }, req);
  return ok({
    ask: true,
    title: FEEDBACK_TITLE,
    subtitle: subtitle(ctx),
    explain_label: FEEDBACK_EXPLAIN,
    answers: FEEDBACK_ANSWERS,
    skip_label: "Не зараз",
    points_label: user.isAnonymous ? POINTS_LABEL.guest : "+2 бали за чесну відповідь — раз на добу",
    accuracy_label,
  }, req);
}

async function submit(req: Request, user: AuthUser, db: FeedbackDb, now: Date): Promise<Response> {
  const body = await readJson(req);
  if (!body || typeof body !== "object" || Array.isArray(body)) throw validation("Очікується JSON-об'єкт");
  const b = body as Record<string, unknown>;
  const lat = coord(b.lat, "lat", -90, 90);
  const lng = coord(b.lng, "lng", -180, 180);
  const day = tripDay(b.day, now);
  if (b.answer !== "found" && b.answer !== "not_found") throw validation("answer: found або not_found");

  const { data, error } = await db.rpc("submit_trip_feedback", {
    p_user_id: user.id,
    p_is_guest: user.isAnonymous,
    p_day: day,
    p_lat: lat,
    p_lng: lng,
    p_answer: b.answer,
  });
  if (error) dbFail("submit_trip_feedback", error);
  const r = (data ?? {}) as { ok?: boolean; code?: string; message?: string; points?: string; points_reason?: string };
  if (!r.ok) {
    const status = r.code === "no_trip_context" ? 422 : r.code === "already_answered" ? 409 : 400;
    throw new HttpError(status, r.code ?? "validation_error", r.message ?? "Відгук не прийнято");
  }
  const reason = r.points === "pending" ? "pending" : r.points_reason ?? "";
  return ok({
    message_label: b.answer === "found" ? "Дякуємо! Записали: знайшли" : "Дякуємо! Записали: не знайшли",
    points: r.points ?? "none",
    points_label: POINTS_LABEL[reason] ?? null,
    accuracy_label: await accuracy(db, user.id),
  }, req);
}

export function isFeedbackPath(url: URL): boolean {
  return /\/v1-analysis\/feedback\/?$/.test(url.pathname);
}

export function handleTripFeedback(req: Request, user: AuthUser, db: FeedbackDb, now: Date): Promise<Response> {
  if (req.method === "GET") return prompt(req, user, db, now);
  if (req.method === "POST") return submit(req, user, db, now);
  return Promise.reject(new HttpError(405, "method_not_allowed", "Лише GET або POST"));
}
