import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import { handleFriends, inviteUrl, PLAY_PACKAGE } from "../../functions/_shared/v1/friends.ts";
import { handleMe } from "../../functions/_shared/v1/me.ts";
import { type Call, mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

// B9.5a: запрошення (ADR-021 §21.4). Правила — у SQL (my_referral_code / redeem_referral); тут — маршрути й тексти.
const ME = "11111111-1111-4111-8111-111111111111";
const NOW = new Date("2026-11-28T10:00:00Z");
const find = (d: ReturnType<typeof mockDb>, key: string): Call | undefined => d.calls.find((c) => c.key === key);

function friendsDb(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": { data: { id: ME, handle: "Олена_лісова" }, error: null },
    "rpc.my_referral_code": { data: { ok: true, code: "K7M2Q9PX", invited: 2, rewarded: 1, bonuses_left: 4 }, error: null },
    ...extra,
  });
}
const runFriends = (d: ReturnType<typeof mockDb>, r: Request, anon = false) =>
  handle((x) => handleFriends(x, { db: d, verify: verifyAs(ME, anon), now: () => NOW, send: () => Promise.resolve({ ok: true, unregistered: false }) }))(r);

Deno.test("invite: мій код — посилання лише в Google Play з ref=КОД, підсумок і підпис", async () => {
  const d = friendsDb();
  const res = await runFriends(d, req("GET", "http://localhost/v1-friends/invite"));
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.code, "K7M2Q9PX");
  assertEquals(data.share_url, `https://play.google.com/store/apps/details?id=${PLAY_PACKAGE}&referrer=ref%3DK7M2Q9PX`);
  assert(data.share_text.includes(data.share_url));
  assertEquals([data.invited, data.rewarded, data.bonuses_left], [2, 1, 4]);
  assert(data.label.includes("4 з 5"));
  assertEquals(find(d, "rpc.my_referral_code")!.args[0], { p_user_id: ME });
});

Deno.test("invite: бонуси вичерпано — інший підпис; гість — 403", async () => {
  const d = friendsDb({ "rpc.my_referral_code": { data: { ok: true, code: "K7M2Q9PX", invited: 7, rewarded: 5, bonuses_left: 0 }, error: null } });
  const { data } = await (await runFriends(d, req("GET", "http://localhost/v1-friends/invite"))).json();
  assert(data.label.startsWith("Бонуси за запрошення вже отримано"));
  assertEquals((await runFriends(friendsDb(), req("GET", "http://localhost/v1-friends/invite"), true)).status, 403);
});

Deno.test("inviteUrl: без вебсторінок — лише play.google.com", () => {
  assert(inviteUrl("ABCDEFGH").startsWith("https://play.google.com/store/apps/details?id="));
});

// ─── v1-me PATCH referral_code ─────────────────────────────────────────────
function meDb(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": {
      data: { id: ME, name: null, handle: null, handle_changed_at: null, avatar: null, rating: 0, total_verified_picks: 0, home_region_id: null, created_at: NOW.toISOString() },
      error: null,
    },
    "user_consents.select": { data: [], error: null },
    "region_change_log.select": { data: [], error: null },
    "rpc.can_create_pick": { data: [{ allowed: true, code: null, message: null }], error: null },
    "rpc.redeem_referral": { data: { ok: true, inviter_handle: "Петро", friends_now: false }, error: null },
    ...extra,
  });
}
const runMe = (d: ReturnType<typeof mockDb>, r: Request, anon = false) =>
  handle((x) => handleMe(x, { db: d, verify: verifyAs(ME, anon), now: () => NOW }))(r);

Deno.test("me PATCH referral_code: гість — прийнято, підказка увійти; код великими літерами", async () => {
  const d = meDb();
  const res = await runMe(d, req("PATCH", "http://localhost/v1-me", { referral_code: " k7m2q9px " }), true);
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.referral.applied, true);
  assert(data.referral.label.includes("@Петро") && data.referral.label.includes("Увійдіть"));
  assertEquals(find(d, "rpc.redeem_referral")!.args[0], { p_invitee_id: ME, p_code: "K7M2Q9PX" });
});

Deno.test("me PATCH referral_code: акаунт — «ви друзі»; відмова SQL — 200 з текстом, онбординг не зривається", async () => {
  let { data } = await (await runMe(meDb(), req("PATCH", "http://localhost/v1-me", { referral_code: "K7M2Q9PX" }))).json();
  assert(data.referral.label.includes("ви друзі"));
  const d = meDb({ "rpc.redeem_referral": { data: { ok: false, code: "too_late", message: "Код запрошення діє лише в перші 14 днів" }, error: null } });
  const res = await runMe(d, req("PATCH", "http://localhost/v1-me", { referral_code: "K7M2Q9PX" }));
  assertEquals(res.status, 200);
  data = (await res.json()).data;
  assertEquals(data.referral, { applied: false, label: "Код запрошення діє лише в перші 14 днів" });
  // помилка БД теж не зриває запит
  const e = meDb({ "rpc.redeem_referral": { data: null, error: { message: "boom" } } });
  assertEquals((await runMe(e, req("PATCH", "http://localhost/v1-me", { referral_code: "K7M2Q9PX" }))).status, 200);
});

Deno.test("me PATCH referral_code: кривий код — 400 без запиту в БД; без коду — поля referral немає", async () => {
  for (const bad of ["ab", "КИРИЛИЦЯ", "TOO-LONG-CODE-123", 42]) {
    const d = meDb();
    assertEquals((await runMe(d, req("PATCH", "http://localhost/v1-me", { referral_code: bad }))).status, 400, String(bad));
    assertEquals(find(d, "rpc.redeem_referral"), undefined);
  }
  const d = meDb({ "rpc.find_region_by_slug": { data: [{ id: 10 }], error: null }, "regions.select": { data: { id: 10, slug: "kyivska", name: "Київська" }, error: null } });
  const { data } = await (await runMe(d, req("PATCH", "http://localhost/v1-me", { home_region_slug: "kyivska" }))).json();
  assertEquals("referral" in data, false);
});
