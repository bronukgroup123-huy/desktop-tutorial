// Рушій плодоношення: поштовх → дозрівання (тепло ґрунту) → хвиля → спад (ADR-015 §15.8).
import { assert, assertEquals } from "jsr:@std/assert";
import {
  flushShape,
  flushStage,
  fruitingEvents,
  type FruitingParams,
  fruitingState,
  PRIMED_FRACTION,
  soilTempFit,
} from "../../functions/_shared/forecast/fruiting.ts";
import { scenarioSeries } from "../../../scripts/season_replay/core.ts";

const BOLETUS: FruitingParams = {
  trigger: "rain", triggerRainMm: 15, maturationDd: 80, ddBase: 4, flushDays: 10, soilTempMin: 10, soilTempMax: 20,
};

// Ґрунт у сценаріях = повітря − 1°: при 16° повітря → 15° ґрунт → 11 градусо-днів на добу.
const DROUGHT_THEN_RAIN = scenarioSeries("2025-08-01", [
  { days: 30, t: 16, rain: 0 },          // посуха: грибниця не готова
  { days: 1, t: 16, rain: 25 },          // 2025-08-31 — злива (поштовх)
  { days: 30, t: 16, rain: [0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0] },
]);

Deno.test("fruiting: після посухи — повна сума тепла (80 / 11 на добу ≈ 8 днів), далі хвиля 10 днів", () => {
  const [ev] = fruitingEvents(DROUGHT_THEN_RAIN, BOLETUS);
  assertEquals(DROUGHT_THEN_RAIN.dates[ev.trigger], "2025-08-31");
  assertEquals(ev.primed, false);
  assertEquals(DROUGHT_THEN_RAIN.dates[ev.flushStart!], "2025-09-08");

  assertEquals(fruitingState(DROUGHT_THEN_RAIN, "2025-08-30", BOLETUS)!.phase, "idle");
  const mat = fruitingState(DROUGHT_THEN_RAIN, "2025-09-03", BOLETUS)!;
  assertEquals([mat.phase, mat.expectedStart, mat.triggerRain], ["maturing", "2025-09-08", 25]);
  const flush = fruitingState(DROUGHT_THEN_RAIN, "2025-09-10", BOLETUS)!;
  assertEquals([flush.phase, flush.flushDay, flush.flushDays], ["flush", 3, 10]);
  assertEquals(fruitingState(DROUGHT_THEN_RAIN, "2025-09-20", BOLETUS)!.phase, "after");
});

Deno.test("fruiting: ґрунт уже вологий — грибниця готова, гриби за 2–4 дні (як у книгах)", () => {
  const s = scenarioSeries("2025-08-01", [
    { days: 25, t: 16, rain: [0, 0, 4, 0, 0, 4, 0, 0, 4, 0, 0, 4, 0, 0, 4, 0, 0, 4, 0, 0, 4, 0, 0, 4, 0] },
    { days: 1, t: 16, rain: 20 },
    { days: 20, t: 16, rain: 1 },
  ]);
  const ev = fruitingEvents(s, BOLETUS).find((e) => e.triggerRain >= 20)!;
  assert(ev.primed);
  const lag = ev.flushStart! - ev.trigger;
  assert(lag >= 2 && lag <= 4, `затримка ${lag} днів`);
  assertEquals(Math.ceil((BOLETUS.maturationDd * PRIMED_FRACTION) / 11), 3);
});

Deno.test("fruiting: холодний ґрунт — дозрівання довше", () => {
  const cold = scenarioSeries("2025-09-01", [{ days: 30, t: 10, rain: 0 }, { days: 1, t: 10, rain: 25 }, { days: 30, t: 10, rain: 1 }]);
  const [ev] = fruitingEvents(cold, BOLETUS);
  assertEquals(ev.flushStart! - ev.trigger, Math.ceil(80 / 5)); // 9° ґрунт → 5 градусо-днів на добу
});

Deno.test("fruiting: посуха під час дозрівання зриває хвилю", () => {
  const s = scenarioSeries("2025-07-01", [{ days: 30, t: 9, rain: 0 }, { days: 1, t: 9, rain: 16 }, { days: 30, t: 9, rain: 0 }]);
  const [ev] = fruitingEvents(s, BOLETUS);
  assert(ev.aborted);
  assertEquals(ev.flushStart, null);
  assertEquals(fruitingState(s, "2025-08-20", BOLETUS)!.phase, "idle");
});

Deno.test("fruiting: дощ слабший за поріг — поштовху немає", () => {
  const s = scenarioSeries("2025-08-01", [{ days: 30, t: 16, rain: 0 }, { days: 1, t: 16, rain: 8 }, { days: 10, t: 16, rain: 0 }]);
  assertEquals(fruitingEvents(s, BOLETUS), []);
});

Deno.test("fruiting: сморчок — весняний прогрів ґрунту, не дощ", () => {
  const morel: FruitingParams = { ...BOLETUS, trigger: "spring_warm", triggerRainMm: 0, maturationDd: 60, flushDays: 18, soilTempMin: 6, soilTempMax: 14 };
  const s = scenarioSeries("2025-03-01", [{ days: 61, t: 3, tTo: 15, rain: [0, 0, 4] .concat(Array(58).fill(0).map((_, i) => (i % 3 === 2 ? 4 : 0))) }]);
  const events = fruitingEvents(s, morel);
  assertEquals(events.length, 1); // один раз за весну
  const st5 = s.dates[events[0].trigger];
  assert(st5 >= "2025-04-01" && st5 <= "2025-04-20", st5);
});

Deno.test("fruiting: зимовий опеньок — дощ у холод або відлига після заморозків", () => {
  const winter: FruitingParams = { trigger: "thaw", triggerRainMm: 10, maturationDd: 25, ddBase: 0, flushDays: 20, soilTempMin: 0, soilTempMax: 10 };
  const coldRain = scenarioSeries("2025-11-01", [{ days: 10, t: 5, rain: 0 }, { days: 1, t: 5, rain: 12 }, { days: 10, t: 5, rain: 0 }]);
  assertEquals(fruitingEvents(coldRain, winter).length, 1);
  const thaw = scenarioSeries("2025-12-01", [{ days: 5, t: -4, rain: 0 }, { days: 10, t: 4, rain: 0 }]);
  assertEquals(thaw.dates[fruitingEvents(thaw, winter)[0].trigger], "2025-12-06");
});

Deno.test("fruiting: форма хвилі і температура ґрунту", () => {
  assert(flushShape(0, 10) < 1);
  assertEquals(flushShape(4, 10), 1);
  assert(flushShape(9, 10) < 0.7);
  assertEquals(soilTempFit(15, BOLETUS), 1);
  assertEquals(soilTempFit(8, BOLETUS), 0.6);
  assertEquals(soilTempFit(2, BOLETUS), 0.25);
});

Deno.test("fruiting: новий поштовх посеред хвилі не скидає її на 1-й день — береться сильніша", () => {
  // Злива 31.08 → хвиля з 08.09; ще злива 10.09 (ґрунт вологий — нова хвиля за ~3 дні).
  const s = scenarioSeries("2025-08-01", [
    { days: 30, t: 16, rain: 0 },
    { days: 1, t: 16, rain: 25 },          // 31.08
    { days: 10, t: 16, rain: 1 },          // 01.09–10.09
    { days: 1, t: 16, rain: 25 },          // 11.09 — новий поштовх посеред хвилі
    { days: 20, t: 16, rain: 1 },
  ]);
  const evs = fruitingEvents(s, BOLETUS).filter((e) => e.flushStart !== null);
  assert(evs.length >= 2);
  const second = s.dates[evs[1].flushStart!];
  const st = fruitingState(s, second, BOLETUS)!;
  // Стара хвиля (розпал) сильніша за початок нової — день не скидається на 1-й.
  assertEquals(st.phase, "flush");
  assert(st.flushDay! > 1, `день ${st.flushDay}`);
  assertEquals(st.stage, "peak");
  assertEquals(st.intensity, 1);
  // Коли стара хвиля спадає, а нова — в розпалі, береться нова.
  const later = fruitingState(s, s.dates[evs[1].flushStart! + 4], BOLETUS)!;
  assertEquals(later.triggerDate, s.dates[evs[1].trigger]);
});

Deno.test("fruiting: стадії хвилі", () => {
  assertEquals([0, 1, 2, 3, 4, 12, 13, 19].map((d) => flushStage(d, 20)), [
    "rise", "rise", "rise", "rise", "peak", "peak", "decline", "decline",
  ]);
});
