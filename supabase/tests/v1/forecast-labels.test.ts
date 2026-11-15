import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import type { WeatherData } from "../../functions/_shared/forecast/types.ts";
import {
  days,
  forestLabel,
  humanizeLimit,
  humanizeReason,
  MAX_WHY,
  levelReasonLabel,
  waveBlock,
  weatherBlock,
  weatherScene,
  weatherVerdict,
  sceneSprouts,
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
  assertEquals(forestLabel(null, null), "Ліс");
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

Deno.test("рушій плодоношення: поштовх за його видом — дощ, відлига, прогрів, похолодання", () => {
  assertEquals(humanizeReason("fruiting flush 3/20 thaw 0 10.11", W), "Хвиля плодоношення: 3-й день з 20 — після відлиги (10.11)");
  assertEquals(humanizeReason("fruiting flush 2/20 thaw 12 10.11", W), "Хвиля плодоношення: 2-й день з 20 — після дощу 12 мм у холод (10.11)");
  assertEquals(humanizeReason("fruiting flush 5/10 rain 18 12.09", W), "Хвиля плодоношення: 5-й день з 10 — після дощу 18 мм (12.09)");
  assertEquals(humanizeLimit("fruiting maturing spring_warm 14 15.04 until 28.04", W), "Грибниця дозріває після прогріву ґрунту (15.04) — гриби орієнтовно з 28.04");
  assertEquals(humanizeLimit("fruiting maturing rain_cool 16 02.10 until ?", W), "Грибниця дозріває після дощу 16 мм і похолодання (02.10) — гриби за кілька днів");
});

Deno.test("whyLabels: «в оптимумі» без дублю «температура підходить»", () => {
  assertEquals(whyLabels(["temp 6 within fruiting range", "in peak temp [5,12]"], W), ["Температура в оптимумі для виду"]);
});

// ─── Чому такий рівень, смужка хвилі, висновок погоди (рішення PO 2026-11-15) ──────

Deno.test("Чому середня: хвиля тільки починається — головне, що стримує, першим", () => {
  const s = {
    mushroom_type: "flammulina_velutipes", name_ua: "Зимовий опеньок", score: 0.6, probability: "medium",
    matched: ["fruiting flush 1/20 thaw 0 2026-11-14"], missed: [], wave: null,
    fruiting: {
      phase: "flush", flushDay: 1, flushDays: 20, intensity: 0.66, stage: "rise", soilFit: 1, soilT: 4,
      soilCold: false, triggerDate: "2026-11-14", triggerRain: 0,
    },
  } as unknown as ScoredSpecies;
  const shaped = shapeSpecies(s, W)!;
  assertEquals(shaped.reason_label, "Чому середня: хвиля тільки починається — гриби ще дрібні й поодинокі");
  assertEquals((shaped.limit_labels as string[])[0], "Хвиля тільки починається — гриби ще дрібні й поодинокі");
  // розмите «Умови сприятливі лише частково» більше не з'являється
  assertEquals((shaped.limit_labels as string[]).includes("Умови сприятливі лише частково"), false);
  assertEquals(shaped.wave, {
    phase: "flush", day: 1, days: 20, stage: "rise", label: "Хвиля зараз — 1-й день з 20",
    segments: [{ days: 4, label: "підйом" }, { days: 9, label: "розпал" }, { days: 7, label: "спад" }],
  });
});

Deno.test("Чому висока / низька; холодний ґрунт; не хвиля — лише фаза", () => {
  const peak = { phase: "flush", flushDay: 6, flushDays: 10, intensity: 1, stage: "peak" } as const;
  assertEquals(levelReasonLabel("high", [], ["Підходящий ліс"], peak), "Чому висока: хвиля в розпалі — грибів найбільше");
  assertEquals(levelReasonLabel("low", ["Мало дощу: 2 мм за 3 дні (краще від 10 мм)"], [], undefined),
    "Чому низька: мало дощу: 2 мм за 3 дні (краще від 10 мм)");
  assertEquals(levelReasonLabel("no_data", [], [], undefined), null);
  const cold = shapeSpecies({
    mushroom_type: "x", name_ua: "X", score: 0.5, probability: "medium", matched: [], missed: [], wave: null,
    fruiting: { phase: "flush", flushDay: 5, flushDays: 10, intensity: 0.6, stage: "peak", soilFit: 0.6, soilT: 6.6, soilCold: true },
  } as unknown as ScoredSpecies, W)!;
  assertEquals(cold.reason_label, "Чому середня: ґрунт прохолодний (7°) — гриби ростуть повільно");
  assertEquals(waveBlock({ phase: "maturing", intensity: 0, expectedStart: "2026-11-20" }),
    { phase: "maturing", label: "Хвиля орієнтовно з 20.11" });
  assertEquals(waveBlock(undefined), null);
});

Deno.test("Висновок погоди для грибів: сухо / холодно / свіжий дощ / волого / помірно", () => {
  assertEquals(weatherVerdict({ ...W, droughtDays: 12 })!.tone, "bad");
  assertEquals(weatherVerdict({ ...W, tempAvg7d: 1 })!.label, "Холодно — ростуть лише зимові гриби (зимовий опеньок, глива)");
  assertEquals(weatherVerdict({ ...W, rain3d: 16 })!.tone, "good");
  assertEquals(weatherVerdict({ ...W, rain3d: 2, rain7d: 18 })!.label, "Ґрунт вологий після дощів — добре для грибів");
  assertEquals(weatherVerdict({ ...W, rain3d: 2, rain7d: 6, rain14d: 10 })!.tone, "neutral");
  assertEquals(weatherVerdict({ ...W, source: "unavailable" }), null);
});

Deno.test("Сцена погоди: за кодом WMO, без коду — за опадами й вологістю; спека лише з посухою", () => {
  const day = (o: Partial<{ tempMin: number; tempMax: number; rain: number; humidity: number; code: number | null }> = {}) => ({
    tempMin: 5, tempMax: 15, rain: 0, humidity: 70, code: null, ...o,
  });
  assertEquals(weatherScene(day({ code: 0 }), W), "sunny");
  assertEquals(weatherScene(day({ code: 2 }), W), "partly_cloudy");
  assertEquals(weatherScene(day({ code: 3 }), W), "cloudy");
  assertEquals(weatherScene(day({ code: 45 }), W), "fog");
  assertEquals(weatherScene(day({ code: 61, rain: 3 }), W), "rain");
  assertEquals(weatherScene(day({ code: 95, rain: 8 }), W), "heavy_rain");
  assertEquals(weatherScene(day({ code: 73, rain: 2, tempMax: 0 }), W), "snow");
  assertEquals(weatherScene(day({ code: 0, tempMin: -3 }), W), "frost");
  assertEquals(weatherScene(day({ code: 0, tempMax: 31 }), W), "sunny"); // волого — не спека
  assertEquals(weatherScene(day({ code: 0, tempMax: 31 }), { ...W, droughtDays: 9 }), "heat");
  // без коду (старий кеш)
  assertEquals(weatherScene(day({ rain: 20 }), W), "heavy_rain");
  assertEquals(weatherScene(day({ rain: 2, tempMax: 0.5 }), W), "snow");
  assertEquals(weatherScene(day({ humidity: 98 }), W), "fog");
  assertEquals(weatherScene(day({ humidity: 88 }), W), "cloudy");
  assertEquals(weatherScene(day({ humidity: 60 }), W), "sunny");
  assertEquals(sceneSprouts({ phase: "flush", intensity: 1, stage: "peak" }), "many");
  assertEquals(sceneSprouts({ phase: "flush", intensity: 0.7, stage: "rise" }), "few");
  assertEquals(sceneSprouts({ phase: "maturing", intensity: 0 }), "none");
  assertEquals(sceneSprouts(undefined), "none");
});
