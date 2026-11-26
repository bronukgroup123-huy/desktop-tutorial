// B3.10a: v1-quiz (ADR-023). Правила (черга модулів, бали, критичні, сертифікат) — у SQL-тесті knowledge_tests.sql.
import { assert, assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { DISCLAIMER_LABEL, GUEST_LABEL, handleQuiz, validateAnswers } from "../../functions/_shared/v1/quiz.ts";
import { type Call, mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

const URL_ = "http://localhost/v1-quiz";
const ATT = "11111111-2222-4333-8444-555555555555";

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "rpc.quiz_overview": { data: { modules: [{ id: "app", status: "open" }], passed_count: 0, total: 7, certified_at: null }, error: null },
    ...extra,
  });
}
const run = (d: ReturnType<typeof db>, r: Request, isAnonymous = false) =>
  handle((x) => handleQuiz(x, { db: d, verify: verifyAs("u1", isAnonymous) }))(r);
const find = (d: ReturnType<typeof db>, key: string): Call | undefined => d.calls.find((c) => c.key === key);

Deno.test("quiz GET: модулі з сервера + підпис «не дозвіл їсти»; гостю — пояснення про бали", async () => {
  const { data } = await (await run(db(), req("GET", URL_))).json();
  assertEquals(data.modules[0].id, "app");
  assertEquals(data.disclaimer_label, DISCLAIMER_LABEL);
  assertEquals(data.guest_label, null);
  const guest = (await (await run(db(), req("GET", URL_), true)).json()).data;
  assertEquals(guest.guest_label, GUEST_LABEL);
});

Deno.test("quiz POST attempts: модуль і режим ідуть у SQL (гість — з позначкою); відповідь без ok", async () => {
  const d = db({ "rpc.quiz_start": { data: { ok: true, attempt_id: ATT, practice: true, questions: [{ id: "q1" }] }, error: null } });
  const res = await run(d, req("POST", `${URL_}/attempts`, { module_id: "app", practice: true }), true);
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data, { attempt_id: ATT, practice: true, questions: [{ id: "q1" }] });
  assertEquals(find(d, "rpc.quiz_start")?.args[0], { p_user_id: "u1", p_is_guest: true, p_module_id: "app", p_practice: true });
});

Deno.test("quiz POST attempts: відмови SQL → HTTP з текстом сервера; пауза — Retry-After", async () => {
  for (const [code, status] of [["module_locked", 409], ["registration_required", 403], ["module_not_found", 404], ["already_passed", 409]] as const) {
    const res = await run(db({ "rpc.quiz_start": { data: { ok: false, code, message: "текст" }, error: null } }), req("POST", `${URL_}/attempts`, { module_id: "app" }));
    assertEquals(res.status, status, code);
    assertEquals((await res.json()).message, "текст");
  }
  const later = new Date(Date.now() + 3600_000).toISOString();
  const res = await run(db({ "rpc.quiz_start": { data: { ok: false, code: "retry_later", message: "через добу", next_scored_at: later }, error: null } }), req("POST", `${URL_}/attempts`, { module_id: "app" }));
  assertEquals(res.status, 429);
  assert(Number(res.headers.get("Retry-After")) > 3000);
});

Deno.test("quiz POST attempts: некоректний module_id / practice → 400, у БД не йдемо", async () => {
  for (const body of [{}, { module_id: "../x" }, { module_id: "app", practice: "yes" }]) {
    const d = db();
    assertEquals((await run(d, req("POST", `${URL_}/attempts`, body))).status, 400);
    assertEquals(find(d, "rpc.quiz_start"), undefined);
  }
});

Deno.test("quiz submit: відповіді в SQL; підсумок словами — зараховано / критичне / не вистачило / тренування", async () => {
  const base = { ok: true, correct: 9, total: 10, percent: 90, pass_percent: 80, review: [] };
  const cases: Array<[Record<string, unknown>, string]> = [
    [{ ...base, passed: true, points_awarded: 10, practice: false }, "Модуль зараховано! +10 балів"],
    [{ ...base, passed: true, points_awarded: 25, practice: false, certified_now: true }, "сертифікат знань"],
    [{ ...base, passed: false, critical_failed: true, practice: false }, "критичному питанні"],
    [{ ...base, correct: 7, percent: 70, passed: false, practice: false }, "7 з 10 (70 %), потрібно 80 %"],
    [{ ...base, passed: true, practice: true }, "Тренування: 9 з 10"],
  ];
  for (const [r, part] of cases) {
    const d = db({ "rpc.quiz_submit": { data: r, error: null } });
    const res = await run(d, req("POST", `${URL_}/attempts/${ATT}/submit`, { answers: { q1: ["a"], q2: ["b", "c"] } }));
    assertEquals(res.status, 200);
    const { data } = await res.json();
    assert(String(data.result_label).includes(part), `${part} ← ${data.result_label}`);
    assertEquals(find(d, "rpc.quiz_submit")?.args[0], { p_user_id: "u1", p_attempt_id: ATT, p_answers: { q1: ["a"], q2: ["b", "c"] } });
  }
});

Deno.test("quiz submit: чужа / прострочена / здана спроба — коди SQL; поганий id спроби — 404 без БД", async () => {
  for (const [code, status] of [["attempt_not_found", 404], ["attempt_expired", 410], ["already_submitted", 409]] as const) {
    const res = await run(db({ "rpc.quiz_submit": { data: { ok: false, code, message: "m" }, error: null } }), req("POST", `${URL_}/attempts/${ATT}/submit`, { answers: {} }));
    assertEquals(res.status, status, code);
  }
  const d = db();
  assertEquals((await run(d, req("POST", `${URL_}/attempts/not-a-uuid/submit`, { answers: {} }))).status, 404);
  assertEquals(find(d, "rpc.quiz_submit"), undefined);
});

Deno.test("validateAnswers: лише { питання: [варіанти] } у межах", () => {
  assertEquals(validateAnswers({ app_1: ["a"], app_2: [] }), { app_1: ["a"], app_2: [] });
  for (const bad of [[], { "Bad Id": ["a"] }, { app_1: "a" }, { app_1: [1] }, { app_1: Array(9).fill("a") },
    Object.fromEntries(Array.from({ length: 31 }, (_, i) => [`q${i}`, ["a"]]))]) {
    let thrown = false;
    try {
      validateAnswers(bad);
    } catch {
      thrown = true;
    }
    assert(thrown, JSON.stringify(bad).slice(0, 40));
  }
});

Deno.test("quiz report: скарга з коментарем іде в SQL; невідомий шлях — 404; помилка БД — 500 без деталей", async () => {
  const d = db({ "rpc.quiz_report": { data: { ok: true, hidden: false }, error: null } });
  const res = await run(d, req("POST", `${URL_}/questions/app_1/report`, { comment: "Неточно" }));
  assertEquals((await res.json()).data.reported, true);
  assertEquals(find(d, "rpc.quiz_report")?.args[0], { p_user_id: "u1", p_question_id: "app_1", p_comment: "Неточно" });
  assertEquals((await run(db(), req("POST", `${URL_}/unknown`, {}))).status, 404);
  const broken = await run(db({ "rpc.quiz_overview": { data: null, error: { message: "secret detail" } } }), req("GET", URL_));
  assertEquals(broken.status, 500);
  assert(!(await broken.text()).includes("secret"));
});
