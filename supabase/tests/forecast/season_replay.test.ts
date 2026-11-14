// Інструмент повтору сезону (scripts/season_replay, BACKEND_PLAN B2.15): механіка без мережі.
import { assert, assertEquals } from "jsr:@std/assert";
import { rowToRule } from "../../functions/_shared/forecast/db.ts";
import {
  dateRange,
  replay,
  runScenario,
  SCENARIOS,
  scenarioSeries,
} from "../../../scripts/season_replay/core.ts";
import { renderReport, textGrid } from "../../../scripts/season_replay/report.ts";

const rules = JSON.parse(await Deno.readTextFile(new URL("../fixtures/rules-subset.json", import.meta.url)))
  .map(rowToRule);

Deno.test("season replay: dateRange включно, через межу місяця", () => {
  assertEquals(dateRange("2025-08-30", "2025-09-02"), ["2025-08-30", "2025-08-31", "2025-09-01", "2025-09-02"]);
});

Deno.test("season replay: сценарій → ряд погоди по днях", () => {
  const s = scenarioSeries("2025-08-01", [{ days: 2, t: 20, rain: 0 }, { days: 1, t: 15, rain: 25, soil: 0.4 }]);
  assertEquals(s.dates, ["2025-08-01", "2025-08-02", "2025-08-03"]);
  assertEquals(s.precip, [0, 0, 25]);
  assertEquals([s.tmin[2], s.tmax[2]], [10, 20]);
  assertEquals(s.soil[2], 0.4);
});

Deno.test("season replay: злива видна в стані погоди наступних днів, а не до неї", () => {
  const series = scenarioSeries("2025-08-01", [{ days: 30, t: 18, rain: 0 }, { days: 1, t: 16, rain: 25 }, { days: 5, t: 15, rain: 0 }]);
  const run = replay("t", series, ["2025-08-30", "2025-08-31", "2025-09-03"], 50.25, 28.6, "pine", rules);
  assertEquals(run.days.map((d) => d.weather.daysAfterRain), [999, 0, 3]);
  assertEquals(run.days[0].weather.rain7d, 0);
  assertEquals(run.days[2].weather.rain7d, 25);
});

Deno.test("season replay: кожен сценарій дає рівень для кожного виду на кожен день", () => {
  for (const s of SCENARIOS) {
    const run = runScenario(s, rules);
    assert(run.days.length >= 28, s.id);
    assertEquals(run.days[0].date, s.showFrom);
    for (const d of run.days) assertEquals(Object.keys(d.species).length, rules.length);
  }
});

Deno.test("season replay: звіт і сітка для логів", () => {
  const run = runScenario(SCENARIOS[0], rules);
  const grid = textGrid(run).split("\n");
  assertEquals(grid.length, 2 + rules.length);
  assert(grid[2].startsWith("boletu ") && grid[2].endsWith("  boletus_edulis"));
  const html = renderReport("Сценарії сезону", "тест", [run], ["знахідка"]);
  assert(html.startsWith("<!doctype html>"));
  assert(html.includes("<title>Сценарії сезону</title>"));
  assert(html.includes("Білий гриб"));
});

Deno.test("season replay: компактний запис для логу → той самий прогін", async () => {
  const { compactRun, expandRun } = await import("../../../scripts/season_replay/report.ts");
  const run = runScenario(SCENARIOS[0], rules);
  const back = expandRun(compactRun(run));
  assertEquals(back.days.length, run.days.length);
  assertEquals(back.days.map((d) => d.species.boletus_edulis.level), run.days.map((d) => d.species.boletus_edulis.level));
  assertEquals(back.days.map((d) => d.top1), run.days.map((d) => d.top1));
  assertEquals(back.days[5].weather.rain, run.days[5].weather.rain);
});
