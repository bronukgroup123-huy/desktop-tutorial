import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import { actionsFor, handleFriends, normalizeQuery, type PushMessage } from "../../functions/_shared/v1/friends.ts";
import { mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

const URL = "http://localhost/v1-friends";
const ME = "11111111-1111-4111-8111-111111111111";
const PETRO = "22222222-2222-4222-8222-222222222222";
const NOW = new Date("2026-11-20T10:00:00Z");

const meRow = { id: ME, handle: "Олена_лісова" };
const petroRow = { id: PETRO, handle: "Петро", name: "Петро", avatar: null, rating: 75 };

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": (c) => ({
      data: c.filters.some(([k, v]) => k === "id" && v === ME) ? meRow : petroRow,
      error: null,
    }),
    ...extra,
  });
}

function run(d: ReturnType<typeof mockDb>, r: Request, opts: { anon?: boolean; sent?: Array<[string, PushMessage]> } = {}) {
  return handle((x) =>
    handleFriends(x, {
      db: d,
      verify: verifyAs(ME, opts.anon ?? false),
      now: () => NOW,
      send: (token, msg) => {
        opts.sent?.push([token, msg]);
        return Promise.resolve({ ok: true, unregistered: token === "dead-token" });
      },
    })
  )(r);
}

Deno.test("v1-friends: гість → 403 registration_required (ADR-001)", async () => {
  const res = await run(db(), req("GET", URL), { anon: true });
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, "registration_required");
});

Deno.test("v1-friends: без ніка → 409 profile_required", async () => {
  const d = db({ "users.select": { data: { id: ME, handle: null }, error: null } });
  const res = await run(d, req("GET", URL));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error, "profile_required");
});

Deno.test("v1-friends GET: список розкладено на друзів, запити, заблокованих; кнопки із сервера", async () => {
  const d = db({
    "rpc.friend_list": {
      data: [
        { kind: "friend", id: PETRO, handle: "Петро", name: "Петро", avatar: null, rating: 75, since: "2026-11-01" },
        { kind: "friend", id: "33333333-3333-4333-8333-333333333333", handle: "Андрій", name: "Андрій", avatar: null, rating: 0, since: "2026-11-02" },
        { kind: "incoming", id: "44444444-4444-4444-8444-444444444444", handle: "Ірина", name: "Ірина", avatar: null, rating: 0, since: "2026-11-03" },
        { kind: "blocked", id: "55555555-5555-4555-8555-555555555555", handle: "Спамер", name: null, avatar: null, rating: 0, since: "2026-11-04" },
      ],
      error: null,
    },
  });
  const res = await run(d, req("GET", URL));
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.friends.map((f: { handle: string }) => f.handle), ["Андрій", "Петро"]);
  assertEquals(data.incoming[0].actions.map((a: { id: string }) => a.id), ["accept", "decline", "report", "block"]);
  assertEquals(data.blocked[0].actions[0].id, "unblock");
  assertEquals(data.counts, { friends: 2, incoming: 1 });
  assertEquals(data.friends[1].level.label, "Слідопит");
  assertEquals(data.friends[1].avatar, { kind: "preset", id: "default" });
  // У картці немає нічого приватного
  for (const k of ["email", "home_region", "lat", "lng", "phone"]) assertEquals(k in data.friends[1], false);
});

Deno.test("v1-friends GET ?q: пошук — без @, малими літерами; коротко → підказка без запиту", async () => {
  const d = db({ "rpc.search_users_by_handle": { data: [{ ...petroRow, relation: "none" }], error: null } });
  const { data } = await (await run(d, req("GET", `${URL}?q=${encodeURIComponent("@ПЕТ")}`))).json();
  assertEquals(data.results.length, 1);
  assertEquals(data.results[0].actions[0].id, "request");
  const call = d.calls.find((c) => c.key === "rpc.search_users_by_handle")!;
  assertEquals((call.args[0] as { p_prefix: string }).p_prefix, "пет");

  const d2 = db();
  const short = (await (await run(d2, req("GET", `${URL}?q=${encodeURIComponent("п")}`))).json()).data;
  assertEquals(short.results, []);
  assertEquals(d2.calls.some((c) => c.key === "rpc.search_users_by_handle"), false);
});

Deno.test("v1-friends GET ?user: мене заблокували → 404 (блок ховає все)", async () => {
  const d = db({ "rpc.friend_relation": { data: "hidden", error: null } });
  const res = await run(d, req("GET", `${URL}?user=${encodeURIComponent("Петро")}`));
  assertEquals(res.status, 404);
  assertEquals((await res.json()).error, "user_not_found");
});

Deno.test("v1-friends GET ?user: публічний профіль без області й координат", async () => {
  const d = db({ "rpc.friend_relation": { data: "friends", error: null }, "rpc.friend_count": { data: 12, error: null } });
  const { data } = await (await run(d, req("GET", `${URL}?user=${PETRO}`))).json();
  assertEquals(data.profile.handle, "Петро");
  assertEquals(data.profile.friends_count, 12);
  assertEquals(data.profile.relation_label, "У друзях");
  assertEquals("home_region" in data.profile, false);
  assertEquals(data.profile.trophies, []);
});

Deno.test("v1-friends POST request: push отримувачу без координат; мертвий токен видаляється", async () => {
  const sent: Array<[string, PushMessage]> = [];
  const d = db({
    "rpc.friend_action": { data: { ok: true, relation: "outgoing", notify: "request" }, error: null },
    "rpc.push_tokens_of": { data: ["live-token", "dead-token"], error: null },
  });
  const res = await run(d, req("POST", URL, { action: "request", user_id: PETRO }), { sent });
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.user.relation, "outgoing");
  assertEquals(data.user.actions[0].id, "cancel");
  assertEquals(sent.length, 2);
  assertEquals(sent[0][1].body, "@Олена_лісова хоче додати вас у друзі");
  const push = d.calls.find((c) => c.key === "rpc.push_tokens_of")!;
  assertEquals((push.args[0] as { p_user: string }).p_user, PETRO);
  assertEquals(d.calls.some((c) => c.key === "push_devices.delete"), true);
});

Deno.test("v1-friends POST: помилки SQL → коди й статуси", async () => {
  for (const [code, status] of [["daily_limit", 429], ["request_cooldown", 429], ["friends_limit", 409], ["user_not_found", 404]] as const) {
    const d = db({ "rpc.friend_action": { data: { ok: false, code, message: "текст" }, error: null } });
    const res = await run(d, req("POST", URL, { action: "request", user_id: PETRO }));
    assertEquals(res.status, status);
    const body = await res.json();
    assertEquals(body.error, code);
    assertEquals(body.message, "текст");
  }
});

Deno.test("v1-friends POST decline / remove — без push", async () => {
  for (const action of ["decline", "remove", "block"]) {
    const sent: Array<[string, PushMessage]> = [];
    const d = db({ "rpc.friend_action": { data: { ok: true, relation: "none", notify: null }, error: null } });
    await run(d, req("POST", URL, { action, user_id: PETRO }), { sent });
    assertEquals(sent.length, 0);
  }
});

Deno.test("v1-friends POST report: причина обов'язкова; з block — ще й блок", async () => {
  const bad = await run(db(), req("POST", URL, { action: "report", user_id: PETRO }));
  assertEquals(bad.status, 400);

  const d = db({
    "rpc.friend_relation": { data: "none", error: null },
    "rpc.friend_action": { data: { ok: true, relation: "blocked", notify: null }, error: null },
  });
  const res = await run(d, req("POST", URL, { action: "report", user_id: PETRO, reason: "spam", comment: "  реклама\n грибів ", block: true }));
  assertEquals(res.status, 200);
  const ins = d.calls.find((c) => c.key === "user_reports.insert")!;
  assertEquals((ins.args[0] as { comment: string }).comment, "реклама грибів");
  const act = d.calls.find((c) => c.key === "rpc.friend_action")!;
  assertEquals((act.args[0] as { p_action: string }).p_action, "block");
});

Deno.test("v1-friends PUT /push: реєстрація пристрою без зміни сповіщень про хвилі", async () => {
  const d = db();
  const res = await run(d, req("PUT", `${URL}/push`, { token: "x".repeat(40), platform: "android" }));
  assertEquals(res.status, 200);
  assertEquals(d.calls.some((c) => c.key === "rpc.register_push_device_social"), true);
});

Deno.test("actionsFor: друзі — видалити з підтвердженням; normalizeQuery", () => {
  const a = actionsFor("friends", "Петро");
  assertEquals(a[0].id, "remove");
  assertEquals(a[0].confirm_label?.includes("@Петро"), true);
  assertEquals(normalizeQuery("  @@Марʼяна'"), "марʼянаʼ");
});
