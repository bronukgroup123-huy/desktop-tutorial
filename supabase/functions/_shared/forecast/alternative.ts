// ============================================================================
// Forecast Engine — Alternative picker (group 8.5, план v6.0 §11.7)
//
// Вибирає альтернативний вид із відсортованого списку за 3 рівнями:
//   1) інший тип лісу (forestType) АБО інша хвиля (rule[waveKey])
//   2) інший рід (genus з nameLat)
//   3) наступний за скором (sorted[1])
//
// ScoredSpecies (8.4a) не несе повного правила — лише mushroom_type/name_ua.
// Тому дані правила беруться з rules-мапи за mushroom_type.
// ============================================================================

import type {
  ScoredSpecies,
  ForecastContext,
  SpeciesRule,
} from "./types.ts";
import { WAVE_KEY } from "./matchers.ts";

/** Різні типи лісу АБО різні значення поточної хвилі */
function differentForestOrWave(
  aRule: SpeciesRule,
  bRule: SpeciesRule,
  ctx: ForecastContext,
): boolean {
  if (aRule.forestType.join() !== bRule.forestType.join()) return true;
  const waveKey = WAVE_KEY[ctx.wave];
  return aRule[waveKey] !== bRule[waveKey];
}

export function pickAlternative(
  sorted: ScoredSpecies[],
  top1: ScoredSpecies,
  ctx: ForecastContext,
  rules: Map<string, SpeciesRule>,
): ScoredSpecies | null {
  if (sorted.length < 2) return null;

  const top1Rule = rules.get(top1.mushroom_type);

  // Рівень 1: інший тип лісу АБО інша хвиля
  if (top1Rule) {
    for (let i = 1; i < sorted.length; i++) {
      const candRule = rules.get(sorted[i].mushroom_type);
      if (candRule && differentForestOrWave(candRule, top1Rule, ctx)) {
        return sorted[i];
      }
    }

    // Рівень 2: інший рід (genus)
    const top1Genus = top1Rule.nameLat.split(" ")[0];
    for (let i = 1; i < sorted.length; i++) {
      const candRule = rules.get(sorted[i].mushroom_type);
      if (candRule && candRule.nameLat.split(" ")[0] !== top1Genus) {
        return sorted[i];
      }
    }
  }

  // Рівень 3: наступний за скором
  return sorted[1];
}
