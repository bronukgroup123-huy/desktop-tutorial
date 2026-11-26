// ============================================================================
// v1-quiz — тести знань (BACKEND_PLAN B3.10; ADR-023, бали й сертифікат — ADR-012/013)
//
// GET  v1-quiz
//   → { data: { modules: [{ id, position, title, summary, points, status, best_percent, passed_at,
//                next_scored_at, questions_per_attempt, pass_percent }], passed_count, total,
//                certified_at, disclaimer_label, guest_label } }
//   status: soon (готується) | locked (спершу попередній) | open | passed
// POST v1-quiz/attempts                 { module_id, practice? }
//   → { data: { attempt_id, practice, expires_at, questions: [{ id, kind, prompt, options: [{ id, text }] }] } }
//   Правильних відповідей і пояснень тут немає. Гість — лише practice: true.
// POST v1-quiz/attempts/{id}/submit     { answers: { <question_id>: [<option_id>, …] } }
//   → { data: { correct, total, percent, pass_percent, passed, critical_failed, points_awarded,
//               certified_now, result_label, review: [{ id, prompt, options, chosen, correct, is_correct,
//               critical, explanation, source }] } }
// POST v1-quiz/questions/{id}/report    { comment? }  → { data: { reported: true } }
//
// Перевірка, бали й сертифікат — у SQL (quiz_start / quiz_submit); тут — валідація і тексти.
// ============================================================================

import {
  assertMethod,
  type AuthUser,
  enforceRateLimit,
  HttpError,
  ok,
  readJson,
  requireUser,
  type TokenVerifier,
} from "../http.ts";

export interface QuizDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

export interface QuizDeps {
  db: QuizDb;
  verify: TokenVerifier;
}

const MODULE_RE = /^[a-z0-9_]{1,40}$/;
const QUESTION_RE = /^[a-z0-9_]{1,60}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_ANSWERS = 30;
const MAX_CHOSEN = 8;

/** ADR-023 §23.2: тест навчає, але не дозволяє їсти знайдене. */
export const DISCLAIMER_LABEL = "Тест навчає, але не дає дозволу їсти знайдені гриби";
export const GUEST_LABEL = "Бали за тести й сертифікат — після входу через Google або Apple. Тренуватися можна й так";

/** Код SQL → HTTP-статус. */
const STATUS: Record<string, number> = {
  module_not_found: 404,
  module_soon: 409,
  module_locked: 409,
  already_passed: 409,
  retry_later: 429,
  registration_required: 403,
  attempt_not_found: 404,
  already_submitted: 409,
  attempt_expired: 410,
  question_not_found: 404,
  validation_error: 400,
};

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-quiz] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

function validation(message: string): HttpError {
  return new HttpError(400, "validation_error", message);
}

function asObject(body: unknown): Record<string, unknown> {
  if (!body || typeof body !== "object" || Array.isArray(body)) throw validation("Очікується JSON-об'єкт");
  return body as Record<string, unknown>;
}

/** Відмова з SQL — у HTTP з текстом сервера. */
function refuse(r: { code?: string; message?: string; next_scored_at?: string }): never {
  const code = r.code ?? "validation_error";
  const headers: Record<string, string> = {};
  if (code === "retry_later" && r.next_scored_at) {
    const secs = Math.max(60, Math.ceil((new Date(r.next_scored_at).getTime() - Date.now()) / 1000));
    headers["Retry-After"] = String(secs);
  }
  throw new HttpError(STATUS[code] ?? 400, code, r.message ?? "Не вдалося", headers);
}

async function rpc(db: QuizDb, fn: string, params: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await db.rpc(fn, params);
  if (error) dbFail(fn, error);
  return (data ?? {}) as Record<string, unknown>;
}

/** Відповіді: { питання: [варіанти] } — не більше 30 питань, до 8 варіантів, лише відомі формати id. */
export function validateAnswers(raw: unknown): Record<string, string[]> {
  const obj = asObject(raw);
  const entries = Object.entries(obj);
  if (entries.length > MAX_ANSWERS) throw validation("Забагато відповідей");
  const out: Record<string, string[]> = {};
  for (const [qid, chosen] of entries) {
    if (!QUESTION_RE.test(qid)) throw validation("Невідоме питання");
    if (!Array.isArray(chosen) || chosen.length > MAX_CHOSEN || chosen.some((c) => typeof c !== "string" || c.length > 40)) {
      throw validation("Відповідь — список варіантів");
    }
    out[qid] = chosen as string[];
  }
  return out;
}

function resultLabel(r: Record<string, unknown>): string {
  const pct = Number(r.percent ?? 0);
  if (r.practice === true) return `Тренування: ${r.correct} з ${r.total} (${pct} %)`;
  if (r.passed === true) {
    const pts = Number(r.points_awarded ?? 0);
    return r.certified_now === true
      ? `Модуль зараховано! +${pts} балів. Ви пройшли всі модулі — отримали сертифікат знань`
      : pts > 0 ? `Модуль зараховано! +${pts} балів` : "Модуль зараховано";
  }
  if (r.critical_failed === true) {
    return "Не зараховано: помилка в критичному питанні. У лісі така помилка може бути останньою — перегляньте пояснення";
  }
  return `Не зараховано: ${r.correct} з ${r.total} (${pct} %), потрібно ${r.pass_percent} %. Наступна спроба на бали — через добу`;
}

async function overview(db: QuizDb, user: AuthUser): Promise<Record<string, unknown>> {
  const data = await rpc(db, "quiz_overview", { p_user_id: user.id });
  return { ...data, disclaimer_label: DISCLAIMER_LABEL, guest_label: user.isAnonymous ? GUEST_LABEL : null };
}

async function start(req: Request, db: QuizDb, user: AuthUser): Promise<Record<string, unknown>> {
  const b = asObject(await readJson(req));
  if (typeof b.module_id !== "string" || !MODULE_RE.test(b.module_id)) throw validation("module_id — id модуля");
  if (b.practice !== undefined && typeof b.practice !== "boolean") throw validation("practice — true або false");
  const r = await rpc(db, "quiz_start", {
    p_user_id: user.id,
    p_is_guest: user.isAnonymous,
    p_module_id: b.module_id,
    p_practice: b.practice === true,
  });
  if (r.ok !== true) refuse(r);
  const { ok: _ok, ...rest } = r;
  return rest;
}

async function submit(req: Request, db: QuizDb, user: AuthUser, attemptId: string): Promise<Record<string, unknown>> {
  const b = asObject(await readJson(req));
  const answers = validateAnswers(b.answers ?? {});
  const r = await rpc(db, "quiz_submit", { p_user_id: user.id, p_attempt_id: attemptId, p_answers: answers });
  if (r.ok !== true) refuse(r);
  const { ok: _ok, ...rest } = r;
  return { ...rest, result_label: resultLabel(r) };
}

async function report(req: Request, db: QuizDb, user: AuthUser, questionId: string): Promise<Record<string, unknown>> {
  const b = asObject(await readJson(req));
  if (b.comment !== undefined && b.comment !== null && (typeof b.comment !== "string" || b.comment.length > 500)) {
    throw validation("comment — до 500 символів");
  }
  const r = await rpc(db, "quiz_report", {
    p_user_id: user.id,
    p_question_id: questionId,
    p_comment: typeof b.comment === "string" ? b.comment : null,
  });
  if (r.ok !== true) refuse(r);
  return { reported: true, label: "Дякуємо! Перевіримо це питання" };
}

export async function handleQuiz(req: Request, deps: QuizDeps): Promise<Response> {
  assertMethod(req, ["GET", "POST"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-quiz");
  const user = await requireUser(req, deps.verify);
  const path = new URL(req.url).pathname.replace(/\/+$/, "");

  if (req.method === "GET") {
    if (!/\/v1-quiz$/.test(path)) throw new HttpError(404, "not_found", "Невідомий шлях");
    return ok(await overview(deps.db, user), req);
  }
  if (/\/v1-quiz\/attempts$/.test(path)) return ok(await start(req, deps.db, user), req);
  const sub = path.match(/\/v1-quiz\/attempts\/([^/]+)\/submit$/);
  if (sub) {
    if (!UUID_RE.test(sub[1])) throw new HttpError(404, "attempt_not_found", "Спробу не знайдено");
    return ok(await submit(req, deps.db, user, sub[1].toLowerCase()), req);
  }
  const rep = path.match(/\/v1-quiz\/questions\/([^/]+)\/report$/);
  if (rep) {
    if (!QUESTION_RE.test(rep[1])) throw new HttpError(404, "question_not_found", "Питання не знайдено");
    return ok(await report(req, deps.db, user, rep[1]), req);
  }
  throw new HttpError(404, "not_found", "Невідомий шлях");
}
