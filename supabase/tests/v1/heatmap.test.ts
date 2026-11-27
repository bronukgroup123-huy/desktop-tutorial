import { assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { handleHeatmap, LEGEND_LABEL, parseHeatmapQuery } from "../../functions/_shared/v1/heatmap.ts";
import { type Call, mockDb, req, type Results, RL_BLOCKED, RL_OK, verifyAs } from "./mock-db.ts";

// B3.5a: теплова карта (ADR-010). Доступ вирішує SQL heatmap_cells — тут розбір запиту, Pro й відповіді.
const USER = "11111111-1111-4111-8111-111111111111";
const URL_ = "http://localhost/v1-heatmap";

const okData = {
  ok: true,
  cells: [{ lat: 50.4545, lng: 30.527, level: 2 }],
  cell_lat: 0.009,
  cell_lng: 0.014,
  period_days: 3,
  scope: "home",
  can_change_period: false,
};

function db(extra: Results = {}) {
  return mockDb({ ...RL_OK, "rpc.heatmap_cells": { data: okData, error: null }, ...extra });
}

async function run(d: ReturnType<typeof mockDb>, r: Request, opts: { anon?: boolean; pro?: boolean } = {}) {
  const res = await handle((x) =>
    handleHeatmap(x, { db: d, verify: verifyAs(USER, opts.anon ?? false), hasPro: () => Promise.resolve(opts.pro ?? false) })
  )(r);
  return { res, json: await res.json() };
}
const find = (d: ReturnType<typeof mockDb>, key: string): Call | undefined => d.calls.find((c) => c.key === key);

Deno.test("heatmap: 200 — клітинки рівнями, підписи; за замовчуванням 3 дні без bbox, без Pro", async () => {
  const d = db();
  const { res, json } = await run(d, req("GET", URL_));
  assertEquals(res.status, 200);
  assertEquals(json.data.cells, okData.cells);
  assertEquals(json.data.scope_label, "Ваша область");
  assertEquals(json.data.legend_label, LEGEND_LABEL);
  assertEquals("ok" in json.data, false);
  assertEquals(find(d, "rpc.heatmap_cells")!.args[0], {
    p_user_id: USER, p_period_days: 3, p_pro: false,
    p_min_lng: null, p_min_lat: null, p_max_lng: null, p_max_lat: null,
  });
});

Deno.test("heatmap: період і bbox ідуть у SQL; Pro передається", async () => {
  const d = db();
  await run(d, req("GET", `${URL_}?period=30d&bbox=30,50,31,51`), { pro: true });
  assertEquals(find(d, "rpc.heatmap_cells")!.args[0], {
    p_user_id: USER, p_period_days: 30, p_pro: true,
    p_min_lng: 30, p_min_lat: 50, p_max_lng: 31, p_max_lat: 51,
  });
});

Deno.test("heatmap: відмови SQL — 403 level_required / pro_required, 409 без області, з текстом", async () => {
  for (const [code, status] of [["level_required", 403], ["pro_required", 403], ["home_region_required", 409]] as const) {
    const d = db({ "rpc.heatmap_cells": { data: { ok: false, code, message: "Текст" }, error: null } });
    const { res, json } = await run(d, req("GET", URL_));
    assertEquals(res.status, status, code);
    assertEquals([json.error, json.message], [code, "Текст"]);
  }
});

Deno.test("heatmap: кривий період чи bbox — 400 без запиту в БД; гість — 403; POST — 405; ліміт — 429", async () => {
  for (const q of ["?period=5d", "?bbox=abc", "?bbox=31,50,30,51", "?bbox=10,40,40,60"]) {
    const d = db();
    const { res } = await run(d, req("GET", URL_ + q));
    assertEquals(res.status, 400, q);
    assertEquals(find(d, "rpc.heatmap_cells"), undefined);
  }
  let d = db();
  assertEquals((await run(d, req("GET", URL_), { anon: true })).res.status, 403);
  assertEquals(find(d, "rpc.heatmap_cells"), undefined);
  assertEquals((await run(db(), req("POST", URL_, {}))).res.status, 405);
  d = mockDb({ ...RL_BLOCKED });
  assertEquals((await run(d, req("GET", URL_))).res.status, 429);
});

Deno.test("heatmap: помилка БД — 500 без деталей", async () => {
  const d = db({ "rpc.heatmap_cells": { data: null, error: { message: "secret sql" } } });
  const { res, json } = await run(d, req("GET", URL_));
  assertEquals(res.status, 500);
  assertEquals(JSON.stringify(json).includes("secret"), false);
});

Deno.test("parseHeatmapQuery: 3d за замовчуванням, 7d, 30d", () => {
  assertEquals(parseHeatmapQuery(new URL(URL_)).periodDays, 3);
  assertEquals(parseHeatmapQuery(new URL(`${URL_}?period=7d`)).periodDays, 7);
  assertEquals(parseHeatmapQuery(new URL(`${URL_}?period=30d`)), { periodDays: 30, bbox: null });
});
