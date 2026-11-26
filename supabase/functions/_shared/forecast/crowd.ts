// ============================================================================
// Forecast Engine — CrowdAdjuster (group 8.5, план v6.0 §11.6, FIX 2.12)
//
// Коригує ймовірнісний рівень за знахідками спільноти ПОРУЧ із ділянкою за 7 днів (crowd_counts):
//   негативні звіти поруч > 0             → −1 рівень (домінує)
//   підтверджені знахідки ЦЬОГО виду ≥ 3  → +1 рівень
//   0–2                                   → без змін
// Відсутність знахідок прогноз не знижує: більшість лісів ніхто не відвідує, «немає знахідок» — не доказ
// відсутності грибів (як і «не знайшов», ADR-019 §19.9). Раніше тут було «0 → −1» по всій країні.
// Поріг рівня затиснений у [low..peak].
// FIX 2.12: 'no_data' НЕ підвищується (early return).
// ============================================================================

import type { ScoredSpecies, ProbabilityLevel, ForecastContext } from "./types.ts";

/** Порядок рівнів БЕЗ 'no_data' — він early-return вище (FIX 2.12) */
const LEVEL_ORDER: ProbabilityLevel[] = ["low", "medium", "high", "peak"];

export function applyCrowdAdjust(
  s: ScoredSpecies,
  ctx: ForecastContext,
): ScoredSpecies {
  // FIX 2.12: no_data НЕ підвищується — жодних краудсорсингових зсувів
  if (s.probability === "no_data") return s;

  // за видом (crowd_counts); старі контексти без розбивки — загальна кількість
  const picks = ctx.crowd.verifiedBySpecies
    ? ctx.crowd.verifiedBySpecies[s.mushroom_type] ?? 0
    : ctx.crowd.verifiedPicks7d;
  const negatives = ctx.crowd.negativeReports7d;

  let delta = 0;
  if (negatives > 0) delta -= 1;
  else if (picks >= 3) delta += 1;
  // picks 0–2 → delta 0

  const idx = LEVEL_ORDER.indexOf(s.probability);
  const newIdx = Math.max(0, Math.min(LEVEL_ORDER.length - 1, idx + delta));
  const newLevel: ProbabilityLevel = LEVEL_ORDER[newIdx];

  // Причини — у matched (реальне поле ScoredSpecies, 8.4a)
  const matched = [...s.matched];
  if (delta > 0) matched.push(`Поруч за тиждень підтвердили знахідки цього виду: ${picks}`);
  if (delta < 0 && negatives > 0) {
    matched.push(`Поруч за тиждень негативних звітів: ${negatives}`);
  }

  return { ...s, probability: newLevel, matched };
}
