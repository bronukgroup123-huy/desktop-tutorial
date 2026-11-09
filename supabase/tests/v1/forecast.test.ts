import { assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { HttpError } from "../../functions/_shared/http.ts";
import {
  assertPointInHomeRegion,
  parseForecastBody,
  shapeSpecies,
} from "../../functions/_shared/v1/forecast.ts";
import type { ScoredSpecies } from "../../functions/_shared/forecast/types.ts";
import { mockDb } from "./mock-db.ts";

const SPECIES = {
  mushroom_type: "boletus_edulis",
  name_ua: "Білий гриб",
  score: 0.83,
  probability: "high",
  matched: ["temp 13 within fruiting range"],
  missed: [],
  wave: "autumn",
  where: "Південні схили",
} as unknown as ScoredSpecies;

Deno.test("v1-forecast: у відповіді немає числових ймовірностей (Заборона №1)", () => {
  const s = shapeSpecies(SPECIES)!;
  assertEquals("score" in s, false);
  assertEquals("probability" in s, false);
  assertEquals(Object.values(s).some((v) => typeof v === "number"), false);
  assertEquals(s.level, "high");
  assertEquals(s.level_label, "Висока ймовірність");
  assertEquals(s.level_color, "#22c55e");
});

Deno.test("v1-forecast: невідомий рівень → no_data", () => {
  const s = shapeSpecies({ ...SPECIES, probability: "weird" } as unknown as ScoredSpecies)!;
  assertEquals(s.level, "no_data");
});

Deno.test("v1-forecast: валідація тіла", () => {
  assertEquals(parseForecastBody({ lat: 50.4, lng: 30.5, date: "2026-11-09" }).lat, 50.4);
  const err = assertThrows(() => parseForecastBody({ lat: 200, lng: 30.5, date: "2026-11-09" }), HttpError);
  assertEquals(err.code, "invalid_body");
  assertThrows(() => parseForecastBody({ lat: 50, lng: 30, date: "09.11.2026" }), HttpError);
});

Deno.test("v1-forecast: точка поза Home Region → 403 outside_home_region", async () => {
  const db = mockDb({ "rpc.point_in_region": { data: false, error: null } });
  const err = await assertRejects(() => assertPointInHomeRegion(db, 48.5, 35.0, 10), HttpError);
  assertEquals(err.status, 403);
  assertEquals(err.code, "outside_home_region");
  assertEquals(db.calls[0].args[0], { lat: 48.5, lng: 35.0, region_id: 10 });
});

Deno.test("v1-forecast: точка в Home Region → ок", async () => {
  await assertPointInHomeRegion(mockDb({ "rpc.point_in_region": { data: true, error: null } }), 50.4, 30.5, 10);
});
