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
    "rpc.create_analysis_area": { data: [{ id: AREA, slot: 1 }], error: null },
    "rpc.save_analysis_result": { data: null, error: null },
    "rpc.delete_analysis_area": { data: true, error: null },
    "rpc.consume_analysis": { data: 1, error: null },
    "rpc.analysis_used_today": { data: 0, error: null },
    "rpc.analyze_area_forest": { data: FOREST, error: null },
    "rpc.refund_analysis": { data: null, error: null },
    "rpc.forest_edits_today": { data: 0, error: null },
    "rpc.consume_forest_edit": { data: 1, error: null },
    "rpc.save_forest_override": { data: true, error: null },
    "rpc.refund_forest_edit": { data: null, error: null },
    ...extra,
  });
}

/** Прогноз одного дня (тести задають результат по днях; рушій рахує всі дні за раз). */
type DayInput = Omit<AreaForecastInput, "dates"> & { date: Date };

interface Opts {
  forecast?: (input: DayInput) => Promise<ForecastResult>;
  pro?: boolean;
  isAnonymous?: boolean;
  /** Додаткові залежності (рельєф тощо). */
  deps?: Record<string, unknown>;
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
        const { dates, ...rest } = input;
        const one = opts.forecast ?? (() => Promise.resolve(result()));
        return Promise.all(dates.map((d) => one({ ...rest, date: new Date(`${d}T00:00:00Z`) })));
      },
      ...(opts.deps ?? {}),
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
  assertEquals(json.data.can_create, true);
});

Deno.test("analysis GET: збережена ділянка і використані сьогодні аналізи", async () => {
  const d = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null },
    "rpc.analysis_used_today": { data: 3, error: null },
  });
  const { json } = await run(d, req("GET", URL_));
  const usage = { used: 3, limit: 5, label: "Сьогодні: 3 з 5 аналізів" };
  assertEquals(json.data.areas, [{
    id: AREA, slot: 1, lat: 50.4, lng: 30.5, size_km: 5, size_label: "5×5 км", label: null, title: "Ділянка 1", usage,
    last_result: null, last_analyzed_at: null, forest_override: null,
    forest_edit: { used: 0, limit: 2, can_edit: true, label: "Уточнити ліс сьогодні можна ще 2 рази" },
  }]);
  // список порід для «Уточнити ліс» — із сервера, лише зі списку
  assertEquals(json.data.forest_edit_options.species[0], { code: "pine", label: "Сосна" });
  assertEquals(json.data.forest_edit_options.presence.map((p: { code: string }) => p.code), ["dominant", "present"]);
  assertEquals(json.data.usage, usage);
  // безкоштовно ділянка одна — нову створити не можна, доки не видалити стару
  assertEquals(json.data.can_create, false);
  assert(json.data.create_hint_label.includes("видаліть стару"));
  // три клітинки: перша — ділянка, дві інші під замком Pro
  assertEquals(json.data.slots, [
    { slot: 1, state: "area", area_id: AREA, title: "Ділянка 1", subtitle: "5×5 км" },
    { slot: 2, state: "locked", area_id: null, title: "Ділянка 2", subtitle: null, locked_label: "Ще 2 ділянки — у Pro" },
    { slot: 3, state: "locked", area_id: null, title: "Ділянка 3", subtitle: null, locked_label: "Ще 2 ділянки — у Pro" },
  ]);
  assertEquals(json.data.label_max, 24);
  assertEquals(find(d, "rpc.analysis_used_today")!.args[0], { p_user_id: USER, p_slot: 1 });
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
      { forest_type: "pine", type_label: "Сосновий ліс", type_color: "#81c784", area_label: "≈ 8,4 км²", age_label: "~60 р.", species: [], species_label: null },
      { forest_type: "oak", type_label: "Дубовий ліс", type_color: "#4caf50", area_label: "≈ 1,0 км²", age_label: null, species: [], species_label: null },
    ],
    extra: [],
    refined: false,
    refine_note_label: "Уточнення діє лише для вашої ділянки. Знайдете тут гриб — зробіть тук-тук, і ліс уточниться для всіх.",
    terrain_label: null,
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
  // один прогін на тип лісу — усі 3 дні безкоштовного горизонту від сьогодні
  assertEquals(inputs[0].dates, ["2026-11-11", "2026-11-12", "2026-11-13"]);

  assertEquals(find(d, "rpc.create_analysis_area")!.args[0], {
    p_user_id: USER, p_max_slots: 1, p_lat: KYIV.lat, p_lng: KYIV.lng, p_size_km: 5, p_region_id: 10,
  });
  assertEquals(find(d, "rpc.consume_analysis")!.args[0], { p_user_id: USER, p_slot: 1, p_limit: 5 });
  // останній результат зберігається з ділянкою
  const saved = find(d, "rpc.save_analysis_result")!.args[0] as Record<string, unknown>;
  assertEquals([saved.p_user_id, saved.p_area_id], [USER, AREA]);
  assertEquals((saved.p_result as Record<string, unknown>).date, "2026-11-11");
  assertEquals(find(d, "rpc.analyze_area_forest")!.args[0], { p_region_id: 10, p_lat: KYIV.lat, p_lng: KYIV.lng, p_size_km: 5 });
});

Deno.test("analysis POST: безкоштовно 10×10 → 403 pro_required, ділянка не зберігається, аналіз не списується", async () => {
  const d = db();
  const { res, json, inputs } = await run(d, req("POST", URL_, body({ size_km: 10 })));
  assertEquals(res.status, 403);
  assertEquals(json.error, "pro_required");
  assert(json.message.includes("Pro"));
  assertEquals(find(d, "rpc.create_analysis_area"), undefined);
  assertEquals(find(d, "rpc.consume_analysis"), undefined);
  assertEquals(inputs.length, 0);
});

Deno.test("analysis POST: у Pro 10×10 дозволено, ліміт 10 на добу", async () => {
  const d = db();
  const { res, json } = await run(d, req("POST", URL_, body({ size_km: 10 })), { pro: true });
  assertEquals(res.status, 200);
  assertEquals(json.data.area.size_label, "10×10 км");
  assertEquals((find(d, "rpc.consume_analysis")!.args[0] as Record<string, unknown>).p_limit, 10);
  const created = find(d, "rpc.create_analysis_area")!.args[0] as Record<string, unknown>;
  assertEquals([created.p_size_km, created.p_max_slots], [10, 3]);
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

Deno.test("analysis POST: шостий аналіз ділянки за добу → 429 analysis_limit_reached з часом скидання", async () => {
  const d = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null },
    "rpc.consume_analysis": { data: null, error: null },
  });
  const { res, json, inputs } = await run(d, req("POST", URL_, { area_id: AREA }));
  assertEquals(res.status, 429);
  assertEquals(json.error, "analysis_limit_reached");
  assert(json.message.includes("5"));
  assertEquals(res.headers.get("Retry-After"), String(12 * 3600)); // до київської півночі
  assertEquals(inputs.length, 0);
});

Deno.test("analysis POST: ділянку не пересувають — повторний аналіз за area_id з її центром і розміром", async () => {
  const d = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null },
    "rpc.consume_analysis": { data: 4, error: null },
  });
  const { res, json, inputs } = await run(d, req("POST", URL_, { area_id: AREA }));
  assertEquals(res.status, 200);
  assertEquals([json.data.area.id, json.data.area.lat, json.data.area.lng], [AREA, 50.4, 30.5]);
  assertEquals([inputs[0].lat, inputs[0].lng], [50.4, 30.5]);
  assertEquals(json.data.usage, { used: 4, limit: 5, label: "Сьогодні: 4 з 5 аналізів" });
  assertEquals(find(d, "rpc.create_analysis_area"), undefined);
  assertEquals(find(d, "rpc.consume_analysis")!.args[0], { p_user_id: USER, p_slot: 1, p_limit: 5 });
  assertEquals(find(d, "rpc.analyze_area_forest")!.args[0], { p_region_id: 10, p_lat: 50.4, p_lng: 30.5, p_size_km: 5 });

  // спроба «пересунути» ділянку тим самим запитом — 422
  const moved = await run(db(), req("POST", URL_, { area_id: AREA, ...KYIV }));
  assertEquals([moved.res.status, moved.json.error], [422, "validation_error"]);
  // чужа / видалена ділянка — 404
  const gone = await run(db(), req("POST", URL_, { area_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }));
  assertEquals([gone.res.status, gone.json.error], [404, "not_found"]);
});

Deno.test("analysis POST: безкоштовно вже є ділянка → нова не створюється (409), аналіз не списується", async () => {
  const d = db({ "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null } });
  const { res, json, inputs } = await run(d, req("POST", URL_, body()));
  assertEquals([res.status, json.error], [409, "area_limit_reached"]);
  assert(json.message.includes("видаліть стару"));
  assertEquals([find(d, "rpc.consume_analysis"), find(d, "rpc.create_analysis_area"), inputs.length], [undefined, undefined, 0]);
});

Deno.test("analysis POST: Pro — друга ділянка займає слот 2 (ліміт рахується на слот 2)", async () => {
  const d = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB }], error: null },
    "rpc.create_analysis_area": { data: [{ id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", slot: 2 }], error: null },
  });
  const { res, json } = await run(d, req("POST", URL_, body({ size_km: 10 })), { pro: true });
  assertEquals(res.status, 200);
  assertEquals(json.data.area.slot, 2);
  assertEquals(find(d, "rpc.consume_analysis")!.args[0], { p_user_id: USER, p_slot: 2, p_limit: 10 });
});

Deno.test("analysis POST: паралельний запит зайняв слот → 409 і списаний аналіз повернуто", async () => {
  const d = db({ "rpc.create_analysis_area": { data: [], error: null } });
  const { res, json } = await run(d, req("POST", URL_, body()));
  assertEquals([res.status, json.error], [409, "area_limit_reached"]);
  assertEquals(find(d, "rpc.refund_analysis")!.args[0], { p_user_id: USER, p_slot: 1 });
});

Deno.test("analysis DELETE: видалення своєї ділянки; чужа/неіснуюча — 404", async () => {
  const d = db();
  const { res, json } = await run(d, req("DELETE", `${URL_}/areas/${AREA}`));
  assertEquals([res.status, json.data], [200, { deleted: true }]);
  assertEquals(find(d, "rpc.delete_analysis_area")!.args[0], { p_user_id: USER, p_area_id: AREA });

  const missing = await run(db({ "rpc.delete_analysis_area": { data: false, error: null } }), req("DELETE", `${URL_}/areas/${AREA}`));
  assertEquals(missing.res.status, 404);
  assertEquals((await run(db(), req("DELETE", `${URL_}/areas/not-a-uuid`))).res.status, 404);
  assertEquals((await run(db(), req("DELETE", URL_))).res.status, 404);
});

Deno.test("analysis POST: у ділянці немає лісів → лісових видів немає, пояснення (узгоджено з «лісів немає»)", async () => {
  const d = db({ "rpc.analyze_area_forest": { data: { ...FOREST, forest_km2: 0, types: [] }, error: null } });
  const { json, inputs } = await run(d, req("POST", URL_, body()));
  assertEquals(inputs.map((i) => i.forestType), [null]); // прогін лише заради погоди
  assertEquals(json.data.forest.summary_label, "На карті в цій ділянці лісів немає");
  assertEquals([json.data.top1, json.data.alternative], [null, null]);
  assert(String(json.data.no_data_reason).includes("немає лісу"));
});

Deno.test("analysis POST: ліс із карти застосунку (forest) замінює неповні дані БД", async () => {
  const d = db({ "rpc.analyze_area_forest": { data: { ...FOREST, forest_km2: 0, types: [] }, error: null } });
  const hint = { forest_km2: 14.2, types: [{ forest_type: "birch", km2: 3.1 }, { forest_type: "pine", km2: 11.1 }] };
  const { res, json, inputs } = await run(d, req("POST", URL_, body({ forest: hint })));
  assertEquals(res.status, 200);
  assertEquals(json.data.forest.summary_label, "Ліс займає ≈ 14 км² з 25 км² ділянки");
  assertEquals(json.data.forest.types.map((t: { forest_type: string }) => t.forest_type), ["pine", "birch"]);
  assertEquals(inputs.map((i) => i.forestType), ["pine", "birch"]);
  assert(json.data.top1 !== null);
  assertEquals(json.data.area.bbox, FOREST.bbox); // межі квадрата — з БД
});

Deno.test("analysis POST: некоректний forest → 422", async () => {
  for (const forest of [
    { forest_km2: 99, types: [] },
    { forest_km2: 1, types: [{ forest_type: "Drop table", km2: 1 }] },
    { forest_km2: 1, types: [{ forest_type: "pine", km2: 20 }, { forest_type: "oak", km2: 20 }] },
  ]) {
    const { res, json } = await run(db(), req("POST", URL_, body({ forest })));
    assertEquals([res.status, json.error], [422, "validation_error"]);
  }
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
  assertEquals(Object.keys(json.data.weather ?? {}).sort(), [
    "day_label", "humidity_label", "icon", "rain_label", "range_label", "scene", "scene_label", "sprouts", "sun_label",
    "take_label", "temp_label", "verdict_label", "verdict_tone",
  ]);
});

Deno.test("analysis POST: погода дня — температура й опади саме цього дня", async () => {
  const forecast = (input: DayInput) => {
    const date = input.date.toISOString().slice(0, 10);
    const rain = date === "2026-11-12" ? 7.6 : 0;
    const weather = {
      tempMin: 5, tempMax: 12, tempAvg7d: 9, humidity: 70, rain1d: rain, rain3d: 6, rain7d: 14,
      daysAfterRain: 2, pressure: 1012, pressureTrend: "stable",
      day: { date, tempMin: 3.6, tempMax: 11.4, rain, humidity: 70, daysAhead: 0 },
    };
    return Promise.resolve(result({ weather: weather as unknown as ForecastResult["weather"] }));
  };
  const { json } = await run(db(), req("POST", URL_, body()), { forecast });
  const days = json.data.days as Array<{ weather: { icon: string; day_label: string } }>;
  assertEquals(days.map((d) => d.weather.icon), ["sun", "rain", "sun"]);
  assertEquals(days.map((d) => d.weather.day_label), ["4…11°, без опадів", "4…11°, опади 8 мм", "4…11°, без опадів"]);
});

Deno.test("analysis POST: розширені дані погоди — дощ → гриби, що сталося, шкали, що далі", async () => {
  const day = (date: string, rain: number, tmin = 1.4) => ({ date, tempMin: tmin, tempMax: 7.6, rain, humidity: 80, daysAhead: 0 });
  const forecast = (input: DayInput) => {
    const date = input.date.toISOString().slice(0, 10);
    const weather = {
      tempMin: 1, tempMax: 8, tempAvg7d: 4, humidity: 85, rain1d: 0, rain3d: 12, rain7d: 25, rain14d: 30,
      droughtDays: 0, daysAfterRain: 2, pressure: 1012, pressureTrend: "stable", source: "open-meteo", soilState: "wet",
      day: day(date, date === "2026-11-12" ? 9.04 : 0),
      recent: ["2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09", "2026-11-10", date]
        .map((d, k) => day(d, k === 2 ? 14 : 0, k === 4 ? -2.4 : 1.4)),
    };
    return Promise.resolve(result({ weather: weather as unknown as ForecastResult["weather"] }));
  };
  const { json } = await run(db(), req("POST", URL_, body()), { forecast });
  const ins = json.data.weather_insight;
  assertEquals(ins.days.length, 9); // 05.11–11.11 + 12.11, 13.11
  assertEquals(ins.days[0], {
    date: "2026-11-05", label: "Чт", date_label: "05", rain: 0, soaking: false, temp: "cold", forecast: false, today: false,
  });
  assertEquals([ins.days[2].rain, ins.days[2].soaking], [14, true]); // 07.11 — злива промочила ґрунт
  assertEquals(ins.days[4].temp, "frost");
  assertEquals(ins.days.find((d: { today: boolean }) => d.today).label, "сьог.");
  assertEquals(ins.events.map((e: { icon: string }) => e.icon), ["frost", "rain"]); // свіжіші — першими
  assertEquals(ins.events[1].label, "Дощ 14 мм, 07.11 — ґрунт промочило");
  assertEquals(ins.events[0].label, "Заморозок -2°, 09.11 — ріст пригальмував");
  assertEquals(ins.gauges.map((g: { key: string }) => g.key), ["soil", "warmth", "rain14"]);
  assertEquals([ins.gauges[0].index, ins.gauges[0].tone], [2, "good"]); // волого
  assertEquals([ins.gauges[1].index, ins.gauges[1].hint], [0, "ростуть лише зимові гриби"]);
  assertEquals([ins.gauges[2].value_label, ins.gauges[2].fill], ["30 мм — достатньо", 0.75]);
  assertEquals(ins.outlook_label, "Завтра — дощ 9 мм: промочить ґрунт — за 1–2 тижні можлива хвиля");
  assertEquals(json.data.weather_chart, undefined);
  // висновок для грибів: свіжий дощ (12 мм за 3 дні)
  assertEquals(json.data.days[0].weather.verdict_tone, "good");
  assert(json.data.days[0].weather.verdict_label.includes("Свіжий дощ"));
});

Deno.test("analysis POST: розрахунок упав → 500 і списаний аналіз повернуто", async () => {
  const d = db();
  const forecast = () => Promise.reject(new Error("engine exploded"));
  const { res, json } = await run(d, req("POST", URL_, body()), { forecast });
  assertEquals(res.status, 500);
  assertEquals(json.error, "internal_error");
  assertEquals(JSON.stringify(json).includes("exploded"), false);
  assertEquals(find(d, "rpc.refund_analysis")!.args[0], { p_user_id: USER, p_slot: 1 });

  const d2 = db({ "rpc.analyze_area_forest": { data: null, error: { message: "boom" } } });
  const failed = await run(d2, req("POST", URL_, body()));
  assertEquals(failed.res.status, 500);
  assertEquals(failed.json.error, "db_error");
  assert(find(d2, "rpc.refund_analysis") !== undefined);
});

Deno.test("analysis POST: дата — сьогодні…+2 дні безкоштовно, …+6 у Pro; далі → 403/422; минуле → 422", async () => {
  assertEquals((await run(db(), req("POST", URL_, body({ date: "2026-11-13" })))).res.status, 200);

  const far = await run(db(), req("POST", URL_, body({ date: "2026-11-14" })));
  assertEquals(far.res.status, 403);
  assertEquals(far.json.error, "pro_required");
  assertEquals((await run(db(), req("POST", URL_, body({ date: "2026-11-17" })), { pro: true })).res.status, 200);
  const beyond = await run(db(), req("POST", URL_, body({ date: "2026-11-18" })), { pro: true });
  assertEquals([beyond.res.status, beyond.json.error], [422, "validation_error"]);

  const past = await run(db(), req("POST", URL_, body({ date: "2026-11-10" })));
  assertEquals(past.res.status, 422);
  assertEquals(past.json.error, "validation_error");
});

Deno.test("analysis POST: дні — безкоштовно 3 (сьогодні, завтра, Пт 13) і 4 дні під замком Pro", async () => {
  const { json } = await run(db(), req("POST", URL_, body()));
  const a = json.data;
  assertEquals(a.horizon_days, 3);
  assertEquals(a.days.map((d: { day_label: string }) => d.day_label), ["Сьогодні", "Завтра", "Пт 13"]);
  assertEquals(a.days.map((d: { approximate: boolean }) => d.approximate), [false, false, false]);
  assertEquals(a.days[0].top1, a.top1); // верхній рівень — обраний день (сьогодні)
  assertEquals([a.days[1].level_label, a.days[1].level_short_label], ["Висока ймовірність", "Висока"]);
  assertEquals(a.locked_days.map((d: { day_label: string }) => d.day_label), ["Сб 14", "Нд 15", "Пн 16", "Вт 17"]);
  assertEquals(a.locked_label, "Ще 4 дні прогнозу — у Pro");
  // дні під замком — без прогнозу (лише дата й підпис)
  assertEquals(Object.keys(a.locked_days[0]).sort(), ["date", "day_label"]);
});

Deno.test("analysis POST: Pro — 7 днів, дні 5–7 «орієнтовно», найкращий день — з найвищим рівнем", async () => {
  const levels: Record<string, ["high" | "medium" | "low", number]> = {
    "2026-11-11": ["low", 0.4], "2026-11-12": ["medium", 0.6], "2026-11-13": ["high", 0.75],
    "2026-11-14": ["high", 0.86], "2026-11-15": ["medium", 0.6], "2026-11-16": ["low", 0.4], "2026-11-17": ["low", 0.35],
  };
  const forecast = (input: DayInput) => {
    const [probability, score] = levels[input.date.toISOString().slice(0, 10)];
    return Promise.resolve(result({ top1: species({ probability, score }), alternative: null }));
  };
  const { json } = await run(db(), req("POST", URL_, body({ date: "2026-11-13" })), { pro: true, forecast });
  const a = json.data;
  assertEquals(a.horizon_days, 7);
  assertEquals(a.locked_days, []);
  assertEquals(a.locked_label, null);
  assertEquals(a.days.map((d: { level: string }) => d.level), ["low", "medium", "high", "high", "medium", "low", "low"]);
  assertEquals(a.days.map((d: { approximate: boolean }) => d.approximate), [false, false, false, false, true, true, true]);
  assert(a.days[4].approximate_label.startsWith("Орієнтовно"));
  // верхній рівень — обраний день
  assertEquals([a.date, a.top1.level], ["2026-11-13", "high"]);
  assertEquals(a.best_day, { date: "2026-11-14", label: "Найкращий день: субота" });
  assertEquals(/score|probability|0\.86|%/.test(JSON.stringify(json)), false);
});

Deno.test("analysis POST: усі дні низькі → найкращого дня немає", async () => {
  const forecast = () => Promise.resolve(result({ top1: species({ probability: "low", score: 0.4 }), alternative: null }));
  const { json } = await run(db(), req("POST", URL_, body()), { forecast });
  assertEquals(json.data.best_day, null);
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
  assertEquals((await run(db(), req("PATCH", URL_))).res.status, 405);
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

// ─── PUT: уточнення лісу вручну (ADR-015 §15.6) ────────────────────────────

const FOREST_URL = `${URL_}/areas/${AREA}/forest`;
const SATELLITE_HINT = {
  forest_km2: 18,
  types: [{ forest_type: "coniferous", km2: 16 }, { forest_type: "deciduous", km2: 1.3 }, { forest_type: "mixed", km2: 0.4 }],
};
const savedArea = (o: Record<string, unknown> = {}) => ({
  "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB, ...o }], error: null },
});

Deno.test("analysis PUT forest: породи замість типів з карти → переаналіз для них, без списання ліміту аналізів", async () => {
  const d = db({ ...savedArea(), "rpc.analysis_used_today": { data: 2, error: null } });
  const override = {
    types: [{ forest_type: "coniferous", species: ["pine", "spruce"] }],
    extra: [{ species: "oak", presence: "present" }],
  };
  const { res, json, inputs } = await run(d, req("PUT", FOREST_URL, { override, forest: SATELLITE_HINT }));
  assertEquals(res.status, 200);
  // хвойний (16 км²) ділиться між сосною і ялиною; «дуб — є місцями» — після; до 3 порід
  assertEquals(inputs.map((i) => i.forestType), ["pine", "spruce", "deciduous"]);
  const f = json.data.forest;
  assertEquals(f.refined, true);
  assertEquals(f.types[0].species, ["pine", "spruce"]);
  assertEquals(f.types[0].species_label, "сосна, ялина · уточнено вами");
  assertEquals(f.types[1].species_label, null);
  assertEquals(f.extra, [{ species: "oak", label: "Дуб", presence: "present", presence_label: "є місцями · уточнено вами" }]);
  assert(f.refine_note_label.includes("тук-тук"));
  // ліміт аналізів не списано; уточнень — 1 з 2
  assertEquals(find(d, "rpc.consume_analysis"), undefined);
  assertEquals(json.data.usage, { used: 2, limit: 5, label: "Сьогодні: 2 з 5 аналізів" });
  assertEquals(json.data.forest_edit, { used: 1, limit: 2, can_edit: true, label: "Уточнити ліс сьогодні можна ще 1 раз" });
  assertEquals(find(d, "rpc.consume_forest_edit")!.args[0], { p_user_id: USER, p_area_id: AREA, p_limit: 2 });
  // уточнення і результат зберігаються разом з ділянкою
  const saved = find(d, "rpc.save_forest_override")!.args[0] as Record<string, unknown>;
  assertEquals([saved.p_user_id, saved.p_area_id, saved.p_override], [USER, AREA, override]);
  assertEquals((saved.p_result as { forest: { refined: boolean } }).forest.refined, true);
});

Deno.test("analysis PUT forest: «переважає» — першою; null — скинути до карти", async () => {
  const d = db(savedArea());
  const { json, inputs } = await run(d, req("PUT", FOREST_URL, {
    override: { types: [], extra: [{ species: "birch", presence: "dominant" }] },
    forest: SATELLITE_HINT,
  }));
  assertEquals(inputs.map((i) => i.forestType), ["birch", "coniferous", "deciduous"]);
  assertEquals(json.data.forest.extra[0].presence_label, "переважає · уточнено вами");

  const reset = db(savedArea({ forest_override: { types: [{ forest_type: "coniferous", species: ["pine"] }], extra: [] } }));
  const r2 = await run(reset, req("PUT", FOREST_URL, { override: null, forest: SATELLITE_HINT }));
  assertEquals(r2.res.status, 200);
  assertEquals(r2.inputs.map((i) => i.forestType), ["coniferous", "deciduous"]);
  assertEquals(r2.json.data.forest.refined, false);
  assertEquals((find(reset, "rpc.save_forest_override")!.args[0] as Record<string, unknown>).p_override, null);
});

Deno.test("analysis PUT forest: третє уточнення за добу → 429, без розрахунку", async () => {
  const d = db({ ...savedArea(), "rpc.consume_forest_edit": { data: null, error: null } });
  const { res, json, inputs } = await run(d, req("PUT", FOREST_URL, {
    override: { types: [{ forest_type: "coniferous", species: ["pine"] }] },
  }));
  assertEquals([res.status, json.error], [429, "forest_edit_limit_reached"]);
  assert(Number(res.headers.get("Retry-After")) > 0);
  assertEquals(inputs.length, 0);
  assertEquals(find(d, "rpc.save_forest_override"), undefined);
});

Deno.test("analysis PUT forest: лише породи зі списку, 1–2 на тип; некоректне → 422 без списання", async () => {
  for (const override of [
    { types: [{ forest_type: "coniferous", species: ["palm"] }] },
    { types: [{ forest_type: "coniferous", species: ["pine", "spruce", "oak"] }] },
    { types: [{ forest_type: "coniferous", species: [] }] },
    { types: [{ forest_type: "coniferous", species: ["pine", "pine"] }] },
    { types: [{ forest_type: "coniferous", species: ["pine"] }, { forest_type: "coniferous", species: ["spruce"] }] },
    { extra: [{ species: "oak", presence: "everywhere" }] },
    { types: [], extra: [] },
    "сосна",
  ]) {
    const d = db(savedArea());
    const { res, json } = await run(d, req("PUT", FOREST_URL, { override }));
    assertEquals([res.status, json.error], [422, "validation_error"], JSON.stringify(override));
    assertEquals(find(d, "rpc.consume_forest_edit"), undefined);
  }
  const missing = await run(db(savedArea()), req("PUT", FOREST_URL, { forest: SATELLITE_HINT }));
  assertEquals(missing.res.status, 422);
});

Deno.test("analysis PUT forest: чужа ділянка → 404; розрахунок упав → 500 і уточнення повернуто", async () => {
  const gone = await run(db(), req("PUT", FOREST_URL, { override: null }));
  assertEquals([gone.res.status, gone.json.error], [404, "not_found"]);

  const d = db(savedArea());
  const { res } = await run(d, req("PUT", FOREST_URL, { override: null }), {
    forecast: () => Promise.reject(new Error("engine exploded")),
  });
  assertEquals(res.status, 500);
  assertEquals(find(d, "rpc.refund_forest_edit")!.args[0], { p_user_id: USER, p_area_id: AREA });
});

Deno.test("analysis POST area_id: збережене уточнення діє і на повторний аналіз", async () => {
  const d = db(savedArea({ forest_override: { types: [{ forest_type: "coniferous", species: ["pine"] }], extra: [] } }));
  const { json, inputs } = await run(d, req("POST", URL_, { area_id: AREA, forest: SATELLITE_HINT }));
  assertEquals(inputs.map((i) => i.forestType), ["pine", "deciduous", "mixed"]);
  assertEquals(json.data.forest.types[0].species_label, "сосна · уточнено вами");
});

Deno.test("analysis POST: кошик мінікарти — усі види зі шансом за день, найкращий рівень серед лісів, від кращого", async () => {
  const forecast = (input: DayInput) => {
    const c = input.forestType === "pine"
      ? [species({ score: 0.9, probability: "peak" }), species({ mushroom_type: "suillus_luteus", name_ua: "Маслюк", score: 0.45, probability: "low" })]
      : [species({ score: 0.6, probability: "medium" }), species({ mushroom_type: "russula_vesca", name_ua: "Сироїжка", score: 0.7, probability: "high" })];
    return Promise.resolve(result({ candidates: c }));
  };
  const { json } = await run(db(), req("POST", URL_, body()), { forecast });
  const basket = json.data.basket as Array<{ mushroom_type: string; level: string }>;
  assertEquals(basket.map((b) => [b.mushroom_type, b.level]), [
    ["boletus_edulis", "peak"], ["russula_vesca", "high"], ["suillus_luteus", "low"],
  ]);
  assertEquals(json.data.days[0].basket, json.data.basket);
  assertEquals(Object.keys(basket[0]).sort(), ["level", "level_color", "level_label", "mushroom_type", "name_ua", "when_label"]);
  assertEquals(/score|probability|0\.9/.test(JSON.stringify(json.data.basket)), false);
});

Deno.test("analysis POST: анімація тижня — Pro або «Слідопит» (рейтинг ≥ 51), інакше пояснення", async () => {
  const free = await run(db(), req("POST", URL_, body()));
  assertEquals(free.json.data.week_animation, { allowed: false, locked_label: "Анімація тижня — у Pro або з рівня «Слідопит»" });
  const pro = await run(db(), req("POST", URL_, body()), { pro: true });
  assertEquals(pro.json.data.week_animation, { allowed: true, locked_label: null });
  const tracker = await run(db({ "users.select": { data: { home_region_id: 10, rating: 51 }, error: null } }), req("POST", URL_, body()));
  assertEquals(tracker.json.data.week_animation.allowed, true);
});

// ─── PUT: назва ділянки (ADR-015 §15.9) ────────────────────────────────────

const AREA_URL = `${URL_}/areas/${AREA}`;

Deno.test("analysis PUT area: назва ділянки — обрізана, до 24 символів; у Pro порожні клітинки «Нова ділянка»", async () => {
  const d = db({ "analysis_areas.update": { data: { id: AREA, slot: 1 }, error: null } });
  const { res, json } = await run(d, req("PUT", AREA_URL, { label: "  Біля   Броників \n" }));
  assertEquals(res.status, 200);
  assertEquals(json.data, { id: AREA, label: "Біля Броників", title: "Біля Броників" });
  const upd = find(d, "analysis_areas.update")!;
  assertEquals(upd.args[0], { label: "Біля Броників" });
  assertEquals(upd.filters, [["id", AREA], ["user_id", USER]]);
  // ліміт аналізів не чіпаємо
  assertEquals(find(d, "rpc.consume_analysis"), undefined);

  // порожня або null — повернути «Ділянка N»
  for (const label of ["   ", null]) {
    const r = await run(db({ "analysis_areas.update": { data: { id: AREA, slot: 2 }, error: null } }), req("PUT", AREA_URL, { label }));
    assertEquals(r.json.data, { id: AREA, label: null, title: "Ділянка 2" });
  }

  // назва з overview: власна назва в title; у Pro вільні клітинки — «Нова ділянка»
  const g = await run(db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 2, size_km: 10, center: EWKB, label: "Дача" }], error: null },
  }), req("GET", URL_), { pro: true });
  assertEquals([g.json.data.areas[0].label, g.json.data.areas[0].title], ["Дача", "Дача"]);
  assertEquals(g.json.data.slots.map((s: { state: string; title: string }) => `${s.state}:${s.title}`), [
    "empty:Нова ділянка", "area:Дача", "empty:Нова ділянка",
  ]);
  assertEquals(g.json.data.slots[1].subtitle, "10×10 км");
});

Deno.test("analysis PUT area: задовга або не рядок → 422; чужа ділянка → 404", async () => {
  for (const body of [{ label: "а".repeat(25) }, { label: 5 }, {}, "назва"]) {
    const d = db({ "analysis_areas.update": { data: { id: AREA, slot: 1 }, error: null } });
    const { res, json } = await run(d, req("PUT", AREA_URL, body));
    assertEquals([res.status, json.error], [422, "validation_error"], JSON.stringify(body));
    assertEquals(find(d, "analysis_areas.update"), undefined);
  }
  // рівно 24 символи (з емодзі як одним символом) — можна
  const ok24 = await run(db({ "analysis_areas.update": { data: { id: AREA, slot: 1 }, error: null } }),
    req("PUT", AREA_URL, { label: "🍄" + "б".repeat(23) }));
  assertEquals(ok24.res.status, 200);

  const none = await run(db(), req("PUT", AREA_URL, { label: "Ліс" }));
  assertEquals([none.res.status, none.json.error], [404, "not_found"]);
  const bad = await run(db(), req("PUT", `${URL_}/areas/not-a-uuid`, { label: "Ліс" }));
  assertEquals(bad.res.status, 404);
});

// ─── Щоденне безкоштовне оновлення, «інші гриби сезону», «як відрізнити» один раз ─────────

Deno.test("analysis POST refresh=daily: раз на добу без списання; вдруге — 409 already_fresh", async () => {
  const yesterday = "2026-11-10T18:00:00Z"; // NOW — 2026-11-11 12:00 за Києвом
  const d = db({
    "analysis_areas.select": {
      data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB, last_analyzed_at: yesterday, last_result: { result_version: 3 } }],
      error: null,
    },
    "rpc.analysis_used_today": { data: 5, error: null },
  });
  const { res, json } = await run(d, req("POST", URL_, { area_id: AREA, refresh: "daily" }));
  assertEquals(res.status, 200);
  assertEquals(find(d, "rpc.consume_analysis"), undefined); // ліміт не витрачено
  assertEquals(json.data.usage.used, 5); // навіть коли ліміт вичерпано
  assertEquals(json.data.result_version, 3);

  // сьогодні вже оновлено і версія свіжа → 409
  const fresh = db({
    "analysis_areas.select": {
      data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB, last_analyzed_at: "2026-11-11T07:00:00Z", last_result: { result_version: 3 } }],
      error: null,
    },
  });
  const r2 = await run(fresh, req("POST", URL_, { area_id: AREA, refresh: "daily" }));
  assertEquals([r2.res.status, r2.json.error], [409, "already_fresh"]);

  // сьогодні оновлено, але результат старої версії (до оновлення застосунку) → знову безкоштовно
  const old = db({
    "analysis_areas.select": {
      data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB, last_analyzed_at: "2026-11-11T07:00:00Z", last_result: { result_version: 1 } }],
      error: null,
    },
  });
  const r3 = await run(old, req("POST", URL_, { area_id: AREA, refresh: "daily" }));
  assertEquals(r3.res.status, 200);
  assertEquals(find(old, "rpc.consume_analysis"), undefined);

  const bad = await run(db(), req("POST", URL_, { area_id: AREA, refresh: "always" }));
  assertEquals(bad.res.status, 422);
});

Deno.test("analysis POST: «інші гриби сезону» з причиною; «як відрізнити» — один раз у result.identify", async () => {
  const cold = { ...species({ mushroom_type: "boletus_edulis", name_ua: "Білий гриб", probability: "no_data", score: 0 }), missed: ["temp 3.4 < min 10"] };
  const forest = { ...species({ mushroom_type: "suillus_bovinus", name_ua: "Козляк", probability: "no_data", score: 0 }), missed: ["forest mismatch: need pine, got oak"] };
  const flam = species({ mushroom_type: "flammulina_velutipes", name_ua: "Зимовий опеньок", probability: "high" });
  const forecast = () => Promise.resolve(result({
    top1: flam, alternative: null, candidates: [flam], others: [cold, forest],
  }));
  const { json } = await run(db(), req("POST", URL_, body()), { forecast });
  assertEquals(json.data.others, [
    { mushroom_type: "boletus_edulis", name_ua: "Білий гриб", reason_label: "Холодно: 3° за тиждень, потрібно від 10°" },
    { mushroom_type: "suillus_bovinus", name_ua: "Козляк", reason_label: "У лісах ділянки немає його дерев (сосна)" },
  ]);
  assertEquals(json.data.days[0].others.length, 2);
  // identify — не в кожному виді, а один раз на результат
  assertEquals(json.data.top1.identify, undefined);
  assertEquals(Object.keys(json.data.identify), ["flammulina_velutipes"]);
});

Deno.test("analysis POST: знахідки — прогноз дня в історію, звірка тук-туків, торішні знахідки", async () => {
  const flam = species({ mushroom_type: "flammulina_velutipes", name_ua: "Зимовий опеньок", probability: "high" });
  const forecast = () => Promise.resolve(result({ top1: flam, alternative: null, candidates: [flam] }));
  const d = db({
    "rpc.area_finds": (call) => {
      const p = call.args[0] as { p_from: string };
      return p.p_from.startsWith("2025")
        ? { data: [{ lat: 50.41, lng: 30.51, species_id: "flammulina_velutipes", name_ua: "Зимовий опеньок", day: "2025-11-12", matched: null }], error: null }
        : {
          data: [
            { lat: 50.41, lng: 30.51, species_id: "flammulina_velutipes", name_ua: "Зимовий опеньок", day: "2026-11-09", matched: true },
            { lat: 50.42, lng: 30.52, species_id: "pleurotus_ostreatus", name_ua: "Глива", day: "2026-11-08", matched: false },
            { lat: 50.42, lng: 30.52, species_id: "boletus_edulis", name_ua: "Білий гриб", day: "2026-09-20", matched: null },
          ],
          error: null,
        };
    },
  });
  const { json } = await run(d, req("POST", URL_, body()), { forecast });
  // прогноз сьогоднішнього дня збережено
  const hist = find(d, "rpc.save_analysis_history")!.args[0] as Record<string, unknown>;
  assertEquals([hist.p_user_id, hist.p_day, hist.p_species], [USER, "2026-11-11", ["flammulina_velutipes"]]);
  const f = json.data.finds;
  assertEquals(f.verification, { matched: 1, total: 2 }); // без прогнозу на той день — не рахується
  assertEquals(f.verification_label, "Ваші знахідки тут збіглися з прогнозом: 1 з 2");
  assertEquals(f.last_year, [{ lat: 50.41, lng: 30.51, mushroom_type: "flammulina_velutipes", name: "Зимовий опеньок", date_label: "12.11.2025" }]);
  assertEquals(f.last_year_label, "Торік у ці тижні: 1 знахідка");
  // торішнє вікно — навколо цих самих тижнів
  const calls = d.calls.filter((c) => c.key === "rpc.area_finds").map((c) => c.args[0] as { p_from: string; p_to: string });
  assertEquals([calls[0].p_from, calls[0].p_to], ["2026-09-12", "2026-11-11"]); // 60 днів назад
  assertEquals([calls[1].p_from, calls[1].p_to], ["2025-11-04", "2025-11-21"]);
});

Deno.test("analysis POST: рельєф і ґрунт — один раз на ділянку, у рушій і підпис у блоці лісу", async () => {
  const inputs: Array<{ terrain?: unknown }> = [];
  const forecast = (input: { terrain?: unknown }) => {
    inputs.push(input);
    return Promise.resolve(result());
  };
  let fetched = 0;
  const terrain = () => {
    fetched++;
    return Promise.resolve({ elevation: 160, relief: "valley" as const, reliefRange: 24, sand: 78, clay: 6, soil: "sandy" as const, fetchedAt: "x" });
  };
  const d = db();
  const { json } = await run(d, req("POST", URL_, body()), { forecast: forecast as never, deps: { terrain } });
  assertEquals(fetched, 1);
  assertEquals((inputs[0].terrain as { soil: string }).soil, "sandy");
  assertEquals((find(d, "rpc.save_area_terrain")!.args[0] as { p_terrain: { relief: string } }).p_terrain.relief, "valley");
  assertEquals(json.data.forest.terrain_label,
    "Рельєф: низина — вологіше й прохолодніше, вранці заморозки · Ґрунт: піщаний — після дощу пересихає швидше");

  // збережений рельєф — без нового запиту
  const d2 = db({
    "analysis_areas.select": { data: [{ id: AREA, slot: 1, size_km: 5, center: EWKB, terrain: { relief: "hill", soil: null } }], error: null },
    "rpc.consume_analysis": { data: 1, error: null },
  });
  fetched = 0;
  const r2 = await run(d2, req("POST", URL_, { area_id: AREA }), { forecast: forecast as never, deps: { terrain } });
  assertEquals(fetched, 0);
  assertEquals(r2.json.data.forest.terrain_label, "Рельєф: підвищення — сухіше, ґрунт прогрівається краще");
});

Deno.test("analysis POST (Pro): дні 5–7 — діапазон погоди за кількома моделями", async () => {
  const forecast = (input: DayInput) => {
    const date = input.date.toISOString().slice(0, 10);
    const weather = {
      tempMin: 1, tempMax: 8, tempAvg7d: 4, humidity: 85, rain1d: 0, rain3d: 2, rain7d: 5, rain14d: 10,
      droughtDays: 0, daysAfterRain: 2, pressure: 1012, pressureTrend: "stable", source: "open-meteo",
      day: { date, tempMin: 1, tempMax: 8, rain: 0, humidity: 80, daysAhead: 0 },
    };
    return Promise.resolve(result({ weather: weather as unknown as ForecastResult["weather"] }));
  };
  let called = 0;
  const ensemble = () => {
    called++;
    return Promise.resolve({ "2026-11-16": { rainMin: 2, rainMax: 11, tMin: 3, tMax: 10 } });
  };
  const { json } = await run(db(), req("POST", URL_, body()), { forecast, pro: true, deps: { ensemble } });
  assertEquals(called, 1);
  const days = json.data.days as Array<{ date: string; weather: { range_label: string | null } }>;
  assertEquals(days.find((d) => d.date === "2026-11-16")!.weather.range_label, "Різні моделі: опади 2–11 мм, 3…10°");
  assertEquals(days[0].weather.range_label, null); // близькі дні — без діапазону
  // безкоштовно (3 дні) ансамбль не запитується
  called = 0;
  await run(db(), req("POST", URL_, body()), { forecast, deps: { ensemble } });
  assertEquals(called, 0);
});

Deno.test("analysis PUT push: пристрій для сповіщень про хвилі; доступ — Pro або «Слідопит»", async () => {
  const d = db({ "users.select": { data: { home_region_id: 10, rating: 12 }, error: null } });
  const token = "fcm-token-" + "x".repeat(30);
  const { res, json } = await run(d, req("PUT", `${URL_}/push`, { token, platform: "android" }));
  assertEquals(res.status, 200);
  assertEquals(json.data, { registered: true, wave_alerts: true, allowed: false, locked_label: "Сповіщення про хвилі — у Pro або з рівня «Слідопит»" });
  assertEquals(find(d, "rpc.register_push_device")!.args[0], { p_user_id: USER, p_token: token, p_platform: "android", p_wave_alerts: true });
  const bad = await run(db(), req("PUT", `${URL_}/push`, { token: "short", platform: "android" }));
  assertEquals(bad.res.status, 422);
  const pro = await run(db(), req("PUT", `${URL_}/push`, { token, platform: "ios", wave_alerts: false }), { pro: true });
  assertEquals([pro.json.data.allowed, pro.json.data.wave_alerts], [true, false]);
});
