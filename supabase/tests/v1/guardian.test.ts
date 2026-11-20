import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import {
  guardianMessage,
  handleGuardian,
  handleGuardianTick,
  handleTelegramWebhook,
  type HikeRow,
  type PushMessage,
  validatePoints,
} from "../../functions/_shared/v1/guardian.ts";
import { type Call, mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

const URL = "http://localhost/v1-guardian";
const OLENA = "11111111-1111-4111-8111-111111111111";
const PETRO = "22222222-2222-4222-8222-222222222222";
const IRA = "33333333-3333-4333-8333-333333333333";
const HIKE = "99999999-9999-4999-8999-999999999999";
const NOW = new Date("2026-11-20T10:00:00Z");

const users: Record<string, { id: string; handle: string; name: string; avatar: null }> = {
  [OLENA]: { id: OLENA, handle: "Олена_лісова", name: "Олена", avatar: null },
  [PETRO]: { id: PETRO, handle: "Петро", name: "Петро", avatar: null },
  [IRA]: { id: IRA, handle: "Ірина", name: "Ірина", avatar: null },
};

function hike(over: Partial<HikeRow> = {}): HikeRow {
  return {
    id: HIKE, owner_id: OLENA, client_id: "c1", status: "active",
    route: [{ lat: 50.4, lng: 28.6, label: "Машина" }],
    started_at: "2026-11-20T07:00:00Z", expected_return: "2026-11-20T14:00:00Z",
    last_lat: 50.41234, last_lng: 28.61234, last_accuracy: 12, last_at: "2026-11-20T09:55:00Z",
    last_signal_at: "2026-11-20T09:56:00Z", battery: 64, gps_issue_at: null,
    check_sent_at: null, alert_sent_at: null, sos_at: null, closed_at: null, ...over,
  };
}

const filter = (c: Call, k: string) => c.filters.find(([f]) => f === k)?.[1];

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": (c) => {
      const id = filter(c, "id");
      if (Array.isArray(id)) return { data: id.map((x) => users[x as string]).filter(Boolean), error: null };
      return { data: users[id as string] ?? null, error: null };
    },
    "rpc.push_tokens_of": (c) => ({ data: [`tok-${(c.args[0] as { p_user: string }).p_user.slice(0, 4)}`], error: null }),
    ...extra,
  });
}

type Sent = Array<{ token: string; msg: PushMessage; urgent: boolean }>;

function run(d: ReturnType<typeof mockDb>, r: Request, as = OLENA, opts: { anon?: boolean; sent?: Sent; tg?: string[]; pro?: boolean } = {}) {
  return handle((x) =>
    handleGuardian(x, {
      db: d,
      verify: verifyAs(as, opts.anon ?? false),
      now: () => NOW,
      send: (token, msg, urgent) => {
        opts.sent?.push({ token, msg, urgent });
        return Promise.resolve({ ok: true });
      },
      telegram: (_chat, text) => {
        opts.tg?.push(text);
        return Promise.resolve(true);
      },
      telegramBot: "GrybRadarBot",
      hasGuardians3: () => Promise.resolve(opts.pro ?? false),
      randomCode: () => "CODE_abcdefghijklmnop",
    })
  )(r);
}

const COORDS = /\d{2}\.\d{3,}/;

Deno.test("v1-guardian: гість → 403 registration_required (ADR-001, B4.7)", async () => {
  const res = await run(db(), req("GET", URL), OLENA, { anon: true });
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, "registration_required");
});

Deno.test("v1-guardian invite: лише друга; другу — прохання push", async () => {
  const notFriend = await run(db({ "rpc.are_friends": { data: false, error: null } }), req("POST", URL, { action: "invite", user_id: PETRO }));
  assertEquals(notFriend.status, 403);
  assertEquals((await notFriend.json()).error, "not_friends");

  const sent: Sent = [];
  const d = db({ "rpc.are_friends": { data: true, error: null }, "guardian_links.select": { data: [], error: null } });
  const res = await run(d, req("POST", URL, { action: "invite", user_id: PETRO }), OLENA, { sent });
  assertEquals(res.status, 200);
  assertEquals((await res.json()).data.status, "pending");
  const ins = d.calls.find((c) => c.key === "guardian_links.insert")!;
  assertEquals((ins.args[0] as { status: string }).status, "pending");
  assertEquals(sent[0].msg.body, "@Олена_лісова просить вас бути Наглядачем у поході");
});

Deno.test("v1-guardian start: маршрут обов'язковий, Наглядач — обов'язково, 2 без Pro → pro_required", async () => {
  const base = { action: "start", expected_return: "2026-11-20T15:00:00Z", client_id: "c1" };
  const noRoute = await run(db(), req("POST", URL, { ...base, route: [], guardian_ids: [PETRO] }));
  assertEquals((await noRoute.json()).error, "route_required");
  const noGuard = await run(db(), req("POST", URL, { ...base, route: [{ lat: 50.4, lng: 28.6 }], guardian_ids: [] }));
  assertEquals((await noGuard.json()).error, "guardian_required");
  const two = await run(db(), req("POST", URL, { ...base, route: [{ lat: 50.4, lng: 28.6 }], guardian_ids: [PETRO, IRA] }));
  assertEquals(two.status, 403);
  assertEquals((await two.json()).error, "pro_required");
  const tooSoon = await run(db(), req("POST", URL, { ...base, expected_return: "2026-11-20T10:05:00Z", route: [{ lat: 50.4, lng: 28.6 }], guardian_ids: [PETRO] }));
  assertEquals(tooSoon.status, 422);
});

Deno.test("v1-guardian start: Наглядач не погодився → 403; погодився → похід і push без координат", async () => {
  const body = { action: "start", expected_return: "2026-11-20T15:00:00Z", client_id: "c1", route: [{ lat: 50.4, lng: 28.6, label: "Машина" }], guardian_ids: [PETRO] };
  const pending = db({ "hikes.select": { data: null, error: null }, "guardian_links.select": { data: [{ guardian_id: PETRO, status: "pending" }], error: null } });
  const r1 = await run(pending, req("POST", URL, body));
  assertEquals((await r1.json()).error, "guardian_not_accepted");

  const sent: Sent = [];
  const tg: string[] = [];
  const d = db({
    "hikes.select": { data: null, error: null },
    "guardian_links.select": { data: [{ guardian_id: PETRO, status: "accepted" }], error: null },
    "hikes.insert": { data: hike({ expected_return: "2026-11-20T15:00:00Z" }), error: null },
    "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null },
    "guardian_telegram.select": { data: [{ user_id: PETRO, chat_id: 777 }], error: null },
  });
  const res = await run(d, req("POST", URL, body), OLENA, { sent, tg });
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.hike.status, "active");
  assertEquals(data.hike.expected_return_label, "17:00");
  assertEquals(data.hike.guardians[0].handle, "Петро");
  assertEquals(data.hike.actions.map((a: { id: string }) => a.id), ["extend", "finish"]);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].token, "tok-2222");
  assert(!COORDS.test(sent[0].msg.body), sent[0].msg.body);
  assert(!COORDS.test(tg[0]), tg[0]);
  const hg = d.calls.find((c) => c.key === "hike_guardians.insert")!;
  assertEquals(hg.args[0], [{ hike_id: HIKE, guardian_id: PETRO }]);
});

Deno.test("v1-guardian track: точка з поганою точністю — у трек з позначкою, але не «останнє місце»", async () => {
  const d = db({ "hikes.select": { data: hike(), error: null }, "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null } });
  const res = await run(d, req("POST", URL, {
    action: "track", hike_id: HIKE, battery: 41,
    points: [
      { lat: 50.42, lng: 28.62, t: "2026-11-20T09:58:00Z", acc: 9 },
      { lat: 50.9, lng: 28.9, t: "2026-11-20T09:59:00Z", acc: 450 },
      { lat: 50.1, lng: 28.1, t: "2026-11-20T06:00:00Z", acc: 5 }, // до старту — відкинуто
    ],
  }));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).data.accepted, 2);
  const up = d.calls.find((c) => c.key === "hike_points.upsert")!;
  const rows = up.args[0] as Array<{ low_accuracy: boolean }>;
  assertEquals(rows.map((r) => r.low_accuracy), [false, true]);
  const patch = d.calls.find((c) => c.key === "hikes.update")!.args[0] as Record<string, unknown>;
  assertEquals(patch.last_lat, 50.42);
  assertEquals(patch.battery, 41);
  assertEquals(typeof patch.gps_issue_at, "string");
});

Deno.test("v1-guardian track: чужий похід → 404", async () => {
  const d = db({ "hikes.select": { data: hike({ owner_id: IRA }), error: null } });
  const res = await run(d, req("POST", URL, { action: "track", hike_id: HIKE, points: [] }));
  assertEquals(res.status, 404);
});

Deno.test("v1-guardian ?hike: Наглядач бачить трек і текст для 112; чужий і після закриття — 404 (B4.9)", async () => {
  const d = db({
    "hikes.select": { data: hike(), error: null },
    "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null },
    "hike_points.select": { data: [{ lat: 50.41, lng: 28.61, accuracy: 10, low_accuracy: false, recorded_at: "2026-11-20T09:00:00Z" }], error: null },
  });
  const res = await run(d, req("GET", `${URL}?hike=${HIKE}`), PETRO);
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.hike.track.length, 1);
  assertEquals(data.hike.route[0].label, "Машина");
  assertEquals(data.hike.rescue.coords_label, "50.41234, 28.61234");
  assert(data.hike.rescue.sms_text.includes("50.41234, 28.61234"));
  assert(!data.hike.rescue.sms_text.includes("http"));
  assertEquals(data.hike.battery_label, "Батарея 64 %");

  const stranger = await run(d, req("GET", `${URL}?hike=${HIKE}`), IRA);
  assertEquals(stranger.status, 404);

  const closed = db({ "hikes.select": { data: hike({ status: "closed", closed_at: NOW.toISOString() }), error: null }, "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null } });
  assertEquals((await run(closed, req("GET", `${URL}?hike=${HIKE}`), PETRO)).status, 404);
});

Deno.test("v1-guardian sos: тривога Наглядачам одразу, термінова, без координат", async () => {
  const sent: Sent = [];
  const tg: string[] = [];
  const d = db({
    "hikes.select": { data: hike(), error: null },
    "hikes.update": { data: hike({ status: "sos", sos_at: NOW.toISOString() }), error: null },
    "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null },
    "guardian_telegram.select": { data: [{ user_id: PETRO, chat_id: 777 }], error: null },
  });
  const res = await run(d, req("POST", URL, { action: "sos", hike_id: HIKE }), OLENA, { sent, tg });
  assertEquals(res.status, 200);
  assertEquals((await res.json()).data.hike.actions[0].id, "sos_cancel");
  assertEquals(sent[0].urgent, true);
  assertEquals(sent[0].msg.body, "@Олена_лісова — SOS. Відкрийте застосунок");
  assertEquals(tg[0], "🔴 SOS\n@Олена_лісова — SOS. Відкрийте застосунок");
});

Deno.test("v1-guardian «Так, все добре» під час тривоги — Наглядачам «все добре»; finish — «вдома»", async () => {
  const sent: Sent = [];
  const d = db({
    "hikes.select": { data: hike({ status: "alert", check_sent_at: "2026-11-20T09:40:00Z" }), error: null },
    "hikes.update": { data: hike({ status: "active", expected_return: "2026-11-20T10:30:00Z" }), error: null },
    "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null },
  });
  const res = await run(d, req("POST", URL, { action: "ok", hike_id: HIKE }), OLENA, { sent });
  assertEquals(res.status, 200);
  const patch = d.calls.find((c) => c.key === "hikes.update")!.args[0] as Record<string, unknown>;
  assertEquals(patch.status, "active");
  assertEquals(sent[0].msg.body, "@Олена_лісова відповідає: все добре");

  const sent2: Sent = [];
  const d2 = db({
    "hikes.select": { data: hike(), error: null },
    "hikes.update": { data: hike({ status: "closed", closed_at: NOW.toISOString() }), error: null },
    "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null },
  });
  const fin = await (await run(d2, req("POST", URL, { action: "finish", hike_id: HIKE }), OLENA, { sent: sent2 })).json();
  assertEquals(fin.data.hike, null);
  assertEquals(sent2[0].msg.body, "@Олена_лісова вдома. Похід завершено");
});

Deno.test("v1-guardian GET: Наглядач бачить картку грибника; тривожні — згори", async () => {
  const d = db({
    "guardian_links.select": (c) => filter(c, "owner_id") === PETRO
      ? { data: [], error: null }
      : { data: [{ owner_id: OLENA, status: "accepted" }, { owner_id: IRA, status: "pending" }], error: null },
    "hike_guardians.select": { data: [{ hike_id: HIKE }, { hike_id: "88888888-8888-4888-8888-888888888888" }], error: null },
    "hikes.select": (c) => filter(c, "owner_id") === PETRO
      ? { data: null, error: null }
      : { data: [hike(), hike({ id: "88888888-8888-4888-8888-888888888888", owner_id: IRA, status: "sos" })], error: null },
    "guardian_telegram.select": { data: null, error: null },
  });
  const { data } = await (await run(d, req("GET", URL), PETRO)).json();
  assertEquals(data.watched.length, 2);
  assertEquals(data.watched[0].status, "sos");
  assertEquals(data.watched[0].alarm, true);
  assertEquals(data.watched[1].last_signal_label, "Останній сигнал 4 хв тому");
  assertEquals(data.invites.length, 1);
  assertEquals(data.invites[0].actions[0].id, "accept_invite");
  assertEquals(data.watching[0].handle, "Олена_лісова");
  assertEquals(data.limits.max_guardians_per_hike, 1);
  assertEquals(data.telegram, { available: true, linked: false });
});

Deno.test("v1-guardian-tick: лише service_role; «Все добре?» грибнику, тривога — Наглядачам", async () => {
  const unauth = await handle((x) => handleGuardianTick(x, { db: db(), serviceKey: "svc" }))(req("POST", "http://x/v1-guardian-tick", {}));
  assertEquals(unauth.status, 401);

  const sent: Sent = [];
  const tg: string[] = [];
  const d = db({
    "rpc.hike_tick": { data: [{ hike_id: HIKE, kind: "check", owner_id: OLENA }, { hike_id: HIKE, kind: "alert", owner_id: OLENA }], error: null },
    "hikes.select": { data: hike({ status: "alert" }), error: null },
    "hike_guardians.select": { data: [{ guardian_id: PETRO }], error: null },
    "guardian_telegram.select": { data: [{ user_id: PETRO, chat_id: 777 }], error: null },
  });
  const res = await handle((x) =>
    handleGuardianTick(x, {
      db: d, serviceKey: "svc", now: () => NOW,
      send: (token, msg, urgent) => { sent.push({ token, msg, urgent }); return Promise.resolve({ ok: true }); },
      telegram: (_c, t) => { tg.push(t); return Promise.resolve(true); },
    })
  )(req("POST", "http://x/v1-guardian-tick", {}, { Authorization: "Bearer svc" }));
  assertEquals(res.status, 200);
  assertEquals(sent.map((s) => [s.token, s.msg.data.type]), [
    ["tok-1111", "hike_check"],
    ["tok-2222", "hike_alert"],
    ["tok-1111", "hike_alert_owner"],
  ]);
  assertEquals(tg.length, 1);
  assert(!COORDS.test(tg[0]));
});

Deno.test("v1-guardian telegram_link → посилання на бота з кодом; webhook прив'язує чат лише з секретом", async () => {
  const d = db();
  const { data } = await (await run(d, req("POST", URL, { action: "telegram_link" }))).json();
  assertEquals(data.url, "https://t.me/GrybRadarBot?start=CODE_abcdefghijklmnop");
  const saved = d.calls.find((c) => c.key === "telegram_link_codes.insert")!.args[0] as { code_hash: string };
  assert(!saved.code_hash.includes("CODE")); // зберігається лише хеш

  const replies: string[] = [];
  const hook = (database: ReturnType<typeof mockDb>, secret: string) =>
    handle((x) => handleTelegramWebhook(x, { db: database, secret: "s3", now: () => NOW, telegram: (_c, t) => { replies.push(t); return Promise.resolve(true); } }))(
      req("POST", "http://x/v1-telegram-webhook", { message: { chat: { id: 777, type: "private" }, text: "/start CODE_abcdefghijklmnop" } }, { "X-Telegram-Bot-Api-Secret-Token": secret }),
    );
  assertEquals((await hook(db(), "wrong")).status, 401);

  const d2 = db({ "telegram_link_codes.select": { data: { user_id: PETRO, expires_at: "2026-11-20T10:10:00Z" }, error: null } });
  const ok = await (await hook(d2, "s3")).json();
  assertEquals(ok.data.linked, true);
  const up = d2.calls.find((c) => c.key === "guardian_telegram.upsert")!.args[0] as { user_id: string; chat_id: number };
  assertEquals([up.user_id, up.chat_id], [PETRO, 777]);

  const d3 = db({ "telegram_link_codes.select": { data: { user_id: PETRO, expires_at: "2026-11-20T09:00:00Z" }, error: null } });
  assertEquals((await (await hook(d3, "s3")).json()).data.linked, false);
});

Deno.test("guardianMessage: жодних координат у текстах Наглядачу; validatePoints сортує й відкидає майбутнє", () => {
  for (const ev of ["start", "alert", "sos", "sos_cancel", "ok", "extend", "finish", "autoclose"] as const) {
    const m = guardianMessage(ev, "@Олена", "2026-11-20T14:00:00Z");
    assert(!COORDS.test(m.body), m.body);
  }
  const pts = validatePoints([
    { lat: 1, lng: 1, t: "2026-11-20T09:50:00Z", acc: 5 },
    { lat: 2, lng: 2, t: "2026-11-20T09:40:00Z" },
    { lat: 3, lng: 3, t: "2026-11-20T11:00:00Z" },
  ], new Date("2026-11-20T09:00:00Z"), NOW);
  assertEquals(pts.map((p) => p.lat), [2, 1]);
});
