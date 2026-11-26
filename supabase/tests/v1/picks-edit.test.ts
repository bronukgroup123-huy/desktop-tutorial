// B3.4: PATCH / DELETE v1-picks/{id} — зміна й видалення своєї точки.
import { assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { handlePicks, type PicksStorage, validateUpdateBody } from "../../functions/_shared/v1/picks.ts";
import { fuzzPoint } from "../../functions/_shared/picks/fuzz.ts";
import { mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const PICK = "99999999-9999-4999-8999-999999999999";
const URL_ = `http://localhost/v1-picks/${PICK}`;
const EXACT = { lat: 50.4501, lng: 30.5234 };

const never = () => Promise.reject(new Error("storage не використовується"));
const storage: PicksStorage = { createSignedUploadUrl: never, download: never, upload: never, remove: never, createSignedUrl: never };

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": { data: { home_region_id: 10 }, error: null },
    "rpc.get_pick_card": { data: { is_mine: true, lat: EXACT.lat, lng: EXACT.lng }, error: null },
    "rpc.update_pick": {
      data: { ok: true, pick: { id: PICK, pick_type: "public", verification_status: "pending", description: "біля струмка" } },
      error: null,
    },
    "rpc.delete_pick": { data: true, error: null },
    ...extra,
  });
}

async function run(d: ReturnType<typeof mockDb>, r: Request, isAnonymous = false) {
  const res = await handle((x) => handlePicks(x, { db: d, storage, verify: verifyAs(USER, isAnonymous), fuzzSecret: "s" }))(r);
  return { res, json: await res.json() };
}
const args = (d: ReturnType<typeof mockDb>, key: string) => d.calls.find((c) => c.key === key)?.args[0] as Record<string, unknown>;

Deno.test("PATCH: публікація — зсунуте місце рахує сервер із точних координат; опис очищено від контактів", async () => {
  const d = db();
  const { res, json } = await run(d, req("PATCH", URL_, { visibility: "public", description: "біля струмка, тел. 0671234567" }));
  assertEquals(res.status, 200);
  assertEquals(json.data.visibility, "public");
  assertEquals(json.data.description, "біля струмка");
  const a = args(d, "rpc.update_pick");
  const fuzzed = await fuzzPoint(PICK, EXACT.lat, EXACT.lng, "s");
  assertEquals([a.p_display_lat, a.p_display_lng], [fuzzed.lat, fuzzed.lng]);
  assertEquals(a.p_visibility, "public");
  assertEquals(a.p_set_description, true);
  assertEquals(String(a.p_description).includes("0671234567"), false);
});

Deno.test("PATCH: лише опис — без зсуву й без запиту картки; null прибирає опис", async () => {
  const d = db({ "rpc.update_pick": { data: { ok: true, pick: { id: PICK, pick_type: "private", verification_status: "pending", description: null } }, error: null } });
  const { res, json } = await run(d, req("PATCH", URL_, { description: null }));
  assertEquals(res.status, 200);
  assertEquals(json.data.description, null);
  assertEquals(d.calls.some((c) => c.key === "rpc.get_pick_card"), false);
  const a = args(d, "rpc.update_pick");
  assertEquals([a.p_visibility, a.p_set_description, a.p_description, a.p_display_lat], [null, true, null, null]);
});

Deno.test("PATCH: чужа точка (картка не моя) — 404 без зміни", async () => {
  const d = db({ "rpc.get_pick_card": { data: { is_mine: false, lat: 1, lng: 2 }, error: null } });
  const { res, json } = await run(d, req("PATCH", URL_, { visibility: "public" }));
  assertEquals(res.status, 404);
  assertEquals(json.error, "pick_not_found");
  assertEquals(d.calls.some((c) => c.key === "rpc.update_pick"), false);
});

Deno.test("PATCH: відмови БД — коди й статуси (вид, рівень, ліміти, не знайдено)", async () => {
  for (const [code, status] of [["species_required", 422], ["level_required", 403], ["weekly_limit_reached", 429], ["private_limit_reached", 429], ["pick_not_found", 404]] as const) {
    const d = db({ "rpc.update_pick": { data: { ok: false, code, message: "текст сервера" }, error: null } });
    const { res, json } = await run(d, req("PATCH", URL_, { visibility: "private" }));
    assertEquals([res.status, json.error], [status, code], code);
  }
});

Deno.test("PATCH: гість не публікує; фото й вид не змінюються; порожнє тіло — 422", async () => {
  assertEquals((await run(db(), req("PATCH", URL_, { visibility: "public" }), true)).res.status, 403);
  for (const body of [{ species_id: "boletus_edulis" }, { photo: "x" }, {}, { visibility: "friends" }]) {
    const d = db();
    const { res } = await run(d, req("PATCH", URL_, body));
    assertEquals(res.status, 422, JSON.stringify(body));
    assertEquals(d.calls.some((c) => c.key === "rpc.update_pick"), false);
  }
  // гість може змінити опис своєї приватної точки
  assertEquals((await run(db(), req("PATCH", URL_, { description: "ок" }), true)).res.status, 200);
});

Deno.test("DELETE: своя — 200; чужа, видалена чи неіснуюча — 404", async () => {
  const d = db();
  const { res, json } = await run(d, req("DELETE", URL_));
  assertEquals([res.status, json.data.deleted], [200, true]);
  assertEquals(args(d, "rpc.delete_pick"), { p_user_id: USER, p_pick_id: PICK });
  const miss = await run(db({ "rpc.delete_pick": { data: false, error: null } }), req("DELETE", URL_));
  assertEquals([miss.res.status, miss.json.error], [404, "pick_not_found"]);
});

Deno.test("validateUpdateBody: лише visibility і description", () => {
  assertEquals(validateUpdateBody({ visibility: "private" }), { visibility: "private", description: undefined });
  assertEquals(validateUpdateBody({ description: "  " }).description, null);
});
