import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import type { WeatherData } from "../../functions/_shared/forecast/types.ts";
import {
  days,
  forestLabel,
  humanizeReason,
  MAX_WHY,
  weatherBlock,
  whenLabel,
  whyLabels,
} from "../../functions/_shared/v1/forecast-labels.ts";
import { shapeSpecies } from "../../functions/_shared/v1/forecast.ts";
import type { ScoredSpecies } from "../../functions/_shared/forecast/types.ts";

const W: WeatherData = {
  tempAvg7d: 13.4, tempAvg14d: 13, tempAvg20d: 13, tempMin: 8.6, tempMax: 17.2,
  humidity: 78.4, rain1d: 0, rain2d: 2, rain3d: 16.2, rain7d: 21, rain14d: 30, rain30d: 50,
  droughtDays: 0, daysAfterRain: 3, pressure: 1013.4, pressureTrend: "stable",
  soilState: "normal", gdd: 240, fetchedAt: "2026-11-09T06:00:00Z", source: "open-meteo",
};
const NO_WEATHER = { ...W, source: "unavailable" as const };

Deno.test("labels: технічні причини → українські підписи", () => {
  assertEquals(humanizeReason("temp 13 within fruiting range", W), "Температура 13° — підходить для плодоношення");
  assertEquals(humanizeReason("rain3d ok", W), "Дощ 16 мм за останні 3 дні");
  assertEquals(humanizeReason("humidity ok", W), "Вологість 78% — достатня");
  assertEquals(humanizeReason("forest match: pine", W), "Підходящий ліс: сосновий ліс");
  assertEquals(humanizeReason("daysAfterRain 3 in [2,7]", W), "3 дні після дощу — вдалий час");
  assertEquals(humanizeReason("10-12 in season", W), "Сезон цього виду");
  assertEquals(humanizeReason("Дощ після 12 днів посухи", W), "Дощ після 12 днів посухи");
});

Deno.test("labels: негативні, службові й назви хвиль не показуються", () => {
  for (const r of [
    "temp 3 < min 5", "humidity 40 < 70", "forest not confirmed — skip", "habitat: passthrough (no input)",
    "weather unavailable — passthrough", 'wave "autumn" allowed', "dry → ×0.7", "Осіння хвиля (пік)",
  ]) {
    assertEquals(humanizeReason(r, W), null, r);
  }
});

Deno.test("labels: why — без англійської, без дублів, не більше MAX_WHY", () => {
  const why = whyLabels([
    "temp 13 within fruiting range", "in peak temp [12,18]", "humidity ok", "rain3d ok",
    "rain3d ok", "10-12 in season", "peak month: 10", "habitat: passthrough (no input)",
  ], W);
  assertEquals(why.length, MAX_WHY);
  assertEquals(new Set(why).size, why.length);
  assertEquals(why.some((l) => /[a-z]{3}/i.test(l)), false);
});

Deno.test("labels: when — хвиля + дні після дощу", () => {
  assertEquals(whenLabel("autumn", W), "Зараз — 3 дні після дощу · Осіння хвиля");
  assertEquals(whenLabel("autumn", { ...W, daysAfterRain: 999 }), "Осіння хвиля");
  assertEquals(whenLabel(null, NO_WEATHER), "Весь сезон");
  assertEquals(whenLabel("spring", { ...W, daysAfterRain: 0 }), "Зараз — у день дощу · Весняна хвиля");
});

Deno.test("labels: відмінювання «день»", () => {
  assertEquals([1, 2, 5, 11, 21, 22].map(days), ["1 день", "2 дні", "5 днів", "11 днів", "21 день", "22 дні"]);
});

Deno.test("weather: блок з готовими рядками; недоступна погода → null", () => {
  const b = weatherBlock(W)!;
  assertEquals(b.temp_label, "9°…17°, у середньому 13° за тиждень");
  assertEquals(b.rain_label, "Опади: 16 мм за 3 дні, 21 мм за тиждень");
  assertEquals(b.rain_recent_label, "Сильний дощ 3 дні тому");
  assertEquals(b.pressure_label, "Тиск 1013 гПа, стабільний");
  assertEquals(b.icon, "sun");
  assertEquals(weatherBlock({ ...W, rain1d: 5 })!.icon, "rain");
  assertEquals(weatherBlock(NO_WEATHER), null);
  assertEquals(weatherBlock(null), null);
});

Deno.test("forest label", () => {
  assertEquals(forestLabel("pine", 50), "Сосновий ліс, ~50 р.");
  assertEquals(forestLabel("oak", null), "Дубовий ліс");
  assertEquals(forestLabel(null, null), "Тип лісу невідомий — прогноз базовий");
});

Deno.test("shapeSpecies: людські підписи і жодних чисел", () => {
  const s = shapeSpecies({
    mushroom_type: "boletus_edulis", name_ua: "Білий гриб", score: 0.83, probability: "high",
    matched: ["temp 13 within fruiting range", "rain3d ok"], missed: [], wave: "autumn", where: null,
  } as ScoredSpecies, W)!;
  assertEquals(s.when_label, "Зараз — 3 дні після дощу · Осіння хвиля");
  assertEquals(s.why_labels, ["Температура 13° — підходить для плодоношення", "Дощ 16 мм за останні 3 дні"]);
  assertEquals(Object.values(s).some((v) => typeof v === "number"), false);
});

Deno.test("shapeSpecies: низький рівень пояснюється обмежувальними факторами, а не лише «✓»", () => {
  const s = shapeSpecies({
    mushroom_type: "flammulina_velutipes", name_ua: "Зимовий опеньок", score: 0.3, probability: "low",
    matched: ["temp 4 within fruiting range", "11-12 in season"],
    missed: ["humidity 55 < 70", "dry → ×0.7", "temp in transition zone", "Різкі перепади температур"],
    wave: "late", where: null,
  } as ScoredSpecies, W)!;
  assertEquals(s.level_label, "Низька ймовірність");
  assertEquals(s.limit_labels, [
    "Вологість 55% — замало (краще від 70%)",
    "Сухий ґрунт",
    "Температура 13° — на межі сприятливої",
    "Різкі перепади температур",
  ]);
});

Deno.test("shapeSpecies: низький рівень без явних факторів — пояснення сезону; високий — без вигаданих", () => {
  const base = { mushroom_type: "x", name_ua: "X", wave: null, where: null, missed: [] };
  const low = shapeSpecies({ ...base, score: 0.3, probability: "low", matched: ["11-12 in season"] } as ScoredSpecies, W)!;
  assertEquals(low.limit_labels, ["Не пік сезону для цього виду"]);
  const high = shapeSpecies({ ...base, score: 0.8, probability: "high", matched: ["peak wave: autumn"] } as ScoredSpecies, W)!;
  assertEquals(high.limit_labels, []);
});
