// Рельєф і ґрунт ділянки: розбір відповідей API і поправки рушія (ADR-015 §15.8 п.15).
import { assert, assertEquals } from "jsr:@std/assert";
import {
  fetchTerrain,
  parseElevation,
  parseSoilGrids,
  reliefOf,
  samplePoints,
  soilOf,
  terrainAdjust,
  terrainLabel,
} from "../../functions/_shared/forecast/terrain.ts";
import { fruitingEvents, type FruitingParams } from "../../functions/_shared/forecast/fruiting.ts";
import { scenarioSeries } from "../../../scripts/season_replay/core.ts";

const P: FruitingParams = { trigger: "rain", triggerRainMm: 15, maturationDd: 80, ddBase: 4, flushDays: 10, soilTempMin: 10, soilTempMax: 20 };

Deno.test("terrain: низина / пагорб / рівнина за висотами квадрата", () => {
  assertEquals(reliefOf(150, [170, 172, 168, 175]).relief, "valley");
  assertEquals(reliefOf(200, [180, 178, 182, 179]).relief, "hill");
  assertEquals(reliefOf(180, [178, 185, 176, 181]), { relief: "flat", range: 9 });
  assertEquals(samplePoints(50, 30, 5).length, 9);
  assertEquals(parseElevation({ elevation: [150, 170, 172, 168, 175, 171, 169, 170, 172] })?.relief, "valley");
  assertEquals(parseElevation({ elevation: [1, 2] }), null);
});

Deno.test("terrain: ґрунт за SoilGrids — пісок / суглинок / глина", () => {
  const json = {
    properties: {
      layers: [
        { name: "sand", unit_measure: { d_factor: 10 }, depths: [{ values: { mean: 7800 } }] },
        { name: "clay", unit_measure: { d_factor: 10 }, depths: [{ values: { mean: 600 } }] },
      ],
    },
  };
  assertEquals(parseSoilGrids(json), { sand: 78, clay: 6 });
  assertEquals(soilOf(78, 6), "sandy");
  assertEquals(soilOf(30, 40), "clay");
  assertEquals(soilOf(40, 20), "loam");
  assertEquals(soilOf(null, 10), null);
});

Deno.test("terrain: збій API — поля null, без помилки", async () => {
  const t = await fetchTerrain(50, 30, 5, () => Promise.reject(new Error("offline")));
  assertEquals([t.relief, t.soil, t.elevation], [null, null, null]);
  assertEquals(terrainLabel(t), null);
});

Deno.test("terrain: пісок пересихає швидше — посуха зриває дозрівання раніше", () => {
  // Злива після посухи, далі 8 сухих днів при холодному ґрунті (дозрівання довге).
  const s = scenarioSeries("2025-09-01", [{ days: 30, t: 9, rain: 0 }, { days: 1, t: 9, rain: 25 }, { days: 30, t: 9, rain: 0 }]);
  const loam = fruitingEvents(s, terrainAdjust(P, { relief: null, soil: "loam" }))[0];
  const sand = fruitingEvents(s, terrainAdjust(P, { relief: null, soil: "sandy" }))[0];
  assert(loam.aborted && sand.aborted);
  // на піску зрив на 3 дні раніше — подія коротша; параметри змінено як очікується
  assertEquals(terrainAdjust(P, { relief: null, soil: "sandy" }).abortDryDays, 7);
  assertEquals(terrainAdjust(P, { relief: "valley", soil: null }).soilTOffset, -0.7);
  assertEquals(terrainAdjust(P, null), P);
});
