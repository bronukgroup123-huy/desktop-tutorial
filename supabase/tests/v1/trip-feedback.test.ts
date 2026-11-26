// B3.11 «Знайшли?» — v1-analysis/feedback (ADR-014). Правила балів і довіри — у SQL-тесті trip_feedback.sql.
import { assert, assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { handleAnalysis } from "../../functions/_shared/v1/analysis.ts";
import { accuracyLabel, FEEDBACK_EXPLAIN } from "../../functions/_shared/v1/trip-feedback.ts";
import { type Call, mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

const NOW = new Date("2026-11-26T22:30:00Z"); // у Києві вже 27-ме, 00:30
const URL_ = "http://localhost/v1-analysis/feedback";
const CTX = { source: "forecast", area_id: "a1", hike_id: null, title: "Біля Броників" };

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "rpc.trip_feedback_context": { data: [CTX], error: null },
    "rpc.trip_feedback_accuracy": { data: [{ hits: 3, total: 4 }], error: null },
    "trip_feedback.select": { data: [], error: null },
    ...extra,
  });
}

const run = (d: ReturnType<typeof db>, r: Request, isAnonymous = false) =>
  handle((x) =>
    handleAnalysis(x, { db: d, verify: verifyAs("u1", isAnonymous), forecast: () => Promise.resolve([]), now: () => NOW })
  )(r);

const find = (d: ReturnType<typeof db>, key: string): Call | undefined => d.calls.find((c) => c.key === key);

Deno.test("feedback GET: є прогноз ділянки поруч і ще не відповідали → питаємо з поясненням і точністю", async () => {
  const d = db();
  const res = await run(d, req("GET", `${URL_}?lat=50.45&lng=30.52`));
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.ask, true);
  assertEquals(data.title, "Знайшли гриби?");
  assertEquals(data.subtitle, "Біля ділянки «Біля Броників»");
  assertEquals(data.explain_label, FEEDBACK_EXPLAIN);
  assertEquals(data.answers.map((a: { id: string }) => a.id), ["found", "not_found"]);
  assertEquals(data.accuracy_label, "Прогноз для вас збувся 3 з 4 разів");
  // день за замовчуванням — київська дата
  assertEquals(find(d, "rpc.trip_feedback_context")?.args[0], { p_user_id: "u1", p_day: "2026-11-27", p_lat: 50.45, p_lng: 30.52 });
  // перевірка «вже відповідали» — за ділянкою й днем
  const check = find(d, "trip_feedback.select")!;
  assertEquals(check.filters.filter(([k]) => k !== "limit"), [["user_id", "u1"], ["source", "forecast"], ["trip_day", "2026-11-27"], ["area_id", "a1"]]);
});

Deno.test("feedback GET: немає зв'язку або вже відповіли → не питаємо", async () => {
  const none = await run(db({ "rpc.trip_feedback_context": { data: [], error: null } }), req("GET", `${URL_}?lat=50&lng=30`));
  assertEquals((await none.json()).data, { ask: false, accuracy_label: "Прогноз для вас збувся 3 з 4 разів" });
  const done = await run(db({ "trip_feedback.select": { data: [{ id: "f1" }], error: null } }), req("GET", `${URL_}?lat=50&lng=30`));
  assertEquals((await done.json()).data.ask, false);
});

Deno.test("feedback GET: похід із Наглядачем — перевірка за походом; гостю — без обіцянки балів", async () => {
  const d = db({ "rpc.trip_feedback_context": { data: [{ source: "hike", area_id: null, hike_id: "h1", title: null }], error: null } });
  const { data } = await (await run(d, req("GET", `${URL_}?lat=50&lng=30&day=2026-11-26`), true)).json();
  assertEquals(data.subtitle, "Похід із Наглядачем");
  assertEquals(data.points_label, "Бали за відгуки — після входу через Google або Apple");
  assertEquals(find(d, "trip_feedback.select")!.filters.filter(([k]) => k !== "limit"), [["user_id", "u1"], ["source", "hike"], ["hike_id", "h1"]]);
});

Deno.test("feedback GET: координати й день перевіряються", async () => {
  for (const q of ["lat=95&lng=30", "lat=50", "lat=x&lng=30", "lat=50&lng=30&day=27.11.2026"]) {
    const res = await run(db(), req("GET", `${URL_}?${q}`));
    assertEquals(res.status, 400, q);
  }
});

Deno.test("feedback POST: прийнято — бали через добу; у SQL іде гість/акаунт і відповідь", async () => {
  const d = db({ "rpc.submit_trip_feedback": { data: { ok: true, points: "pending", points_reason: null }, error: null } });
  const res = await run(d, req("POST", URL_, { lat: 50.45, lng: 30.52, day: "2026-11-26", answer: "found" }));
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.message_label, "Дякуємо! Записали: знайшли");
  assertEquals(data.points, "pending");
  assertEquals(data.points_label, "+2 бали — через добу, після перевірки");
  assertEquals(data.accuracy_label, "Прогноз для вас збувся 3 з 4 разів");
  assertEquals(find(d, "rpc.submit_trip_feedback")?.args[0], {
    p_user_id: "u1", p_is_guest: false, p_day: "2026-11-26", p_lat: 50.45, p_lng: 30.52, p_answer: "found",
  });
});

Deno.test("feedback POST: без балів — м'яке пояснення причини (суперечність, ліміт, гість)", async () => {
  for (const [reason, part] of [["contradiction", "Якщо щось знайшли"], ["daily_limit", "раз на добу"], ["guest", "після входу"]]) {
    const d = db({ "rpc.submit_trip_feedback": { data: { ok: true, points: "none", points_reason: reason }, error: null } });
    const { data } = await (await run(d, req("POST", URL_, { lat: 50, lng: 30, answer: "not_found" }))).json();
    assertEquals(data.points, "none");
    assert(String(data.points_label).includes(part), reason);
    assertEquals(data.message_label, "Дякуємо! Записали: не знайшли");
  }
});

Deno.test("feedback POST: немає зв'язку → 422 з текстом сервера; вже відповіли → 409; погана відповідь → 400", async () => {
  const no = await run(db({ "rpc.submit_trip_feedback": { data: { ok: false, code: "no_trip_context", message: "Цей похід не біля жодної вашої ділянки" }, error: null } }),
    req("POST", URL_, { lat: 50, lng: 30, answer: "found" }));
  assertEquals(no.status, 422);
  assertEquals((await no.json()).error, "no_trip_context");
  const again = await run(db({ "rpc.submit_trip_feedback": { data: { ok: false, code: "already_answered", message: "Ви вже відповіли" }, error: null } }),
    req("POST", URL_, { lat: 50, lng: 30, answer: "found" }));
  assertEquals(again.status, 409);
  const d = db();
  const bad = await run(d, req("POST", URL_, { lat: 50, lng: 30, answer: "maybe" }));
  assertEquals(bad.status, 400);
  assertEquals(find(d, "rpc.submit_trip_feedback"), undefined);
});

Deno.test("feedback: помилка БД → 500 без деталей", async () => {
  const res = await run(db({ "rpc.trip_feedback_context": { data: null, error: { message: "secret detail" } } }), req("GET", `${URL_}?lat=50&lng=30`));
  assertEquals(res.status, 500);
  assert(!(await res.text()).includes("secret"));
});

Deno.test("accuracyLabel: відмінки «разу / разів»; без відгуків — null", () => {
  assertEquals(accuracyLabel(0, 0), null);
  assertEquals(accuracyLabel(1, 1), "Прогноз для вас збувся 1 з 1 разу");
  assertEquals(accuracyLabel(7, 11), "Прогноз для вас збувся 7 з 11 разів");
  assertEquals(accuracyLabel(15, 21), "Прогноз для вас збувся 15 з 21 разу");
});
