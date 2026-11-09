import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import type { WeatherData } from "../../functions/_shared/forecast/types.ts";
import { fetchWeatherCached, weatherCell } from "../../functions/_shared/forecast/weather-cache.ts";
import { mockDb } from "./mock-db.ts";

const NOW = new Date("2026-11-10T12:00:00Z");
const W = { tempAvg7d: 13, humidity: 78, source: "open-meteo" } as unknown as WeatherData;

function fetcherSpy(result: WeatherData = W) {
  const calls: Array<[number, number]> = [];
  return { calls, fetch: (lat: number, lng: number) => { calls.push([lat, lng]); return Promise.resolve(result); } };
}

Deno.test("weather cell: сусідні точки — одна клітинка, запит для центру", () => {
  assertEquals(weatherCell(50.31, 28.66), { key: "50.35:28.65", lat: 50.35, lng: 28.65 });
  assertEquals(weatherCell(50.39, 28.61).key, "50.35:28.65");
  assertEquals(weatherCell(50.41, 28.66).key === "50.35:28.65", false);
});

Deno.test("weather cache: свіжий запис — без запиту до Open-Meteo", async () => {
  const spy = fetcherSpy();
  const db = mockDb({ "weather_cache.select": { data: { payload: W, fetched_at: "2026-11-10T10:30:00Z" }, error: null } });
  const w = await fetchWeatherCached(db, 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW });
  assertEquals(spy.calls.length, 0);
  assertEquals(w.source, "cached");
  assertEquals(w.tempAvg7d, 13);
});

Deno.test("weather cache: застарілий запис (> 3 год) → свіжа погода для центру клітинки + upsert", async () => {
  const spy = fetcherSpy();
  const db = mockDb({ "weather_cache.select": { data: { payload: W, fetched_at: "2026-11-10T08:00:00Z" }, error: null } });
  const w = await fetchWeatherCached(db, 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW });
  assertEquals(spy.calls, [[50.35, 28.65]]);
  assertEquals(w.source, "open-meteo");
  const up = db.calls.find((c) => c.key === "weather_cache.upsert")!;
  assertEquals((up.args[0] as Record<string, unknown>).cell_key, "50.35:28.65");
});

Deno.test("weather cache: недоступна погода не кешується", async () => {
  const spy = fetcherSpy({ ...W, source: "unavailable" });
  const db = mockDb();
  const w = await fetchWeatherCached(db, 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW });
  assertEquals(w.source, "unavailable");
  assertEquals(db.calls.some((c) => c.key === "weather_cache.upsert"), false);
});

Deno.test("weather cache: помилка БД → все одно повертає погоду", async () => {
  const spy = fetcherSpy();
  const broken = { from() { throw new Error("no table"); } };
  const w = await fetchWeatherCached(broken, 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW });
  assertEquals(w.tempAvg7d, 13);
  assertEquals(spy.calls.length, 1);
});
