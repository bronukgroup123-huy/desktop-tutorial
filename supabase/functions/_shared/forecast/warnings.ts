// ============================================================================
// Forecast Engine — Warnings / When (group 8.5, план v6.0 §11.10)
// ============================================================================

import type { ForecastContext, ScoredSpecies, SpeciesRule } from "./types.ts";

/** Коли йти: вікно daysAfterRain АБО хвильовий дефолт */
export function buildWhen(ctx: ForecastContext, rule: SpeciesRule): string {
  const w = ctx.weather;
  const minD = rule.daysAfterRainMin ?? 5;
  const maxD = rule.daysAfterRainMax ?? 9;
  if (w.daysAfterRain >= minD && w.daysAfterRain <= maxD) {
    return `Зараз — ${w.daysAfterRain} днів після дощу`;
  }
  if (ctx.wave === "autumn") return "Весь період осінньої хвилі";
  if (ctx.wave === "late") return "Пізня хвиля, до заморозків";
  return "Найближчі 2–4 дні";
}

/** Попередження за хвилею та невідомим типом лісу */
export function buildWarnings(
  // _top1 reserved for future context-aware warnings (plan §11.10)
  _top1: ScoredSpecies | null,
  ctx: ForecastContext,
): string[] {
  const w: string[] = [];
  if (ctx.wave === "summer2") {
    w.push("Гриби другої хвилі часто червиві. Перевіряйте на місці.");
  }
  if (ctx.wave === "autumn") {
    w.push("Гриби міцні, чисті. Можуть з'являтися до перших заморозків.");
  }
  if (ctx.forestTypeUnknown) {
    w.push("Уточніть тип лісу на місці — це покращить прогноз.");
  }
  return w;
}
