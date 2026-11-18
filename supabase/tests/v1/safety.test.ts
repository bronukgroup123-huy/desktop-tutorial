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

Deno.test("v1-air-alerts: без ключа — available:false; з ключем — області з кешем 45 с; збій джерела — без помилки", async () => {
  _resetAirAlertsCache();
  const run = (deps: Partial<Parameters<typeof handleAirAlerts>[1]>) =>
    handle((r) => handleAirAlerts(r, { db: mockDb(RL_OK), ...deps }))(new Request("http://localhost/v1-air-alerts"));
  assertEquals((await (await run({})).json()).data, { available: false, updated_at: null, regions: [] });

  let calls = 0;
  let t = 1_000_000;
  const fetcher = (url: string, token: string) => {
    calls++;
    assertEquals([url, token], [ALERTS_URL, "secret"]);
    return Promise.resolve(SAMPLE);
  };
  const body = (await (await run({ token: "secret", fetcher, now: () => t })).json()).data;
  assertEquals(body.available, true);
  assertEquals(body.regions.map((r: { slug: string }) => r.slug), ["kyivska", "zhytomyrska"]);
  t += 10_000;
  await run({ token: "secret", fetcher, now: () => t });
  assertEquals(calls, 1); // кеш
  t += 60_000;
  const failing = () => Promise.reject(new Error("down"));
  const stale = (await (await run({ token: "secret", fetcher: failing, now: () => t })).json()).data;
  assertEquals(stale.available, true); // недавні дані лишаються
  _resetAirAlertsCache();
  const none = (await (await run({ token: "secret", fetcher: failing, now: () => t })).json()).data;
  assertEquals(none.available, false);
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
