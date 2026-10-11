import { assertEquals } from "jsr:@std/assert";
import {
  computeSoilState,
  computeGDD,
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
