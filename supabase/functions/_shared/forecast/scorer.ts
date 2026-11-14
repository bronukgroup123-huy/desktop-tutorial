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
import { MVP_RULES, rule1_StandAge, rule3_MicrorefugiumBoletus, rule5_Indicators, rule6_MyceliumTemp, rule8_SeasonMicrorefugium } from "./rules.ts";
import { type FruitingState, fruitingState } from "./fruiting.ts";
import type { MatcherResult } from "./matchers.ts";

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

  // Рушій плодоношення: є ряд погоди — рівень визначає фаза (хвиля / дозрівання / …),
  // а не календар (ADR-015 §15.8). Без ряду (старі виклики, тести) — попередня формула.
  const series = ctx.weatherSeries?.series;
  if (series && ctx.config.fruiting_model_enabled !== false) {
    const fr = fruitingState(series, ctx.input.date.toISOString().slice(0, 10), rule.fruiting, rule.mushroomType);
    if (fr) return scoreWithFruiting(rule, ctx, { geo, weather, season, soil }, fr);
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

/** Базовий рівень поза хвилею: «Низька» — поодинокі гриби можливі. */
const PHASE_BASE: Record<Exclude<FruitingState["phase"], "flush">, number> = { maturing: 0.36, after: 0.36, idle: 0.32 };
/** Книжкове «наймасовіше …» — у ці місяці хвилі рясніші. */
const PEAK_MONTH_BONUS = 0.05;
/** Правила, що лишаються з рушієм плодоношення (календар хвиль і «дощ після посухи» — у ньому). */
const FRUITING_RULES = [rule1_StandAge, rule3_MicrorefugiumBoletus, rule5_Indicators, rule6_MyceliumTemp, rule8_SeasonMicrorefugium];
/** Причини матчерів, які рушій плодоношення замінює (вікна дощу й посухи). */
const SUPERSEDED = /^(rain3d|drought|daysAfterRain)/;

const fmt = (d?: string) => (d ? `${d.slice(8, 10)}.${d.slice(5, 7)}` : "");

/** Технічна причина про стан плодоношення (людський підпис — forecast-labels.ts). */
export function fruitingReason(fr: FruitingState, rule: SpeciesRule): string {
  switch (fr.phase) {
    case "flush":
      return `fruiting flush ${fr.flushDay}/${fr.flushDays} ${rule.fruiting.trigger} ${fr.triggerRain} ${fmt(fr.triggerDate)}`;
    case "maturing":
      return `fruiting maturing ${rule.fruiting.trigger} ${fr.triggerRain} ${fmt(fr.triggerDate)} until ${fmt(fr.expectedStart) || "?"}`;
    case "after":
      return `fruiting after ${fmt(fr.flushEnded)}`;
    case "idle":
      return `fruiting idle ${rule.fruiting.trigger} ${rule.fruiting.triggerRainMm}`;
  }
}

function scoreWithFruiting(
  rule: SpeciesRule,
  ctx: ForecastContext,
  m: { geo: MatcherResult; weather: MatcherResult; season: MatcherResult; soil: MatcherResult },
  fr: FruitingState,
): ScoredSpecies {
  let score = fr.phase === "flush" ? 0.45 + 0.5 * fr.intensity : PHASE_BASE[fr.phase];
  // Умови місця: тип і вік лісу (geo), стан ґрунту (сухо / перезволожено).
  score *= m.geo.score * m.soil.score;
  const month = ctx.input.date.getUTCMonth() + 1;
  const peakMonth = rule.peakMonths.includes(month);
  if (peakMonth && fr.phase === "flush") score += PEAK_MONTH_BONUS;

  const ruleReasons: string[] = [];
  const ruleLimits: string[] = [];
  let overrideWhere: string | null | undefined;
  for (const dynamicRule of FRUITING_RULES) {
    const res = dynamicRule(rule, ctx);
    if (res.skip) continue;
    // Стабільна температура вже врахована хвилею; лишаємо тільки різкі перепади (мінус).
    if (dynamicRule === rule6_MyceliumTemp && res.modifier > 0) continue;
    // Зимовому опеньку мороз не шкодить — відлига після нього якраз запускає хвилю.
    if (dynamicRule === rule6_MyceliumTemp && rule.fruiting.trigger === "thaw" && ctx.weather.tempMax <= 28) continue;
    score += res.modifier;
    if (res.reason) (res.modifier < 0 ? ruleLimits : ruleReasons).push(res.reason);
    if (res.overrideWhere) overrideWhere = res.overrideWhere;
  }
  score = Math.max(0, Math.min(1, score));

  const reasons = [m.geo, m.weather, m.season, m.soil].flatMap((r) => r.reasons)
    .filter((r) => !SUPERSEDED.test(r) && !r.startsWith("peak wave") && !(r.startsWith("peak month") && !peakMonth));
  const frReason = fruitingReason(fr, rule);
  const where = overrideWhere ??
    (ctx.weather.soilState === "dry" ? rule.microrefugiumDry : rule.microrefugiumWet) ?? null;
  return {
    mushroom_type: rule.mushroomType,
    name_ua: rule.nameUa,
    score,
    probability: scoreToLevel(score),
    matched: [...(fr.phase === "flush" ? [frReason] : []), ...reasons.filter((r) => !isLimitingReason(r)), ...ruleReasons],
    missed: [...(fr.phase === "flush" ? [] : [frReason]), ...reasons.filter(isLimitingReason), ...ruleLimits],
    wave: ctx.wave,
    where,
    fruiting: fr,
  };
}

/** Службовий reason: температура в перехідній зоні (скор ×0.7). */
export const TEMP_TRANSITION_REASON = "temp in transition zone";

/** Технічні reasons матчерів, що ЗНИЖУЮТЬ скор (а не підтверджують умови). */
export function isLimitingReason(reason: string): boolean {
  return /^(humidity [\d.]+ <|rain3d [\d.]+ <|drought \d+d .* no trigger|daysAfterRain \d+ outside|stand age \d+y outside|relief soft-miss|dry →|waterlogged →|forest not confirmed|forest group|fruiting (maturing|after|idle))/
    .test(reason);
}

/** Оцінити всі правила (без фільтрації/сортування — 8.5/8.6) */
export function scoreAll(rules: SpeciesRule[], ctx: ForecastContext): ScoredSpecies[] {
  return rules.map((rule) => scoreSpecies(rule, ctx));
}
