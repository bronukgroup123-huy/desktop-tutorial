// ============================================================================
// Forecast Engine — CrowdAdjuster (group 8.5, план v6.0 §11.6, FIX 2.12)
//
// Коригує ймовірнісний рівень за краудсорсинговими даними:
//   negativeReports7d > 0 → −1 рівень (домінує)
//   verifiedPicks7d = 0   → −1 рівень
//   verifiedPicks7d ≥ 3   → +1 рівень
//   verifiedPicks7d 1–2   → без змін
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

  const picks = ctx.crowd.verifiedPicks7d;
  const negatives = ctx.crowd.negativeReports7d;

  let delta = 0;
  if (negatives > 0) delta -= 1;
  else if (picks === 0) delta -= 1;
  else if (picks >= 3) delta += 1;
  // picks 1–2 → delta 0

  const idx = LEVEL_ORDER.indexOf(s.probability);
  const newIdx = Math.max(0, Math.min(LEVEL_ORDER.length - 1, idx + delta));
  const newLevel: ProbabilityLevel = LEVEL_ORDER[newIdx];

  // Причини — у matched (реальне поле ScoredSpecies, 8.4a)
  const matched = [...s.matched];
  if (delta > 0) matched.push(`Краудсорсинг: ${picks} підтверджених знахідок`);
  if (delta < 0 && negatives > 0) {
    matched.push(`Краудсорсинг: ${negatives} негативних звітів`);
  }

  return { ...s, probability: newLevel, matched };
}
