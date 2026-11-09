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
  return { id: "u1", name: "Гриб", rating: 0, total_verified_picks: 0, home_region_id, created_at: hoursAgo(100) };
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

Deno.test("v1-me: DELETE → 405", async () => {
  assertEquals((await run(db(), req("DELETE", URL))).status, 405);
});
