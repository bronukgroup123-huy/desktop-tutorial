import { assert, assertEquals } from "jsr:@std/assert";
import type { ForecastResult, ScoredSpecies } from "../../functions/_shared/forecast/types.ts";
import { handle } from "../../functions/_shared/http.ts";
import {
  type AreaForecastInput,
  daysAhead,
  handleAnalysis,
  km2Label,
  kyivToday,
  pickBest,
  secondsToKyivMidnight,
} from "../../functions/_shared/v1/analysis.ts";
import { type Call, mockDb, req, type Results, RL_BLOCKED, RL_OK, verifyAs } from "./mock-db.ts";

const NOW = new Date("2026-11-11T10:00:00Z"); // 12:00 у Києві
const USER = "11111111-1111-4111-8111-111111111111";
const AREA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const URL_ = "http://localhost/v1-analysis";
const KYIV = { lat: 50.4501, lng: 30.5234 };
// POINT(30.5 50.4) — центр збереженої ділянки у форматі PostgREST
const EWKB = "0101000020E61000000000000000803E403333333333334940";

const species = (o: Partial<ScoredSpecies> = {}): ScoredSpecies => ({
  mushroom_type: "boletus_edulis",
  name_ua: "Білий гриб",
  score: 0.83,
  probability: "high",
  matched: [],
  missed: [],
  wave: null,
  ...o,
});

const result = (o: Partial<ForecastResult> = {}): ForecastResult => ({
  regionName: "Київська",
  date: "2026-11-11",
  forest: "pine",
  top1: species(),
  alternative: species({ mushroom_type: "suillus_luteus", name_ua: "Маслюк звичайний", score: 0.61, probability: "medium" }),
  warnings: ["Не збирайте гриби біля доріг."],
  weather: null,
  ...o,
});

const FOREST = {
  bbox: [30.488, 50.4276, 30.5588, 50.4726],
  area_km2: 25,
  forest_km2: 9.42,
  types: [
    { forest_type: "pine", km2: 8.4, stand_age_years: 60 },
    { forest_type: "oak", km2: 1.02, stand_age_years: null },
  ],
};

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": { data: { home_region_id: 10 }, error: null },
    "analysis_areas.select": { data: [], error: null },
    "rpc.point_in_region": { data: true, error: null },
    "rpc.save_analysis_area": { data: AREA, error: null },
    "rpc.consume_analysis": { data: 1, error: null },
    "rpc.analysis_used_today": { data: 0, error: null },
    "rpc.analyze_area_forest": { data: FOREST, error: null },
    "rpc.refund_analysis": { data: null, error: null },
    ...extra,
  });
}

interface Opts {
  forecast?: (input: AreaForecastInput) => Promise<ForecastResult>;
  pro?: boolean;
  isAnonymous?: boolean;
}

async function run(d: ReturnType<typeof mockDb>, r: Request, opts: Opts = {}) {
  const inputs: AreaForecastInput[] = [];
  const res = await handle((x) =>
    handleAnalysis(x, {
      db: d,
      verify: verifyAs(USER, opts.isAnonymous ?? false),
      now: () => NOW,
      hasAnalysisPro: () => Promise.resolve(opts.pro ?? false),
      forecast: (input) => {
        inputs.push(input);
        return (opts.forecast ?? (() => Promise.resolve(result())))(input);
      },
    })
  )(r);
  return { res, json: await res.json(), inputs };
}

const find = (d: ReturnType<typeof mockDb>, key: string): Call | undefined => d.calls.find((c) => c.key === key);
const body = (o: Record<string, unknown> = {}) => ({ ...KYIV, size_km: 5, ...o });

// ─── GET ────────────────────────────────────────────────────────────────────

Deno.test("analysis GET: без Pro — 5×5 доступна, 10×10 із замком «Доступно в Pro»; ліміт 5 на добу", async () => {
  const { res, json } = await run(db(), req("GET", URL_));
  assertEquals(res.status, 200);
  assertEquals(json.data.sizes, [
    { size_km: 5, label: "5×5 км", available: true, lock_label: null },
    { size_km: 10, label: "10×10 км", available: false, lock_label: "Доступно в Pro" },
  ]);
  assertEquals(json.data.areas, []);
  assertEquals(json.data.usage, { used: 0, limit: 5, label: "Сьогодні: 0 з 5 аналізів" });
  assert(json.data.hint_label.length > 0);
});

Deno.test("analysis GET: збережена ділянка і використані сьогодні аналізи", async () => {
  const d = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null },
    "rpc.analysis_used_today": { data: 3, error: null },
  });
  const { json } = await run(d, req("GET", URL_));
  assertEquals(json.data.areas, [{ id: AREA, slot: 1, lat: 50.4, lng: 30.5, size_km: 5, size_label: "5×5 км" }]);
  assertEquals(json.data.usage, { used: 3, limit: 5, label: "Сьогодні: 3 з 5 аналізів" });
  assertEquals(find(d, "analysis_areas.select")!.filters, [["user_id", USER]]);
});

Deno.test("analysis GET: у Pro обидва розміри доступні, ліміт 10", async () => {
  const { json } = await run(db(), req("GET", URL_), { pro: true });
  assertEquals(json.data.sizes.map((s: { available: boolean }) => s.available), [true, true]);
  assertEquals(json.data.usage.limit, 10);
});

// ─── POST ───────────────────────────────────────────────────────────────────

Deno.test("analysis POST: 5×5 → рівні з підписами, ліс у квадраті, межі ділянки, ліміт; без чисел-ймовірностей", async () => {
  const d = db();
  const { res, json, inputs } = await run(d, req("POST", URL_, body()));
  assertEquals(res.status, 200);
  const a = json.data;

  assertEquals(a.area, {
    id: AREA, slot: 1, lat: KYIV.lat, lng: KYIV.lng, size_km: 5, size_label: "5×5 км", bbox: FOREST.bbox,
  });
  assertEquals(a.date, "2026-11-11");
  assertEquals(a.forest, {
    summary_label: "Ліс займає ≈ 9,4 км² з 25 км² ділянки",
    types: [
      { forest_type: "pine", type_label: "Сосновий ліс", type_color: "#81c784", area_label: "≈ 8,4 км²", age_label: "~60 р." },
      { forest_type: "oak", type_label: "Дубовий ліс", type_color: "#4caf50", area_label: "≈ 1,0 км²", age_label: null },
    ],
  });
  assertEquals(a.top1.name_ua, "Білий гриб");
  assertEquals(a.top1.level, "high");
  assertEquals(a.top1.level_label, "Висока ймовірність");
  assertEquals(a.top1.forest_label, "Сосновий ліс");
  assertEquals(a.alternative.name_ua, "Маслюк звичайний");
  assertEquals(a.usage, { used: 1, limit: 5, label: "Сьогодні: 1 з 5 аналізів" });
  assertEquals(a.warnings, ["Не збирайте гриби біля доріг."]);

  // жодних чисел-ймовірностей (маніфест, Заборона №1)
  const text = JSON.stringify(json);
  assertEquals(/score|probability|0\.83|0\.61|%/.test(text), false);

  // прогноз — для двох переважних типів лісу, в центрі ділянки, у своїй області
  assertEquals(inputs.map((i) => i.forestType), ["pine", "oak"]);
  assertEquals([inputs[0].lat, inputs[0].lng, inputs[0].homeRegionId], [KYIV.lat, KYIV.lng, 10]);
  assertEquals(inputs[0].date.toISOString(), "2026-11-11T00:00:00.000Z");

  assertEquals(find(d, "rpc.save_analysis_area")!.args[0], {
    p_user_id: USER, p_slot: 1, p_lat: KYIV.lat, p_lng: KYIV.lng, p_size_km: 5, p_region_id: 10,
  });
  assertEquals(find(d, "rpc.consume_analysis")!.args[0], { p_user_id: USER, p_area_id: AREA, p_limit: 5 });
  assertEquals(find(d, "rpc.analyze_area_forest")!.args[0], { p_region_id: 10, p_lat: KYIV.lat, p_lng: KYIV.lng, p_size_km: 5 });
});

Deno.test("analysis POST: безкоштовно 10×10 → 403 pro_required, ділянка не зберігається, аналіз не списується", async () => {
  const d = db();
  const { res, json, inputs } = await run(d, req("POST", URL_, body({ size_km: 10 })));
  assertEquals(res.status, 403);
  assertEquals(json.error, "pro_required");
  assert(json.message.includes("Pro"));
  assertEquals(find(d, "rpc.save_analysis_area"), undefined);
  assertEquals(find(d, "rpc.consume_analysis"), undefined);
  assertEquals(inputs.length, 0);
});

Deno.test("analysis POST: у Pro 10×10 дозволено, ліміт 10 на добу", async () => {
  const d = db();
  const { res, json } = await run(d, req("POST", URL_, body({ size_km: 10 })), { pro: true });
  assertEquals(res.status, 200);
  assertEquals(json.data.area.size_label, "10×10 км");
  assertEquals((find(d, "rpc.consume_analysis")!.args[0] as Record<string, unknown>).p_limit, 10);
  assertEquals((find(d, "rpc.save_analysis_area")!.args[0] as Record<string, unknown>).p_size_km, 10);
});

Deno.test("analysis POST: ділянка поза областю → 403 outside_home_region (і в Pro)", async () => {
  for (const pro of [false, true]) {
    const d = db({ "rpc.point_in_region": { data: false, error: null } });
    const { res, json } = await run(d, req("POST", URL_, body()), { pro });
    assertEquals(res.status, 403);
    assertEquals(json.error, "outside_home_region");
    assertEquals(find(d, "rpc.consume_analysis"), undefined);
  }
});

Deno.test("analysis POST: шостий аналіз за добу → 429 analysis_limit_reached з часом скидання", async () => {
  // ділянка вже є — ліміт перевіряється до того, як її пересунути
  const d = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null },
    "rpc.consume_analysis": { data: null, error: null },
  });
  const { res, json, inputs } = await run(d, req("POST", URL_, body()));
  assertEquals(res.status, 429);
  assertEquals(json.error, "analysis_limit_reached");
  assert(json.message.includes("5"));
  assertEquals(res.headers.get("Retry-After"), String(12 * 3600)); // до київської півночі
  assertEquals(find(d, "rpc.save_analysis_area"), undefined);
  assertEquals(inputs.length, 0);
});

Deno.test("analysis POST: наявна ділянка — спершу ліміт, потім пересування; лічильник з БД", async () => {
  const d = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null },
    "rpc.consume_analysis": { data: 4, error: null },
  });
  const { json } = await run(d, req("POST", URL_, body()));
  assertEquals(json.data.usage, { used: 4, limit: 5, label: "Сьогодні: 4 з 5 аналізів" });
  const order = d.calls.map((c) => c.key).filter((k) => k.startsWith("rpc.") && !k.includes("rate_limit"));
  assertEquals(order, ["rpc.point_in_region", "rpc.consume_analysis", "rpc.save_analysis_area", "rpc.analyze_area_forest"]);
  assertEquals(d.calls.filter((c) => c.key === "rpc.consume_analysis").length, 1);
});

Deno.test("analysis POST: у ділянці немає лісів → базовий прогноз (тип лісу невідомий)", async () => {
  const d = db({ "rpc.analyze_area_forest": { data: { ...FOREST, forest_km2: 0, types: [] }, error: null } });
  const { json, inputs } = await run(d, req("POST", URL_, body()));
  assertEquals(inputs.map((i) => i.forestType), [null]);
  assertEquals(json.data.forest.summary_label, "На карті в цій ділянці лісів немає — прогноз базовий");
  assertEquals(json.data.top1.forest_label, null);
});

Deno.test("analysis POST: найкращий вид обирається серед усіх типів лісу ділянки", async () => {
  const forecast = (input: AreaForecastInput) =>
    Promise.resolve(
      input.forestType === "pine"
        ? result({ top1: species({ score: 0.5, probability: "medium" }), alternative: null })
        : result({
          top1: species({ mushroom_type: "leccinum_scabrum", name_ua: "Підберезник", score: 0.9, probability: "peak" }),
          alternative: null,
          warnings: ["Не збирайте гриби біля доріг.", "Беріть воду."],
        }),
    );
  const { json } = await run(db(), req("POST", URL_, body()), { forecast });
  assertEquals([json.data.top1.name_ua, json.data.top1.forest_label], ["Підберезник", "Дубовий ліс"]);
  assertEquals([json.data.alternative.name_ua, json.data.alternative.forest_label], ["Білий гриб", "Сосновий ліс"]);
  assertEquals(json.data.warnings, ["Не збирайте гриби біля доріг.", "Беріть воду."]); // без повторів
});

Deno.test("analysis POST: кандидатів немає → top1 = null і причина", async () => {
  const forecast = () => Promise.resolve(result({ top1: null, alternative: null, noDataReason: "out_of_season" }));
  const { res, json } = await run(db(), req("POST", URL_, body()), { forecast });
  assertEquals(res.status, 200);
  assertEquals([json.data.top1, json.data.alternative, json.data.no_data_reason], [null, null, "out_of_season"]);
});

Deno.test("analysis POST: базова погода — температура, вологість, опади (без розширених полів)", async () => {
  const weather = {
    tempMin: 5, tempMax: 12, tempAvg7d: 9, humidity: 82, rain1d: 0, rain3d: 6, rain7d: 14,
    daysAfterRain: 2, pressure: 1012, pressureTrend: "stable",
  };
  const forecast = () => Promise.resolve(result({ weather: weather as unknown as ForecastResult["weather"] }));
  const { json } = await run(db(), req("POST", URL_, body()), { forecast });
  assertEquals(Object.keys(json.data.weather ?? {}).sort(), ["humidity_label", "icon", "rain_label", "temp_label"]);
});

Deno.test("analysis POST: розрахунок упав → 500 і списаний аналіз повернуто", async () => {
  const d = db();
  const forecast = () => Promise.reject(new Error("engine exploded"));
  const { res, json } = await run(d, req("POST", URL_, body()), { forecast });
  assertEquals(res.status, 500);
  assertEquals(json.error, "internal_error");
  assertEquals(JSON.stringify(json).includes("exploded"), false);
  assertEquals(find(d, "rpc.refund_analysis")!.args[0], { p_user_id: USER, p_area_id: AREA });

  const d2 = db({ "rpc.analyze_area_forest": { data: null, error: { message: "boom" } } });
  const failed = await run(d2, req("POST", URL_, body()));
  assertEquals(failed.res.status, 500);
  assertEquals(failed.json.error, "db_error");
  assert(find(d2, "rpc.refund_analysis") !== undefined);
});

Deno.test("analysis POST: дата — сьогодні…+3 дні безкоштовно; далі → 403 pro_required; минуле → 422", async () => {
  assertEquals((await run(db(), req("POST", URL_, body({ date: "2026-11-14" })))).res.status, 200);

  const far = await run(db(), req("POST", URL_, body({ date: "2026-11-15" })));
  assertEquals(far.res.status, 403);
  assertEquals(far.json.error, "pro_required");
  assertEquals((await run(db(), req("POST", URL_, body({ date: "2026-11-20" })), { pro: true })).res.status, 200);

  const past = await run(db(), req("POST", URL_, body({ date: "2026-11-10" })));
  assertEquals(past.res.status, 422);
  assertEquals(past.json.error, "validation_error");
});

Deno.test("analysis POST: валідація тіла → 422 validation_error українською", async () => {
  for (
    const bad of [
      body({ lat: 91 }),
      body({ lng: "30.5" }),
      body({ size_km: 7 }),
      body({ size_km: "5" }),
      body({ size_km: undefined }),
      body({ date: "11.11.2026" }),
      body({ date: "2026-13-45" }),
      [body()],
      null,
    ]
  ) {
    const d = db();
    const { res, json } = await run(d, req("POST", URL_, bad));
    assertEquals(res.status, 422, JSON.stringify(bad));
    assertEquals(json.error, "validation_error");
    assert(/[а-яіїє]/i.test(json.message));
    assertEquals(find(d, "rpc.consume_analysis"), undefined);
  }
});

Deno.test("analysis: 401 без токена, 409 без області, 429 rate limit, 405 для інших методів, гість — можна", async () => {
  assertEquals((await run(db(), new Request(URL_))).res.status, 401);
  const noRegion = await run(db({ "users.select": { data: { home_region_id: null }, error: null } }), req("POST", URL_, body()));
  assertEquals(noRegion.res.status, 409);
  assertEquals((await run(db(RL_BLOCKED), req("GET", URL_))).res.status, 429);
  assertEquals((await run(db(), req("DELETE", URL_))).res.status, 405);
  assertEquals((await run(db(), req("POST", URL_, body()), { isAnonymous: true })).res.status, 200);
});

// ─── Чисті функції ──────────────────────────────────────────────────────────

Deno.test("analysis: київська доба, дні наперед, підпис площі", () => {
  assertEquals(kyivToday(new Date("2026-11-11T21:30:00Z")), "2026-11-11"); // 23:30 у Києві
  assertEquals(kyivToday(new Date("2026-11-11T22:30:00Z")), "2026-11-12"); // 00:30 наступної доби
  assertEquals(secondsToKyivMidnight(new Date("2026-11-11T21:59:30Z")), 30);
  assertEquals(secondsToKyivMidnight(new Date("2026-07-01T09:00:00Z")), 12 * 3600); // літній час, UTC+3
  assertEquals(daysAhead("2026-11-14", "2026-11-11"), 3);
  assertEquals(daysAhead("2026-12-01", "2026-11-30"), 1);
  assertEquals(km2Label(8.44), "≈ 8,4 км²");
  assertEquals(km2Label(0.04), "≈ 0,0 км²");
  assertEquals(km2Label(12.6), "≈ 13 км²");
});

Deno.test("analysis: pickBest — порожні прогони", () => {
  assertEquals(pickBest([]), { top1: null, alternative: null });
  const only = pickBest([{ forestType: "pine", result: result({ alternative: null }) }]);
  assertEquals(only.top1?.species.mushroom_type, "boletus_edulis");
  assertEquals(only.alternative, null);
});
