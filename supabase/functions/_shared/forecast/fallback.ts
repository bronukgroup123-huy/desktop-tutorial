// ============================================================================
// Forecast Engine — Fallback (group 8.5, план v6.0 §11.8 + FIX 2.10)
//
// Показується, коли основний прогноз не може дати top1 (тип лісу невідомий
// або жоден вид не пройшов фільтри). Базові види відкидаються за сезоном
// через matchSeason (FIX 2.10) — поза сезоном показуємо no-data,
// а не «бульбашку в снігу».
// ============================================================================

import type { SpeciesRule, ForecastContext, ForecastResult } from "./types.ts";
import { scoreSpecies } from "./scorer.ts";
import { matchSeason } from "./matchers.ts";

/**
 * Базові види, що трапляються майже завжди (канонічні ID каталогу
 * після канонізації: russula_spp/lycoperdon_spp мертві).
 */
export const BASIC_FALLBACK_SPECIES = [
  "russula_vesca",
  "lycoperdon_perlatum",
  "agaricus_campestris",
];

export function buildFallback(
  ctx: ForecastContext,
  allRules: SpeciesRule[],
): ForecastResult {
  const date = ctx.input.date.toISOString().slice(0, 10);
  const forest = "Ліс: невідомо. Прогноз базовий.";

  const basicRules = allRules.filter((r) =>
    BASIC_FALLBACK_SPECIES.includes(r.mushroomType)
  );

  // FIX 2.10: сезонний фільтр — лише ті, що не hard-fail за сезоном
  const seasonal = basicRules.filter(
    (r) => matchSeason(r, ctx).hardFail === false,
  );

  if (seasonal.length === 0) {
    return {
      regionName: ctx.regionName,
      date,
      forest,
      top1: null,
      alternative: null,
      warnings: ["Поза сезоном активного плодоношення."],
      noDataReason: "Немає даних для поточного сезону.",
    };
  }

  const scored = seasonal
    .map((r) => scoreSpecies(r, ctx))
    .sort((a, b) => b.score - a.score);

  return {
    regionName: ctx.regionName,
    date,
    forest,
    top1: scored[0] ?? null,
    alternative: scored[1] ?? null,
    warnings: ["Уточніть тип лісу на місці — це покращить прогноз."],
    noDataReason: "Жоден вид не пройшов фільтр. Показано базовий прогноз.",
  };
}
