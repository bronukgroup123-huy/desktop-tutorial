import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import type { WeatherSeries } from "../../functions/_shared/forecast/weather.ts";
import {
  fetchWeatherCached,
  fetchWeatherSeriesCached,
  kyivDate,
  weatherCell,
} from "../../functions/_shared/forecast/weather-cache.ts";
import { mockDb } from "./mock-db.ts";

const NOW = new Date("2026-11-10T12:00:00Z");

/** Ряд: 3 минулі дні + сьогодні (2026-11-10) + 2 дні прогнозу. */
function series(today = "2026-11-10"): WeatherSeries {
  const dates = ["2026-11-07", "2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12"];
  const n = dates.length;
  return {
    version: 2,
    dates,
    today,
    precip: [0, 0, 12, 1, 30, 0],
    tmax: Array(n).fill(16),
    tmin: Array(n).fill(8),
    tmean: Array(n).fill(13),
    humidity: Array(n).fill(78),
    soil: Array(n).fill(0.3),
    pressureStart: Array(n).fill(1013),
    pressureEnd: Array(n).fill(1013),
    fetchedAt: NOW.toISOString(),
  };
}

function fetcherSpy(result: WeatherSeries | null = series()) {
  const calls: Array<[number, number]> = [];
  return { calls, fetch: (lat: number, lng: number) => { calls.push([lat, lng]); return Promise.resolve(result); } };
}

Deno.test("weather cell: сусідні точки — одна клітинка, запит для центру", () => {
  assertEquals(weatherCell(50.31, 28.66), { key: "50.35:28.65", lat: 50.35, lng: 28.65 });
  assertEquals(weatherCell(50.39, 28.61).key, "50.35:28.65");
  assertEquals(weatherCell(50.41, 28.66).key === "50.35:28.65", false);
});

Deno.test("kyivDate: доба за київським часом", () => {
  assertEquals(kyivDate(new Date("2026-11-10T21:30:00Z")), "2026-11-10");
  assertEquals(kyivDate(new Date("2026-11-10T22:30:00Z")), "2026-11-11");
});

Deno.test("weather cache: свіжий ряд того ж дня — без запиту до Open-Meteo, погода на сьогодні", async () => {
  const spy = fetcherSpy();
  const db = mockDb({ "weather_cache.select": { data: { payload: series(), fetched_at: "2026-11-10T10:30:00Z" }, error: null } });
  const w = await fetchWeatherCached(db, 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW });
  assertEquals(spy.calls.length, 0);
  assertEquals(w.source, "cached");
  assertEquals(w.rain1d, 1); // сьогодні, а не останній день прогнозу
  assertEquals(w.day?.date, "2026-11-10");
});

Deno.test("weather cache: застарілий ряд (> 3 год) → свіжий для центру клітинки + upsert", async () => {
  const spy = fetcherSpy();
  const db = mockDb({ "weather_cache.select": { data: { payload: series(), fetched_at: "2026-11-10T08:00:00Z" }, error: null } });
  const w = await fetchWeatherCached(db, 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW });
  assertEquals(spy.calls, [[50.35, 28.65]]);
  assertEquals(w.source, "open-meteo");
  const up = db.calls.find((c) => c.key === "weather_cache.upsert")!;
  assertEquals((up.args[0] as Record<string, unknown>).cell_key, "50.35:28.65");
});

Deno.test("weather cache: ряд іншого дня або старого формату → перезапит", async () => {
  for (const payload of [series("2026-11-09"), { tempAvg7d: 13, source: "open-meteo" }]) {
    const spy = fetcherSpy();
    const db = mockDb({ "weather_cache.select": { data: { payload, fetched_at: "2026-11-10T11:30:00Z" }, error: null } });
    const res = await fetchWeatherSeriesCached(db, 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW });
    assertEquals(spy.calls.length, 1);
    assertEquals(res.cached, false);
  }
});

Deno.test("weather cache: недоступна погода не кешується", async () => {
  const spy = fetcherSpy(null);
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

Deno.test("weather cache: день горизонту — з того самого ряду", async () => {
  const spy = fetcherSpy();
  const w = await fetchWeatherCached(mockDb(), 50.31, 28.66, { fetcher: spy.fetch, now: () => NOW }, "2026-11-11");
  assertEquals(w.rain1d, 30);
  assertEquals(w.day?.daysAhead, 1);
  assertEquals(spy.calls.length, 1);
});
