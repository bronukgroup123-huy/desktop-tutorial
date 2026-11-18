import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import {
  CURRENT_TERMS_VERSION,
  decideRegionChange,
  handleMe,
} from "../../functions/_shared/v1/me.ts";
import { type Call, mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

const NOW = new Date("2026-11-09T12:00:00Z");
const URL = "http://localhost/v1-me";
const hoursAgo = (h: number) => new Date(NOW.getTime() - h * 3600_000).toISOString();

function userRow(home_region_id: number | null) {
  return {
    id: "u1", name: "Олена Лісова", handle: "Олена_лісова", handle_changed_at: hoursAgo(24 * 40), avatar: null,
    rating: 0, total_verified_picks: 0, home_region_id, created_at: hoursAgo(100),
  };
}

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": { data: userRow(null), error: null },
    "regions.select": { data: { id: 10, slug: "kyivska", name: "Київська" }, error: null },
    "user_consents.select": { data: [], error: null },
    "region_change_log.select": { data: [], error: null },
    "rpc.find_region_by_slug": { data: [{ id: 10 }], error: null },
    ...extra,
  });
}

const run = (d: ReturnType<typeof mockDb>, r: Request, isAnonymous = false) =>
  handle((x) => handleMe(x, { db: d, verify: verifyAs("u1", isAnonymous), now: () => NOW }))(r);

const find = (d: ReturnType<typeof mockDb>, key: string): Call | undefined => d.calls.find((c) => c.key === key);

// ─── GET ───────────────────────────────────────────────────────────────────

Deno.test("v1-me GET: новий користувач → next_step = select_region", async () => {
  const res = await run(db(), req("GET", URL));
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.onboarding.next_step, "select_region");
  assertEquals(data.onboarding.region_done, false);
  assertEquals(data.is_guest, false);
});

Deno.test("v1-me GET: гість (ADR-001) → is_guest = true", async () => {
  const { data } = await (await run(db(), req("GET", URL), true)).json();
  assertEquals(data.is_guest, true);
});

Deno.test("v1-me GET: область є, згоди немає → accept_terms", async () => {
  const d = db({ "users.select": { data: userRow(10), error: null } });
  const { data } = await (await run(d, req("GET", URL))).json();
  assertEquals(data.home_region.slug, "kyivska");
  assertEquals(data.onboarding.next_step, "accept_terms");
  assertEquals(data.onboarding.terms_version, CURRENT_TERMS_VERSION);
});

Deno.test("v1-me GET: область і обидві згоди → done", async () => {
  const d = db({
    "users.select": { data: userRow(10), error: null },
    "user_consents.select": { data: [{ doc: "eula" }, { doc: "privacy" }], error: null },
  });
  const { data } = await (await run(d, req("GET", URL))).json();
  assertEquals(data.onboarding.next_step, "done");
});

Deno.test("v1-me GET: немає рядка users → 404 me_not_found", async () => {
  const res = await run(db({ "users.select": { data: null, error: null } }), req("GET", URL));
  assertEquals(res.status, 404);
});

// ─── PATCH: онбординг ──────────────────────────────────────────────────────

Deno.test("v1-me PATCH: перший вибір області → users.update + лог source=onboarding", async () => {
  const d = db();
  const res = await run(d, req("PATCH", URL, { home_region_slug: "kyivska" }));
  assertEquals(res.status, 200);
  assertEquals((find(d, "users.update")!.args[0] as Record<string, unknown>).home_region_id, 10);
  const log = find(d, "region_change_log.insert")!.args[0] as Record<string, unknown>;
  assertEquals(log.source, "onboarding");
  assertEquals(log.old_region_id, null);
});

Deno.test("v1-me PATCH: прийняття умов → дві згоди (eula + privacy)", async () => {
  const d = db();
  await run(d, req("PATCH", URL, { accept_terms_version: CURRENT_TERMS_VERSION }));
  const rows = find(d, "user_consents.upsert")!.args[0] as Array<Record<string, unknown>>;
  assertEquals(rows.map((r) => r.doc).sort(), ["eula", "privacy"]);
});

Deno.test("v1-me PATCH: застаріла версія умов → 409 terms_version_outdated", async () => {
  const res = await run(db(), req("PATCH", URL, { accept_terms_version: "2020-01" }));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error, "terms_version_outdated");
});

Deno.test("v1-me PATCH: порожнє тіло / невідомі поля → 400 invalid_body", async () => {
  assertEquals((await run(db(), req("PATCH", URL, {}))).status, 400);
  assertEquals((await run(db(), req("PATCH", URL, { foo: 1 }))).status, 400);
  assertEquals((await run(db(), req("PATCH", URL, [1]))).status, 400);
});

Deno.test("v1-me PATCH: невідомий slug → 404 region_not_found", async () => {
  const res = await run(db({ "rpc.find_region_by_slug": { data: [], error: null } }), req("PATCH", URL, { home_region_slug: "atlantis" }));
  assertEquals(res.status, 404);
});

// ─── PATCH: зміна області (ADR-016) ────────────────────────────────────────

Deno.test("v1-me PATCH: виправлення протягом 24 год → дозволено, source=onboarding_fix", async () => {
  const d = db({
    "users.select": { data: userRow(5), error: null },
    "region_change_log.select": { data: [{ source: "onboarding", changed_at: hoursAgo(2) }], error: null },
  });
  const res = await run(d, req("PATCH", URL, { home_region_slug: "kyivska" }));
  assertEquals(res.status, 200);
  assertEquals((find(d, "region_change_log.insert")!.args[0] as Record<string, unknown>).source, "onboarding_fix");
});

Deno.test("v1-me PATCH: після 24 год без Pro → 403 region_change_not_allowed, без запису", async () => {
  const d = db({
    "users.select": { data: userRow(5), error: null },
    "region_change_log.select": { data: [{ source: "onboarding", changed_at: hoursAgo(30) }], error: null },
  });
  const res = await run(d, req("PATCH", URL, { home_region_slug: "kyivska" }));
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, "region_change_not_allowed");
  assertEquals(find(d, "users.update"), undefined);
  assertEquals(find(d, "region_change_log.insert"), undefined);
});

Deno.test("v1-me PATCH: та сама область → без запису в лог", async () => {
  const d = db({ "users.select": { data: userRow(10), error: null } });
  const res = await run(d, req("PATCH", URL, { home_region_slug: "kyivska" }));
  assertEquals(res.status, 200);
  assertEquals(find(d, "region_change_log.insert"), undefined);
});

Deno.test("decideRegionChange: правила ADR-016", () => {
  const onb = (h: number) => ({ source: "onboarding" as const, changed_at: hoursAgo(h) });
  assertEquals(decideRegionChange([onb(1)], NOW, false).allowed, true);
  assertEquals(decideRegionChange([onb(1), { source: "onboarding_fix", changed_at: hoursAgo(0.5) }], NOW, false).allowed, false);
  assertEquals(decideRegionChange([onb(48)], NOW, false).allowed, false);
  const pro = decideRegionChange([onb(48)], NOW, true);
  assertEquals(pro.allowed && pro.source, "pro");
  assertEquals(decideRegionChange([onb(48), { source: "pro", changed_at: hoursAgo(1) }], NOW, true).allowed, false);
  assertEquals(decideRegionChange([], NOW, false).allowed, false); // legacy-користувач без логу
});

Deno.test("v1-me DELETE: видалити акаунт → delete_user_account свого id", async () => {
  const d = db();
  const res = await run(d, req("DELETE", URL));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).data, { deleted: true });
  assertEquals(find(d, "rpc.delete_user_account")?.args[0], { p_user_id: "u1" });
});

// ─── Профіль: ім'я, нік, аватар, рівень (ADR-021 §21.2.1) ───────────────────

const consented = { "user_consents.select": { data: [{ doc: "eula" }, { doc: "privacy" }], error: null } };

Deno.test("v1-me GET: після Google без ніка (ім'я з Google латиницею) → крок profile; гостю — ні", async () => {
  const fresh = { ...userRow(10), name: "Olena Lisova", handle: null, handle_changed_at: null };
  const d = db({ ...consented, "users.select": { data: fresh, error: null } });
  const { data } = await (await run(d, req("GET", URL))).json();
  assertEquals(data.onboarding.next_step, "profile");
  assertEquals(data.name, null); // латиницю не показуємо — людина введе ім'я українською
  assertEquals(data.avatar.kind, "standard");
  assertEquals(data.level.label, "Мандрівник");
  const guest = await (await run(db({ ...consented, "users.select": { data: fresh, error: null } }), req("GET", URL), true)).json();
  assertEquals(guest.data.onboarding.next_step, "done");
  assertEquals(guest.data.handle, null);
});

Deno.test("v1-me PATCH: ім'я й нік → users.update з ключем унікальності; апостроф зведено", async () => {
  const d = db({ "users.select": { data: { ...userRow(10), handle: null, handle_changed_at: null }, error: null } });
  const res = await run(d, req("PATCH", URL, { name: "  Мар'яна   Лісова ", handle: "@Мар’яна_Лісова" }));
  assertEquals(res.status, 200);
  const patch = find(d, "users.update")?.args[0] as Record<string, unknown>;
  assertEquals(patch.name, "Марʼяна Лісова");
  assertEquals(patch.handle, "Марʼяна_Лісова");
  assertEquals(patch.handle_key, "марʼяна_лісова");
  assertEquals(patch.handle_changed_at, NOW.toISOString());
});

Deno.test("v1-me PATCH: нік латиницею / з ы / нецензурний / ім'я латиницею → 400", async () => {
  for (const [body, code] of [
    [{ handle: "olena" }, "invalid_handle"],
    [{ handle: "Олeна" }, "invalid_handle"], // латинська «e»
    [{ handle: "мыло_123" }, "invalid_handle"],
    [{ handle: "1олена" }, "invalid_handle"],
    [{ handle: "ол" }, "invalid_handle"],
    [{ handle: "хуйло" }, "handle_not_allowed"],
    [{ handle: "адмін" }, "handle_not_allowed"],
    [{ name: "Olena" }, "invalid_name"],
    [{ name: "Ж" }, "invalid_name"],
    [{ avatar: { kind: "standard", id: 21 } }, "invalid_avatar"],
  ] as const) {
    const res = await run(db(), req("PATCH", URL, body));
    assertEquals([res.status, (await res.json()).error], [400, code], JSON.stringify(body));
  }
});

Deno.test("v1-me PATCH: гість не має імені, ніка й аватара → 403 registration_required", async () => {
  const res = await run(db(), req("PATCH", URL, { handle: "грибник" }), true);
  assertEquals([res.status, (await res.json()).error], [403, "registration_required"]);
});

Deno.test("v1-me PATCH: зайнятий нік → 409 handle_taken; змінити нік раніше 30 днів → 409", async () => {
  const taken = db({ "users.update": { data: null, error: { code: "23505" } } });
  const res = await run(taken, req("PATCH", URL, { handle: "Петро" }));
  assertEquals([res.status, (await res.json()).error], [409, "handle_taken"]);
  const recent = db({ "users.select": { data: { ...userRow(10), handle_changed_at: hoursAgo(24 * 5) }, error: null } });
  const soon = await run(recent, req("PATCH", URL, { handle: "Петро" }));
  const body = await soon.json();
  assertEquals([soon.status, body.error], [409, "handle_change_too_soon"]);
  // Той самий нік іншими великими літерами — не зміна, обмеження не діє.
  const same = db({ "users.select": { data: { ...userRow(10), handle_changed_at: hoursAgo(24 * 5) }, error: null } });
  assertEquals((await run(same, req("PATCH", URL, { handle: "ОЛЕНА_ЛІСОВА" }))).status, 200);
});

Deno.test("v1-me GET ?check_handle: вільний / зайнятий / некоректний", async () => {
  const free = await (await run(db({ "users.select": { data: [], error: null } }), req("GET", `${URL}?check_handle=грибник`))).json();
  assertEquals(free.data, { handle: "грибник", available: true, reason: null });
  const busy = await (await run(db({ "users.select": { data: [{ id: "u2" }], error: null } }), req("GET", `${URL}?check_handle=грибник`))).json();
  assertEquals([busy.data.available, busy.data.reason], [false, "Нік @грибник уже зайнятий"]);
  const bad = await (await run(db(), req("GET", `${URL}?check_handle=gribnyk`))).json();
  assertEquals([bad.data.available, bad.data.reason], [false, "Нік — лише українськими літерами, без латиниці"]);
});
