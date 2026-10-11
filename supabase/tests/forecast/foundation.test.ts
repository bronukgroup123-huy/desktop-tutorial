import { assertEquals, assert } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { rowToRule } from "../../functions/_shared/forecast/db.ts";
import { loadFeatureFlags, DEFAULT_FEATURE_FLAGS } from "../../functions/_shared/forecast/flags.ts";
import { isInSeason, toMmdd } from "../../functions/_shared/forecast/constants.ts";

// ============================================================================
// rowToRule — snake_case → camelCase
// ============================================================================

Deno.test("rowToRule: конвертує snake_case у camelCase", () => {
  const row = {
    id: "11111111-1111-1111-1111-111111111111",
    legacy_id: 1,
    mushroom_type: "boletus_edulis",
    name_ua: "Білий гриб",
    name_lat: "Boletus edulis",
    fruiting_temp_min: "6.0",
    weight: "1.00",
    season_start: "06-01",
    season_end: "10-31",
    peak_months: [9, 10],
    mvp_stage: "mvp",
  };
  const rule = rowToRule(row);

  assertEquals(rule.mushroomType, "boletus_edulis");
  assertEquals(rule.nameUa, "Білий гриб");
  assertEquals(rule.seasonStart, "06-01");
  assertEquals(rule.fruitingTempMin, 6);
  assertEquals(rule.weight, 1);
  assert(Array.isArray(rule.peakMonths));
  assertEquals(rule.peakMonths, [9, 10]);
  assertEquals(rule.mvpStage, "mvp");
});

Deno.test("rowToRule: null → null, NULL arrays → []", () => {
  const rule = rowToRule({
    id: "x",
    mushroom_type: "t",
    name_ua: "T",
    name_lat: "T",
    season_start: "01-01",
    season_end: "12-31",
  });
  assertEquals(rule.legacyId, null);
  assertEquals(rule.humidityMin, null);
  assertEquals(rule.forestType, []);
  assertEquals(rule.regionIds, []);
  assertEquals(rule.droughtThenRain, false);
  assertEquals(rule.weight, 1.0); // fallback
});

// ============================================================================
// loadFeatureFlags — defaults when DB empty
// ============================================================================

type MockDb = Parameters<typeof loadFeatureFlags>[0];

function emptyDb(): MockDb {
  return {
    from: () => ({
      select: async () => ({ data: [], error: null }),
    }),
  } as unknown as MockDb;
}

function flagsDb(rows: Array<{ key: string; enabled: boolean; value: unknown }>): MockDb {
  return {
    from: () => ({
      select: async () => ({ data: rows, error: null }),
    }),
  } as unknown as MockDb;
}

Deno.test("loadFeatureFlags: порожня БД → defaults", async () => {
  const flags = await loadFeatureFlags(emptyDb());
  assertEquals(flags.fruiting_temp_buffer, 3);
  assertEquals(flags.gdd_enabled, true);
  assertEquals(flags.pressure_enabled, false);
  assertEquals(flags.peak_wave_bonus_enabled, true);
});

Deno.test("loadFeatureFlags: помилка БД → defaults", async () => {
  const errDb = {
    from: () => ({
      select: async () => ({ data: null, error: { message: "boom" } }),
    }),
  } as unknown as MockDb;
  const flags = await loadFeatureFlags(errDb);
  assertEquals(flags, DEFAULT_FEATURE_FLAGS);
});

Deno.test("loadFeatureFlags: читає значення з БД", async () => {
  const db = flagsDb([
    { key: "fruiting_temp_buffer", enabled: true, value: 5 },
    { key: "pressure_enabled", enabled: true, value: true },
    { key: "gdd_enabled", enabled: false, value: false },
  ]);
  const flags = await loadFeatureFlags(db);
  assertEquals(flags.fruiting_temp_buffer, 5);
  assertEquals(flags.pressure_enabled, true);
  assertEquals(flags.gdd_enabled, false);
  // невідомі ключі ігноруються, решта — default
  assertEquals(flags.region_filter_enabled, true);
});

// ============================================================================
// isInSeason (§18.1)
// ============================================================================

Deno.test("isInSeason: 11 вересня в сезоні → true", () => {
  assertEquals(isInSeason("09-11", "06-01", "10-31"), true);
});

Deno.test("isInSeason: 11 березня поза сезоном → false", () => {
  assertEquals(isInSeason("03-11", "06-01", "10-31"), false);
});

Deno.test("isInSeason: сезон через рік 12-15 in 10-01→02-28 → true", () => {
  assertEquals(isInSeason("12-15", "10-01", "02-28"), true);
  assertEquals(isInSeason("01-15", "10-01", "02-28"), true);
  assertEquals(isInSeason("06-15", "10-01", "02-28"), false);
});

Deno.test("isInSeason: межі сезону інклюзивні", () => {
  assertEquals(isInSeason("06-01", "06-01", "10-31"), true);
  assertEquals(isInSeason("10-31", "06-01", "10-31"), true);
});

// ============================================================================
// toMmdd
// ============================================================================

Deno.test("toMmdd: формує MM-DD у UTC", () => {
  assertEquals(toMmdd(new Date("2026-09-11T18:00:00Z")), "09-11");
  assertEquals(toMmdd(new Date("2026-01-05T00:00:00Z")), "01-05");
});
