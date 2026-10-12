// ============================================================================
// Forecast Engine — Dynamic Rules 1–6, 8 (plan v6.0 §12, group 8.4b)
//
// Кожне правило повертає делту (−1..+1) до базового скору (8.4a).
// Rule 7 (TempShock) — V2, не входить у MVP.
// ============================================================================

import type { SpeciesRule, ForecastContext, Wave } from "./types.ts";

export interface RuleResult {
  modifier: number;        // дельта −1..+1
  reason?: string;
  skip?: boolean;
  overrideWhere?: string | null;  // для Rule 3 і Rule 8
}

export type DynamicRule = (rule: SpeciesRule, ctx: ForecastContext) => RuleResult;

// ────────────────────────────────────────────────────────────────────
// Rule 1 — Вік деревостану (§12.1)
// ────────────────────────────────────────────────────────────────────

export const rule1_StandAge: DynamicRule = (rule, ctx) => {
  if (ctx.standAgeUnknown || ctx.standAge === null) {
    return { modifier: 0, skip: true };
  }
  const age = ctx.standAge;

  if (rule.mushroomType === "boletus_edulis") {
    if (age >= 10 && age <= 30) {
      return { modifier: 0.10, reason: "Молодий сосняк (10–30)" };
    }
    if (age > 30 && age <= 50) return { modifier: 0 };
    if (age > 50) return { modifier: -0.05, reason: "Старий деревостан (50+)" };
    return { modifier: 0 };
  }

  if (rule.mushroomType === "cantharellus_cibarius") {
    if (age >= 41 && age <= 60) {
      return { modifier: 0.15, reason: "Стиглий березняк 41–60" };
    }
    if (age < 30 || age > 70) return { modifier: -0.05, reason: "Вік поза оптимумом" };
    return { modifier: 0 };
  }

  return { modifier: 0 };
};

// ────────────────────────────────────────────────────────────────────
// Rule 2 — Дощ після посухи (§12.2)
// ────────────────────────────────────────────────────────────────────

export const rule2_DroughtThenRain: DynamicRule = (rule, ctx) => {
  if (!rule.droughtThenRain) return { modifier: 0, skip: true };

  const w = ctx.weather;
  if (w.droughtDays < (rule.droughtDaysMin ?? 7)) {
    return { modifier: 0, skip: true };
  }

  const droughtOk = w.droughtDays >= 14;
  const rainOk =
    w.rain1d >= (rule.rain1dMin ?? 10) || w.rain2d >= (rule.rain2dMin ?? 10);
  const minD = rule.daysAfterRainMin ?? 5;
  const maxD = rule.daysAfterRainMax ?? 9;
  const windowOk = w.daysAfterRain >= minD && w.daysAfterRain <= maxD;

  if (droughtOk && rainOk && windowOk) {
    if (w.soilState === "waterlogged") {
      return { modifier: -0.30, reason: "Занадто сиро" };
    }
    return { modifier: 0.20, reason: `Дощ після ${w.droughtDays} днів посухи` };
  }

  if (rainOk && !windowOk) {
    return { modifier: 0.05, reason: "Дощ був, вікно не оптимальне" };
  }

  return { modifier: 0 };
};

// ────────────────────────────────────────────────────────────────────
// Rule 3 — Мікрорефугіум білого (§12.3)
// ────────────────────────────────────────────────────────────────────

export const rule3_MicrorefugiumBoletus: DynamicRule = (rule, ctx) => {
  if (rule.mushroomType !== "boletus_edulis") {
    return { modifier: 0, skip: true };
  }
  const w = ctx.weather;
  const cooling = w.tempAvg7d < w.tempAvg14d - 3;
  const dry = w.soilState === "dry";

  if (cooling || dry) {
    return {
      modifier: 0,
      reason: "Прохолода/сухість — мікрорефугіум",
      overrideWhere: rule.microrefugiumDry ?? null,
    };
  }
  return { modifier: 0 };
};

// ────────────────────────────────────────────────────────────────────
// Rule 4 — Хвиля (§12.4)
// ────────────────────────────────────────────────────────────────────

const WAVE_MODIFIERS: Record<Wave, { mod: number; reason: string }> = {
  spring:     { mod: 0.05, reason: "Весняна хвиля" },
  summer1:    { mod: 0.05, reason: "Літо-1 хвиля" },
  summer2:    { mod: 0.05, reason: "Літо-2 хвиля" },
  autumn:     { mod: 0.15, reason: "Осіння хвиля (пік)" },
  late:       { mod: 0.05, reason: "Пізня хвиля" },
};

// FIX 8.7b (2026-10-12): peak-гілка (+0.05) видалена.
// Дублювалась з scorer.ts (peak_wave_bonus_enabled flag) —
// давала +0.10 замість +0.05 за один факт (wave ∈ rule.peakWaves).
// WAVE_MODIFIERS тепер — чиста таблиця клімату хвиль.
// Peak-бонус виду керується flag у scorer.ts (SQL kill-switch).
// Див. docs/8.7b_peak_bonus_fix.md.
export const rule4_Waves: DynamicRule = (_rule, ctx) => {
  const entry = WAVE_MODIFIERS[ctx.wave];
  return { modifier: entry.mod, reason: entry.reason };
};

// ────────────────────────────────────────────────────────────────────
// Rule 5 — Види-індикатори (§12.5, anti-double-counting)
// ────────────────────────────────────────────────────────────────────

export const rule5_Indicators: DynamicRule = (rule, ctx) => {
  if (rule.mushroomType !== "boletus_edulis") {
    return { modifier: 0, skip: true };
  }
  if (rule.indicatorSpecies.length === 0) {
    return { modifier: 0, skip: true };
  }
  const found = rule.indicatorSpecies.filter((s) =>
    ctx.crowd.indicatorSpecies.includes(s)
  );
  if (found.length > 0) {
    return { modifier: 0.10, reason: `Індикатори: ${found.join(", ")}` };
  }
  return { modifier: 0 };
};

// ────────────────────────────────────────────────────────────────────
// Rule 6 — Температура міцелію (§12.6)
// ────────────────────────────────────────────────────────────────────

export const rule6_MyceliumTemp: DynamicRule = (rule, ctx) => {
  const w = ctx.weather;
  if (w.tempMax > 28 || w.tempMin < 0) {
    return { modifier: -0.15, reason: "Різкі перепади температур" };
  }
  const avg = w.tempAvg14d;
  if (
    rule.myceliumTempMin !== null &&
    rule.myceliumTempMax !== null &&
    avg >= rule.myceliumTempMin &&
    avg <= rule.myceliumTempMax
  ) {
    return {
      modifier: 0.10,
      reason: `Стабільна t° ${avg}°C (оптимум ${rule.myceliumTempMin}–${rule.myceliumTempMax})`,
    };
  }
  return { modifier: 0 };
};

// ────────────────────────────────────────────────────────────────────
// Rule 8 — Сезонний мікрорефугіум (§12.8)
// ────────────────────────────────────────────────────────────────────

export const rule8_SeasonMicrorefugium: DynamicRule = (rule, ctx) => {
  const s = ctx.weather.soilState;
  if (s === "dry") {
    return {
      modifier: 0,
      reason: "Сухо — мікрорефугіум",
      overrideWhere: rule.microrefugiumDry ?? null,
    };
  }
  if (s === "wet" || s === "waterlogged") {
    return {
      modifier: 0,
      reason: "Волого — мікрорефугіум",
      overrideWhere: rule.microrefugiumWet ?? null,
    };
  }
  return { modifier: 0 };
};

/** Порядок застосування (§12) */
export const MVP_RULES: DynamicRule[] = [
  rule1_StandAge,
  rule2_DroughtThenRain,
  rule3_MicrorefugiumBoletus,
  rule4_Waves,
  rule5_Indicators,
  rule6_MyceliumTemp,
  rule8_SeasonMicrorefugium,
];
