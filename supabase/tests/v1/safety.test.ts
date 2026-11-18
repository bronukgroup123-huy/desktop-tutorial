import { assert, assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { handleAppConfig } from "../../functions/_shared/v1/app-config.ts";
import { DEFAULT_SAFETY_CONTENT, mergeSafetyContent } from "../../functions/_shared/v1/safety-content.ts";
import {
  _resetAirAlertsCache,
  ALERTS_URL,
  handleAirAlerts,
  oblastSlug,
  parseAlerts,
} from "../../functions/_shared/v1/air-alerts.ts";
import { dayHazards } from "../../functions/_shared/v1/weather-hours.ts";
import type { DayWeather } from "../../functions/_shared/forecast/types.ts";
import { mockDb, RL_BLOCKED, RL_OK } from "./mock-db.ts";

// ─── v1-app-config ─────────────────────────────────────────────────────────

const config = (db: ReturnType<typeof mockDb>, headers: Record<string, string> = {}) =>
  // deno-lint-ignore no-explicit-any
  handle((r) => handleAppConfig(r, { db: db as any }))(new Request("http://localhost/v1-app-config", { headers }));

Deno.test("v1-app-config: типові тексти безпеки (банер ДСНС, «Заблукали?», «Отруєння», чек-лист), ETag → 304", async () => {
  const db = mockDb(RL_OK);
  const res = await config(db);
  assertEquals(res.status, 200);
  const safety = (await res.json()).data.safety;
  assertEquals(safety.notices[0].id, "mines");
  assert(safety.notices[0].link_url.startsWith("https://dsns.gov.ua"));
  assertEquals(safety.guides.map((g: { id: string }) => g.id), ["lost", "poisoning", "dangers"]);
  assert(safety.checklist.length >= 6);
  assertEquals(safety.air_alert.tips.length, 3);
  const etag = res.headers.get("ETag")!;
  const again = await config(db, { "If-None-Match": etag });
  assertEquals(again.status, 304);
});

Deno.test("v1-app-config: банери з feature_flags перекривають типові; вимкнений прапорець і збій БД — типові", async () => {
  const notices = [{ id: "fire", title: "Пожежна небезпека", body: "Не розпалюйте вогнище.", link_url: "http://bad", severity: "warning" }];
  const db = mockDb({
    ...RL_OK,
    "feature_flags.select": { data: [{ key: "safety_notices", enabled: true, value: notices }], error: null },
  });
  const safety = (await (await config(db)).json()).data.safety;
  assertEquals(safety.notices, [{ id: "fire", title: "Пожежна небезпека", body: "Не розпалюйте вогнище.", link_label: null, link_url: null, severity: "warning" }]);
  assertEquals(safety.guides.length, 3);

  const off = mockDb({ ...RL_OK, "feature_flags.select": { data: [{ key: "safety_notices", enabled: false, value: [] }], error: null } });
  assertEquals((await (await config(off)).json()).data.safety.notices[0].id, "mines");
  const broken = mockDb({ ...RL_OK, "feature_flags.select": { data: null, error: { message: "boom" } } });
  assertEquals((await config(broken)).status, 200);
  assertEquals((await config(mockDb(RL_BLOCKED))).status, 429);
});

Deno.test("Тексти безпеки: застосунок вбудовує ті самі типові тексти (офлайн з першого запуску)", async () => {
  const asset = JSON.parse(await Deno.readTextFile(new URL("../../../flutter_client/assets/safety/safety_content.json", import.meta.url)));
  assertEquals(asset, DEFAULT_SAFETY_CONTENT);
  // Часткова заміна: некоректні частини ігноруються.
  const merged = mergeSafetyContent(null, { checklist: [{ id: "x" }], version: 2 });
  assertEquals([merged.version, merged.checklist.length], [2, DEFAULT_SAFETY_CONTENT.checklist.length]);
});

// ─── v1-air-alerts ─────────────────────────────────────────────────────────

const SAMPLE = {
  alerts: [
    { id: 1, location_title: "Житомирська область", location_type: "oblast", alert_type: "air_raid", location_oblast: "Житомирська область", finished_at: null },
    { id: 2, location_title: "Броварський район", location_type: "raion", alert_type: "air_raid", location_oblast: "Київська область", finished_at: null },
    { id: 3, location_title: "м. Київ", location_type: "city", alert_type: "air_raid", location_oblast: "м. Київ", finished_at: null },
    { id: 4, location_title: "Сумська область", location_type: "oblast", alert_type: "artillery_shelling", location_oblast: "Сумська область", finished_at: null },
    { id: 5, location_title: "Львівська область", location_type: "oblast", alert_type: "air_raid", location_oblast: "Львівська область", finished_at: "2026-11-17T10:00:00Z" },
  ],
};

Deno.test("Повітряна тривога: лише air_raid і активні; уся область важливіша за район; Київ — частина Київської", () => {
  assertEquals(parseAlerts(SAMPLE), [
    { slug: "kyivska", scope: "part", title: "Повітряна тривога: Броварський район, м. Київ" },
    { slug: "zhytomyrska", scope: "oblast", title: "Повітряна тривога в області" },
  ]);
  assertEquals(oblastSlug("Івано-Франківська область"), { slug: "ivano-frankivska", city: false });
  assertEquals(oblastSlug("Автономна Республіка Крим"), { slug: "krym", city: false });
  assertEquals(oblastSlug("Атлантида"), null);
  assertEquals(parseAlerts({ nope: 1 }), []);
});

/** Стан таблиці air_alerts_cache + RPC оренди — як у міграції 20261118120000. */
function alertsDb(clock: () => number) {
  const row: Record<string, unknown> = { regions: [], fetched_at: null, last_modified: null, refreshing_until: null, backoff_until: null };
  const ts = (v: unknown) => (typeof v === "string" ? Date.parse(v) : -Infinity);
  const db = mockDb({
    ...RL_OK,
    "air_alerts_cache.select": () => ({ data: { regions: row.regions, fetched_at: row.fetched_at, last_modified: row.last_modified }, error: null }),
    "air_alerts_cache.update": (call) => {
      Object.assign(row, call.args[0] as Record<string, unknown>);
      return { data: null, error: null };
    },
    "rpc.air_alerts_claim_refresh": (call) => {
      const { p_ttl_seconds, p_lease_seconds } = call.args[0] as { p_ttl_seconds: number; p_lease_seconds: number };
      const t = clock();
      const ok = ts(row.fetched_at) < t - p_ttl_seconds * 1000 && ts(row.refreshing_until) < t && ts(row.backoff_until) < t;
      if (ok) row.refreshing_until = new Date(t + p_lease_seconds * 1000).toISOString();
      return { data: ok, error: null };
    },
  });
  return { db, row };
}

Deno.test("v1-air-alerts: без ключа — available:false; один запит на всю Україну, кеш 45 с спільний для всіх копій функції", async () => {
  _resetAirAlertsCache();
  let t = 1_000_000;
  const { db, row } = alertsDb(() => t);
  const run = (deps: Partial<Parameters<typeof handleAirAlerts>[1]>, url = "http://localhost/v1-air-alerts") =>
    handle((r) => handleAirAlerts(r, { db, now: () => t, ...deps }))(new Request(url));
  assertEquals((await (await run({})).json()).data, { available: false, updated_at: null, regions: [] });

  const seen: Array<string | null | undefined> = [];
  const fetcher = (url: string, token: string, since?: string | null) => {
    seen.push(since);
    assertEquals([url, token], [ALERTS_URL, "secret"]);
    return Promise.resolve({ status: 200, body: SAMPLE, lastModified: "Wed, 18 Nov 2026 16:00:00 GMT" });
  };
  const body = (await (await run({ token: "secret", fetcher })).json()).data;
  assertEquals(body.available, true);
  assertEquals(body.regions.map((r: { slug: string }) => r.slug), ["kyivska", "zhytomyrska"]);
  assertEquals(row.last_modified, "Wed, 18 Nov 2026 16:00:00 GMT");

  // Інша копія функції (без кешу в пам'яті) бере дані зі спільного кешу — без запиту.
  _resetAirAlertsCache();
  t += 10_000;
  await run({ token: "secret", fetcher });
  assertEquals(seen.length, 1);

  // Лише своя область.
  const mine = (await (await run({ token: "secret", fetcher }, "http://localhost/v1-air-alerts?region=zhytomyrska")).json()).data;
  assertEquals(mine.regions.map((r: { slug: string }) => r.slug), ["zhytomyrska"]);
});

Deno.test("v1-air-alerts: оновлює лише одна копія; 304 — без змін; 429 — пауза й останні дані; давні дані — available:false", async () => {
  _resetAirAlertsCache();
  let t = 2_000_000;
  const { db, row } = alertsDb(() => t);
  const run = (fetcher: Parameters<typeof handleAirAlerts>[1]["fetcher"]) =>
    handle((r) => handleAirAlerts(r, { db, now: () => t, token: "secret", fetcher }))(new Request("http://localhost/v1-air-alerts"));
  let calls = 0;
  const ok200 = () => (calls++, Promise.resolve({ status: 200, body: SAMPLE, lastModified: "LM1" }));
  await run(ok200);
  assertEquals(calls, 1);

  // Кеш застарів, але оренду вже взяла інша копія — ця не йде до alerts.in.ua, віддає останні дані.
  t += 60_000;
  row.refreshing_until = new Date(t + 10_000).toISOString();
  _resetAirAlertsCache();
  const busy = (await (await run(ok200)).json()).data;
  assertEquals([calls, busy.available], [1, true]);
  row.refreshing_until = null;

  // 304 — If-Modified-Since зі спільного кешу, дані ті самі, час оновлено.
  let since: string | null | undefined;
  const not304 = (_u: string, _t: string, s?: string | null) => (calls++, since = s, Promise.resolve({ status: 304 }));
  const same = (await (await run(not304)).json()).data;
  assertEquals([since, same.regions.length, same.updated_at], ["LM1", 2, new Date(t).toISOString()]);

  // 429 — пауза (Retry-After), тим часом останні дані й жодних запитів.
  t += 60_000;
  _resetAirAlertsCache();
  const tooMany = () => (calls++, Promise.resolve({ status: 429, retryAfterS: 300 }));
  const paused = (await (await run(tooMany)).json()).data;
  assertEquals(paused.available, true);
  assertEquals(Date.parse(row.backoff_until as string), t + 300_000);
  const before = calls;
  t += 60_000;
  _resetAirAlertsCache();
  await run(ok200);
  assertEquals(calls, before); // пауза ще триває

  // Пауза минула, але джерело лежить, а дані давні (> 10 хв) — банера немає.
  t += 15 * 60_000;
  _resetAirAlertsCache();
  const down = (await (await run(() => Promise.reject(new Error("down")))).json()).data;
  assertEquals(down.available, false);
  assertEquals(row.refreshing_until, null); // оренду звільнено
});

// ─── Небезпечна погода ─────────────────────────────────────────────────────

Deno.test("Небезпечна погода: гроза з годинами (WMO 95–99), спека від 30°, мороз; спокійний день — нічого", () => {
  const h = Array.from({ length: 24 }, (_, i) => i);
  const day = (over: Partial<DayWeather>): DayWeather => ({
    date: "2026-07-20", tempMin: 14, tempMax: 24, rain: 0, humidity: 60, daysAhead: 0, code: 2,
    hours: { h, code: h.map(() => 2), rain: h.map(() => 0), temp: h.map(() => 20) }, ...over,
  });
  assertEquals(dayHazards(day({})), []);
  const storm = day({ tempMax: 32, hours: { h, code: h.map((x) => (x >= 15 && x < 18 ? 95 : 2)), rain: h.map(() => 0), temp: h.map(() => 25) } });
  assertEquals(dayHazards(storm), [
    "Гроза 15:00–18:00: не стійте під поодинокими високими деревами, на галявинах і пагорбах",
    "Спека до 32°: візьміть більше води й головний убір",
  ]);
  assertEquals(dayHazards(day({ hours: null, code: 96 }))[0].startsWith("Гроза протягом дня"), true);
  assertEquals(dayHazards(day({ tempMin: -4 })), ["Мороз до -4°: тепло вдягніться, візьміть рукавиці й гарячий чай"]);
});
