// ============================================================================
// Forecast Engine — головний пайплайн (group 8.6b)
//
// RegionGuard → ContextBuilder → scoreAll → CrowdAdjuster → Rule 5
// anti-double → sort → pickAlternative → warnings → ForecastResult.
// Edge Functions (8.6c/d) викликають ForecastEngine.forecast().
//
// Адаптовано під реальні типи 8.4–8.6a:
//   - ScoredSpecies.probability / .matched / .mushroom_type (не .level/.rule)
//   - pickAlternative(sorted, top1, ctx, rulesMap) — 4-й параметр
//   - ForecastResult.noDataReason — camelCase
//   - config snake_case: region_filter_enabled, rule5_anti_double_counting_enabled
//   - db задовольняє ОБА інтерфейси: ForecastDbClient (context.ts) + DbClient (db.ts)
// ============================================================================

import type {
  ForecastInput,
  ForecastResult,
  ScoredSpecies,
  SpeciesRule,
} from "./types.ts";
import type { ForecastDbClient } from "./context.ts";
import type { DbClient } from "./db.ts";
import type { FeatureFlags } from "./flags.ts";
import { ContextBuilder } from "./context.ts";
import { findAllRules, findRegionById } from "./db.ts";
import { scoreAll } from "./scorer.ts";
import { applyCrowdAdjust } from "./crowd.ts";
import { pickAlternative } from "./alternative.ts";
import { buildFallback } from "./fallback.ts";
import { buildWarnings } from "./warnings.ts";
import { pointInRegion } from "./regions.ts";

/** Rule 5 anti-double-counting (§12.5): якщо топ — лисичка, білий гірше */
const ANTI_DOUBLE_TOP1 = "cantharellus_cibarius";
const ANTI_DOUBLE_TARGET = "boletus_edulis";
const ANTI_DOUBLE_PENALTY = 0.1;

export class ForecastEngine {
  /**
   * Повний прогноз для точки.
   *
   * db — клієнт, що задовольняє обидва структурні інтерфейси
   * (context.ts ForecastDbClient + db.ts DbClient); реальний supabase-js
   * є супер сетом обох.
   */
  static async forecast(
    input: ForecastInput,
    db: ForecastDbClient & DbClient,
    config: FeatureFlags
  ): Promise<ForecastResult> {
    const date = input.date.toISOString().slice(0, 10);
    const warnings: string[] = [];

    // ─── 1. RegionGuard (graceful: regions = 0 рядків → не блокуємо) ───
    if (config.region_filter_enabled) {
      if (input.homeRegionId === null) {
        warnings.push("Домашній регіон не вказано — перевірку регіону пропущено.");
      } else {
        const region = await findRegionById(db, input.homeRegionId);
        if (!region) {
          // регіон не seed-нуто (9.1) — не блокуємо, але попереджаємо
          warnings.push(
            `Регіон #${input.homeRegionId} не знайдено у довіднику — перевірку регіону пропущено.`,
          );
        } else {
          const inside = await pointInRegion(
            db,
            input.lat,
            input.lng,
            input.homeRegionId,
          );
          if (!inside) {
            return {
              regionName: null,
              date,
              forest: "",
              top1: null,
              alternative: null,
              warnings: ["Ви поза вашою областю."],
              noDataReason: "outside_home_region",
            };
          }
        }
      }
    }

    // ─── 2. Контекст: погода, crowd, wave, forest_zone ───
    const ctx = await ContextBuilder.build(input, db, config);

    // ─── 3. Rules ───
    const rules = await findAllRules(db);
    const rulesMap = new Map<string, SpeciesRule>(
      rules.map((r) => [r.mushroomType, r]),
    );

    // ─── 4. Score + фільтр hardFail (probability === 'no_data') ───
    const candidates = scoreAll(rules, ctx).filter(
      (s) => s.probability !== "no_data",
    );

    // ─── 5. Fallback при 0 кандидатів (сезонний, канонічні ID) ───
    if (candidates.length === 0) {
      return buildFallback(ctx, rules);
    }

    // ─── 6. CrowdAdjuster (FIX 2.12: no_data не підвищується) ───
    let adjusted: ScoredSpecies[] = candidates.map((s) =>
      applyCrowdAdjust(s, ctx),
    );

    // ─── 7. Rule 5 anti-double (§12.5, адаптовано під .mushroom_type) ───
    if (config.rule5_anti_double_counting_enabled) {
      const top1 = [...adjusted].sort((a, b) => b.score - a.score)[0];
      if (top1?.mushroom_type === ANTI_DOUBLE_TOP1) {
        adjusted = adjusted.map((s) =>
          s.mushroom_type === ANTI_DOUBLE_TARGET
            ? { ...s, score: Math.max(0, s.score - ANTI_DOUBLE_PENALTY) }
            : s,
        );
      }
    }

    // ─── 8. Sort + top1 + alternative (pickAlternative отримує rulesMap) ───
    const sorted = [...adjusted].sort((a, b) => b.score - a.score);
    const top1 = sorted[0];
    const alternative = pickAlternative(sorted, top1, ctx, rulesMap);

    // ─── 9. Warnings ───
    warnings.push(...buildWarnings(top1, ctx));

    // ─── 10. Result ───
    return {
      regionName: ctx.regionName,
      date,
      forest: ctx.forestTypeUnknown
        ? "Ліс: невідомо. Прогноз базовий."
        : `${input.forestType} (підтверджено), ${ctx.standAge ?? "?"} років`,
      top1,
      alternative,
      warnings,
    };
  }
}
