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

Deno.test("detectWave: GDD занадто низький → попередня", () => {
  // autumn має threshold 1500 (GDD_THRESHOLDS, §11.3). GDD=800 → summer2
  const w = detectWave(new Date("2026-09-11T12:00:00Z"), 50.45, 800);
  assertEquals(w, "summer2");
});
