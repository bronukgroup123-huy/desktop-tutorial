import { assert, assertEquals } from "jsr:@std/assert";
import { dayParts, rainSpans, restOfDay } from "../../functions/_shared/v1/weather-hours.ts";
import { weatherInsight } from "../../functions/_shared/v1/weather-insight.ts";
import { mergeWeather, weatherRefreshAllowed } from "../../functions/_shared/v1/analysis.ts";
import type { DayWeather, WeatherData } from "../../functions/_shared/forecast/types.ts";

/** Доба: сонце вдень, дощ 18:00–21:00 (по 1,5 мм), мряка о 06:00 без мм. */
function sunnyThenRain(date = "2026-11-17"): DayWeather {
  const h = Array.from({ length: 24 }, (_, i) => i);
  return {
    date, tempMin: 4, tempMax: 11, rain: 4.5, humidity: 80, daysAhead: 0, code: 61,
    hours: {
      h,
      code: h.map((x) => (x >= 18 && x < 21 ? 61 : x === 6 ? 51 : x >= 10 && x < 16 ? 0 : 2)),
      rain: h.map((x) => (x >= 18 && x < 21 ? 1.5 : 0)),
      temp: h.map((x) => (x >= 10 && x < 16 ? 11 : 5)),
    },
  };
}

const W = {
  tempAvg7d: 6, tempAvg14d: 6, tempAvg20d: 6, tempMin: 0, tempMax: 11, humidity: 80,
  rain1d: 4.5, rain2d: 5, rain3d: 5, rain7d: 9, rain14d: 23, rain30d: 40, droughtDays: 0, daysAfterRain: 4,
  pressure: 1015, pressureTrend: "stable", soilState: "normal", gdd: 10, source: "open-meteo",
} as unknown as WeatherData;

Deno.test("Частини доби: удень сонце, увечері дощ — а не «Дощ» на весь день", () => {
  const parts = dayParts(sunnyThenRain(), W);
  assertEquals(parts.map((p) => p.key), ["night", "morning", "day", "evening"]);
  const day = parts.find((p) => p.key === "day")!;
  assertEquals([day.scene, day.from_hour, day.to_hour], ["sunny", 12, 18]);
  const evening = parts.find((p) => p.key === "evening")!;
  assertEquals([evening.scene, evening.scene_label, evening.temp_label], ["rain", "Дощ", "5°"]);
  assertEquals(dayParts({ ...sunnyThenRain(), hours: null }, W), []);
});

Deno.test("Проміжки опадів: «Мряка 06:00–07:00», «Дощ 18:00–21:00, ~5 мм»; решта дня", () => {
  const spans = rainSpans(sunnyThenRain());
  assertEquals(spans.map((s) => s.label), ["Мряка 06:00–07:00", "Дощ 18:00–21:00, ~5 мм"]);
  assertEquals([spans[1].from_hour, spans[1].to_hour, spans[1].mm], [18, 21, 4.5]);
  assertEquals(restOfDay(sunnyThenRain(), 14), { mm: 4.5, wet: true });
  assertEquals(restOfDay(sunnyThenRain(), 21), { mm: 0, wet: false });
});

const res = (day: DayWeather) => ({ weather: { ...W, day, recent: [day] } });
const label = (d: string) => (d === "2026-11-17" ? "Сьогодні" : d === "2026-11-18" ? "Завтра" : "Чт 19");
const dry = (date: string): DayWeather => ({ date, tempMin: 2, tempMax: 8, rain: 0, humidity: 75, daysAhead: 1, code: 3 });

Deno.test("Що далі: вечірній дощ сьогодні — не «Без дощу до чт»", () => {
  // deno-lint-ignore no-explicit-any
  const runs = [res(sunnyThenRain()), res(dry("2026-11-18")), res(dry("2026-11-19"))] as any;
  const at14 = weatherInsight(runs, "2026-11-17", null, label, 14)!;
  assertEquals(at14.outlook_label, "Сьогодні — невеликий дощ 5 мм: ґрунт не встигне пересохнути");
  // Після дощу — справді без дощу до четверга.
  const at22 = weatherInsight(runs, "2026-11-17", null, label, 22)!;
  assertEquals(at22.outlook_label, "Без дощу до чт 19 — ґрунт підсихатиме");
});

Deno.test("Що далі: мряка за кодом погоди (менше 1 мм) — «лише мряка», а не «без дощу»", () => {
  const drizzle = { ...dry("2026-11-18"), rain: 0.2, code: 53 };
  // deno-lint-ignore no-explicit-any
  const runs = [res({ ...dry("2026-11-17"), daysAhead: 0 }), res(drizzle), res(dry("2026-11-19"))] as any;
  assertEquals(weatherInsight(runs, "2026-11-17", null, label, 9)!.outlook_label, "Завтра — лише мряка, ґрунт підсихатиме");
});

Deno.test("Оновлення погоди: раз на 3 години; гриби, кошик і вікно хвилі лишаються", () => {
  const now = new Date("2026-11-17T12:00:00Z");
  assert(!weatherRefreshAllowed({ last_result: { weather_as_of: "2026-11-17T10:30:00Z" } }, now));
  assert(weatherRefreshAllowed({ last_result: { weather_as_of: "2026-11-17T08:59:00Z" } }, now));
  assert(weatherRefreshAllowed({ last_result: {}, last_analyzed_at: "2026-11-17T08:00:00Z" }, now));
  const stored = {
    date: "2026-11-17",
    top1: { mushroom_type: "flammulina_velutipes" },
    days: [
      { date: "2026-11-17", level: "high", basket: [1], weather: { scene: "rain", sprouts: "many" } },
      { date: "2026-11-18", level: "medium", weather: { scene: "cloudy", sprouts: "few" } },
    ],
    weather: { scene: "rain", sprouts: "many" },
    weather_insight: { wave: { label: "хвиля" }, outlook_label: "старе" },
  };
  const fresh = {
    days: [
      { date: "2026-11-17", level: "low", weather: { scene: "sunny", sprouts: "none", parts: [1] } },
      { date: "2026-11-18", level: "low", weather: { scene: "rain", sprouts: "none" } },
    ],
    weather_insight: { wave: null, outlook_label: "нове" },
  };
  // deno-lint-ignore no-explicit-any
  const m = mergeWeather(stored, fresh, now) as Record<string, any>;
  assertEquals(m.days[0], { date: "2026-11-17", level: "high", basket: [1], weather: { scene: "sunny", sprouts: "many", parts: [1] } });
  assertEquals(m.days[1].weather, { scene: "rain", sprouts: "few" });
  assertEquals(m.weather, m.days[0].weather);
  assertEquals(m.top1, stored.top1);
  assertEquals(m.weather_insight, { wave: { label: "хвиля" }, outlook_label: "нове" });
  assertEquals([m.weather_as_of, m.weather_fresh_until], ["2026-11-17T12:00:00.000Z", "2026-11-17T15:00:00.000Z"]);
});
