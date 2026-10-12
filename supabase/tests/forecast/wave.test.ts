import { assertEquals } from "jsr:@std/assert";
import {
  calendarWave,
  detectWave,
  previousWave,
} from "../../functions/_shared/forecast/wave.ts";

Deno.test("calendarWave: травень → spring", () => {
  assertEquals(calendarWave(new Date("2026-05-15T12:00:00Z")), "spring");
});

Deno.test("calendarWave: серпень → summer2", () => {
  assertEquals(calendarWave(new Date("2026-08-15T12:00:00Z")), "summer2");
});

Deno.test("calendarWave: жовтень → autumn", () => {
  assertEquals(calendarWave(new Date("2026-10-15T12:00:00Z")), "autumn");
});

Deno.test("previousWave: autumn → summer2", () => {
  assertEquals(previousWave("autumn"), "summer2");
});

Deno.test("previousWave: spring → spring (кордон)", () => {
  assertEquals(previousWave("spring"), "spring");
});

Deno.test("detectWave: без GDD → календарна", () => {
  const w = detectWave(new Date("2026-09-11T12:00:00Z"), 50.45, null);
  assertEquals(w, "autumn");
});

Deno.test("detectWave: GDD більше не впливає — завжди calendar wave (8.7a)", () => {
  // FIX 8.7: ковзне вікно computeGDD не сумісне з кумулятивною шкалою
  // порогів → detectWave довіряє calendarWave за будь-якого GDD.
  const d = new Date("2026-09-11T12:00:00Z");
  assertEquals(detectWave(d, 50.45, null), "autumn");
  assertEquals(detectWave(d, 50.45, 100), "autumn");
  assertEquals(detectWave(d, 50.45, 9999), "autumn");
});

Deno.test("detectWave: GDD=100 (раніше → previousWave) теж autumn (8.7a)", () => {
  const w = detectWave(new Date("2026-09-11T12:00:00Z"), 50.45, 100);
  assertEquals(w, "autumn");
});

Deno.test("detectWave: latitude offset досі працює (8.7a)", () => {
  // lat 45 (південніше 50.45) → offset +14 днів: 25.09 + 14 = 09.10 → autumn
  const w = detectWave(new Date("2026-09-25T12:00:00Z"), 45, 50);
  assertEquals(w, "autumn");
});
