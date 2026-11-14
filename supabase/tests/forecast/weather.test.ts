import { assertEquals } from "jsr:@std/assert";
import {
  buildSeries,
  computeGDD,
  computeSoilState,
  type OpenMeteoResponse,
  pressureTrendFromDiff,
  weatherAsOf,
} from "../../functions/_shared/forecast/weather.ts";

Deno.test("computeSoilState: dry", () => {
  assertEquals(computeSoilState(3, 5, 20, 0.2), "dry");
});

Deno.test("computeSoilState: waterlogged", () => {
  assertEquals(computeSoilState(70, 100, 0, 0.9), "waterlogged");
});

Deno.test("computeSoilState: wet", () => {
  assertEquals(computeSoilState(30, 50, 0, 0.7), "wet");
});

Deno.test("computeSoilState: normal", () => {
  assertEquals(computeSoilState(10, 20, 5, 0.5), "normal");
});

Deno.test("computeGDD: базовий випадок", () => {
  // 3 дні: (10+5)/2=7.5 → 2.5; (15+8)/2=11.5 → 6.5; (20+12)/2=16 → 11
  // sum - base 5 each: 2.5 + 6.5 + 11 = 20
  const gdd = computeGDD([10, 15, 20], [5, 8, 12], 5);
  assertEquals(gdd, 20);
});

Deno.test("computeGDD: холодні дні не дають GDD", () => {
  const gdd = computeGDD([4, 3, 2], [1, 0, -2], 5);
  assertEquals(gdd, 0);
});

// ─── Стан погоди на день D (ряд: минулі дні + прогноз) ─────────────────────


/** 30 сухих минулих днів, сьогодні сухо, злива 25 мм на 3-й день прогнозу. */
function openMeteo(): OpenMeteoResponse {
  const start = Date.parse("2026-08-01T00:00:00Z");
  const days = 37; // 30 минулих + сьогодні + 6 днів прогнозу
  const time = Array.from({ length: days }, (_, i) => new Date(start + i * 86_400_000).toISOString().slice(0, 10));
  const hours = time.flatMap((d) => Array.from({ length: 24 }, (_, h) => `${d}T${String(h).padStart(2, "0")}:00`));
  const precip = Array(days).fill(0);
  precip[33] = 25; // сьогодні — індекс 30
  return {
    hourly: {
      time: hours,
      temperature_2m: hours.map((_, i) => (Math.floor(i / 24) >= 30 ? 20 : 15)),
      relative_humidity_2m: Array(hours.length).fill(70),
      precipitation: Array(hours.length).fill(0),
      pressure_msl: hours.map((_, i) => 1015 - (i % 24) * 0.1), // за добу −2.3 гПа
      soil_moisture_0_to_7cm: Array(hours.length).fill(0.3),
    },
    daily: {
      time,
      temperature_2m_max: Array(days).fill(22),
      temperature_2m_min: Array(days).fill(10),
      precipitation_sum: precip,
    },
  };
}

Deno.test("weatherAsOf: «сьогодні» не бачить дощів наступних днів прогнозу", () => {
  const s = buildSeries(openMeteo(), 30, new Date("2026-08-31T09:00:00Z"))!;
  assertEquals(s.today, "2026-08-31");
  const today = weatherAsOf(s, "2026-08-31");
  assertEquals(today.rain7d, 0);
  assertEquals(today.droughtDays, 31);
  assertEquals(today.daysAfterRain, 999);
  assertEquals(today.tempAvg7d, 15 + 5 / 7); // 6 минулих днів по 15° + сьогодні 20°
  assertEquals(today.day, { date: "2026-08-31", tempMin: 10, tempMax: 22, rain: 0, humidity: 70, daysAhead: 0 });
});

Deno.test("weatherAsOf: день прогнозу бачить дощ, що випав до нього", () => {
  const s = buildSeries(openMeteo(), 30, new Date("2026-08-31T09:00:00Z"))!;
  const rainDay = weatherAsOf(s, "2026-09-03");
  assertEquals(rainDay.rain1d, 25);
  assertEquals(rainDay.daysAfterRain, 0);
  const later = weatherAsOf(s, "2026-09-06");
  assertEquals(later.daysAfterRain, 3);
  assertEquals(later.rain7d, 25);
  assertEquals(later.day?.daysAhead, 6);
});

Deno.test("weatherAsOf: день поза рядом → погода недоступна", () => {
  const s = buildSeries(openMeteo(), 30, new Date())!;
  assertEquals(weatherAsOf(s, "2026-09-20").source, "unavailable");
});

Deno.test("weatherAsOf: тренд тиску — за добу цього дня", () => {
  const s = buildSeries(openMeteo(), 30, new Date())!;
  assertEquals(weatherAsOf(s, "2026-08-31").pressureTrend, "smooth_decline_before_rain");
  assertEquals(pressureTrendFromDiff(3), "rising");
  assertEquals(pressureTrendFromDiff(-5), "falling");
  assertEquals(pressureTrendFromDiff(0), "stable");
});

Deno.test("buildSeries: доба переходу на зимовий час (25 год) групується за датою", () => {
  const r = openMeteo();
  r.hourly.time.splice(24, 0, "2026-08-02T02:00"); // зайва година в 2-й день
  r.hourly.temperature_2m.splice(24, 0, 15);
  r.hourly.relative_humidity_2m.splice(24, 0, 70);
  r.hourly.precipitation.splice(24, 0, 0);
  r.hourly.pressure_msl.splice(24, 0, 1015);
  r.hourly.soil_moisture_0_to_7cm.splice(24, 0, 0.3);
  const s = buildSeries(r, 30, new Date())!;
  assertEquals(s.dates.length, 37);
  assertEquals(s.tmean[30], 20);
});
