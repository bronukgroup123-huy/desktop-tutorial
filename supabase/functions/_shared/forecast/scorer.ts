// ============================================================================
// Forecast Engine — Scorer core (group 8.4a) + Dynamic Rules (group 8.4b)
//
// Комбінує виходи матчерів (8.3):
//   1) адитивна база: geo/weather/season (погода — найсильніший сигнал)
//   2) буфер температури (§11.2): transition zone → ×0.7
//   3) мультиплікатор ґрунту (soil.score)
//   4) peak wave bonus (feature flag)
//   5) динамічні правила 1–6, 8 (§12) як адитивні дельти
// CrowdAdjuster/Fallback — група 8.5.
// ============================================================================

import type {
  SpeciesRule,
  ForecastContext,
  ScoredSpecies,
  ProbabilityLevel,
} from "./types.ts";
import { matchGeo, matchWeather, matchSeason, matchSoil } from "./matchers.ts";
import { MVP_RULES } from "./rules.ts";

/** Ваги адитивних сигналів (§11.2): погода важить найбільше */
const W_GEO = 1.0;
const W_WEATHER = 1.5;
const W_SEASON = 1.0;

/** Множик transition zone температур (§11.2) */
const TRANSITION_MULTIPLIER = 0.7;

/** Бонус за peak wave (якщо увімкнено flag) */
const PEAK_WAVE_BONUS = 0.05;

/**
 * Скор → ймовірнісний рівень (границі інклюзивні зверху):
 * <0.30 no_data | <0.50 low | <0.70 medium | <0.90 high | ≥0.90 peak
 */
export function scoreToLevel(score: number): ProbabilityLevel {
  if (score < 0.30) return "no_data";
  if (score < 0.50) return "low";
  if (score < 0.70) return "medium";
  if (score < 0.90) return "high";
  return "peak";
}

/**
 * Оцінити один вид.
 *
 * matched = позитивні reasons матчерів + reasons правил, що ПІДВИЩИЛИ скор;
 * missed  = hardFail → його reasons; інакше — обмежувальні фактори: негативні reasons
 *           матчерів (вологість/дощ нижче норми, сухий ґрунт…), правила з від'ємною
 *           дельтою, перехідна зона температури. Без цього клієнт бачив лише «✓» при
 *           низькому рівні (рівень знижували фактори, яких ніде не було видно).
 * where   = overrideWhere від Rule 3/8, інакше fallback за soilState.
 */
export function scoreSpecies(rule: SpeciesRule, ctx: ForecastContext): ScoredSpecies {
  const noData = (matched: string[]): ScoredSpecies => ({
    mushroom_type: rule.mushroomType,
    name_ua: rule.nameUa,
    score: 0,
    probability: "no_data",
    matched,
    missed: [],
    wave: ctx.wave,
    where: null,
  });

  // 8.4b РІШЕННЯ 3: погода недоступна → no_data, а не «peak без даних»
  if (ctx.weather.source === "unavailable") {
    return noData(["Погода недоступна"]);
  }

  const geo = matchGeo(rule, ctx);
  const weather = matchWeather(rule, ctx.weather);
  const season = matchSeason(rule, ctx);
  const soil = matchSoil(rule, ctx.weather);

  const results = [geo, weather, season, soil];
  const hardFails = results.filter((r) => r.hardFail);

  if (hardFails.length > 0) {
    return {
      ...noData(results.filter((r) => !r.hardFail).flatMap((r) => r.reasons)),
      missed: hardFails.flatMap((r) => r.reasons),
    };
  }

  // 1) Адитивна база
  let score =
    (geo.score * W_GEO + weather.score * W_WEATHER + season.score * W_SEASON) /
    (W_GEO + W_WEATHER + W_SEASON);

  // 2) Буфер температури (§11.2): межа ±buffer °C від fruiting range.
  //    Повний скор у [min+buffer, max-buffer], перехідна зона — ×0.7.
  const buffer = ctx.config.fruiting_temp_buffer ?? 3;
  const t = ctx.weather.tempAvg7d;
  let inTransition = false;
  if (rule.fruitingTempMin !== null && t < rule.fruitingTempMin + buffer) {
    inTransition = true;
  }
  if (rule.fruitingTempMax !== null && t > rule.fruitingTempMax - buffer) {
    inTransition = true;
  }
  if (inTransition) score *= TRANSITION_MULTIPLIER;

  // 3) Мультиплікатор стану ґрунту
  score *= soil.score;

  // 4) Peak wave bonus
  if (
    ctx.config.peak_wave_bonus_enabled &&
    rule.peakWaves.includes(ctx.wave) &&
    score < 1.0
  ) {
    score = Math.min(1.0, score + PEAK_WAVE_BONUS);
  }

  // 5) Динамічні правила 1–6, 8 (§12) — адитивні дельти (8.4b РІШЕННЯ 2)
  const ruleReasons: string[] = [];
  const ruleLimits: string[] = [];
  let overrideWhere: string | null | undefined;
  for (const dynamicRule of MVP_RULES) {
    const res = dynamicRule(rule, ctx);
    if (res.skip) continue;
    score += res.modifier;
    if (res.reason) (res.modifier < 0 ? ruleLimits : ruleReasons).push(res.reason);
    if (res.overrideWhere) overrideWhere = res.overrideWhere;
  }

  score = Math.max(0, Math.min(1, score));
  const matcherReasons = results.flatMap((r) => r.reasons);

  const where =
    overrideWhere ??
    (ctx.weather.soilState === "dry"
      ? rule.microrefugiumDry
      : rule.microrefugiumWet) ??
    null;

  return {
    mushroom_type: rule.mushroomType,
    name_ua: rule.nameUa,
    score,
    probability: scoreToLevel(score),
    matched: [...matcherReasons.filter((r) => !isLimitingReason(r)), ...ruleReasons],
    missed: [
      ...matcherReasons.filter(isLimitingReason),
      ...(inTransition ? [TEMP_TRANSITION_REASON] : []),
      ...ruleLimits,
    ],
    wave: ctx.wave,
    where,
  };
}

/** Службовий reason: температура в перехідній зоні (скор ×0.7). */
export const TEMP_TRANSITION_REASON = "temp in transition zone";

/** Технічні reasons матчерів, що ЗНИЖУЮТЬ скор (а не підтверджують умови). */
export function isLimitingReason(reason: string): boolean {
  return /^(humidity [\d.]+ <|rain3d [\d.]+ <|drought \d+d .* no trigger|daysAfterRain \d+ outside|stand age \d+y outside|relief soft-miss|dry →|waterlogged →|forest not confirmed)/
    .test(reason);
}

/** Оцінити всі правила (без фільтрації/сортування — 8.5/8.6) */
export function scoreAll(rules: SpeciesRule[], ctx: ForecastContext): ScoredSpecies[] {
  return rules.map((rule) => scoreSpecies(rule, ctx));
}
