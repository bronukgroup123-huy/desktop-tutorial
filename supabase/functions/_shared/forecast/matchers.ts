// Група 8.3 — Matchers: geo / weather / season / soil
// Контракт: { score: 0..1, reasons: string[], hardFail: boolean }
import type { SpeciesRule, ForecastContext, WeatherData, Wave } from './types.ts';
import { isInSeason, toMmdd } from './constants.ts';

export interface MatcherResult {
  score: number;
  reasons: string[];
  hardFail: boolean;
}

export const WAVE_KEY: Record<Wave, 'waveSpring' | 'waveSummer1' | 'waveSummer2' | 'waveAutumn' | 'waveLate'> = {
  spring: 'waveSpring',
  summer1: 'waveSummer1',
  summer2: 'waveSummer2',
  autumn: 'waveAutumn',
  late: 'waveLate',
};

function intersects(a: string[] | null | undefined, b: string[] | null | undefined): boolean {
  if (!a || !b || a.length === 0 || b.length === 0) return false;
  const setB = new Set(b);
  return a.some(x => setB.has(x));
}

// ─── Тип лісу: зв'язки між типами ───────────────────────────
/** Породи хвойних і листяних (типи лісу з порідним складом). */
export const CONIFER_TYPES = ['pine', 'spruce'] as const;
export const BROADLEAF_TYPES = ['oak', 'birch', 'aspen', 'alder', 'beech', 'hornbeam'] as const;

/**
 * Ліс загального типу без породи (за супутником або «хвойний» в OSM): вид із конкретною
 * породою тут, найімовірніше, є, але певності немає — трохи нижче.
 */
export const GROUP_FIT = 0.85;
/** Мішаний ліс: невідомо, чи є саме потрібна порода. */
export const MIXED_FIT = 0.8;

const isConifer = (t: string) => (CONIFER_TYPES as readonly string[]).includes(t);
const isBroadleaf = (t: string) => (BROADLEAF_TYPES as readonly string[]).includes(t);

/**
 * Наскільки тип лісу ділянки [forest] підходить виду зі списком типів [ruleTypes]:
 * 1 — підходить, 0 — ні (вид у цьому лісі не росте), між — загальний або мішаний ліс без
 * відомої породи. Раніше потрібен був точний збіг слова, і вид зникав, напр., у мішаному лісі
 * (немає в списку білого) або в «хвойному» лісі за супутником (у маслюка в списку лише сосна).
 */
export function forestFit(ruleTypes: string[], forest: string): { score: number; reason: string } {
  const has = (t: string) => ruleTypes.includes(t);
  const anyConifer = ruleTypes.some(isConifer) || has('coniferous');
  const anyBroadleaf = ruleTypes.some(isBroadleaf) || has('deciduous');
  const match = { score: 1, reason: `forest match: ${forest}` };

  if (has(forest) || has('any') || forest === 'any') return match;
  // Ліс конкретної породи: якщо у виду перелічені породи — головні вони (березняк не підходить
  // білому, у якого в списку сосна, ялина, дуб). Загальний тип виду («листяний», «мішаний»)
  // діє, лише коли порід у списку немає.
  if (isConifer(forest) || isBroadleaf(forest)) {
    const listsSpecies = ruleTypes.some((t) => isConifer(t) || isBroadleaf(t));
    const group = isConifer(forest) ? 'coniferous' : 'deciduous';
    if (!listsSpecies && (has(group) || has('mixed'))) return match;
    return { score: 0, reason: `forest mismatch: ${forest}` };
  }

  if (forest === 'coniferous') {
    if (ruleTypes.some(isConifer)) return { score: GROUP_FIT, reason: 'forest group: coniferous' };
    if (has('mixed')) return { score: GROUP_FIT, reason: 'forest group: coniferous' };
  }
  if (forest === 'deciduous') {
    if (ruleTypes.some(isBroadleaf)) return { score: GROUP_FIT, reason: 'forest group: deciduous' };
    if (has('mixed')) return { score: GROUP_FIT, reason: 'forest group: deciduous' };
  }
  if (forest === 'mixed' && (anyConifer || anyBroadleaf)) {
    return { score: MIXED_FIT, reason: 'forest group: mixed' };
  }
  return { score: 0, reason: `forest mismatch: ${forest}` };
}

// ─── matchGeo ────────────────────────────────────────────────
export function matchGeo(rule: SpeciesRule, ctx: ForecastContext): MatcherResult {
  const reasons: string[] = [];
  const input = ctx.input;

  // HARD: forest type (тільки якщо підтверджено і є обмеження). Типи пов'язані між собою:
  // «хвойний» ⊃ сосна, ялина; «листяний» ⊃ дуб, береза…; «мішаний» = хвойні + листяні.
  let forestScore = 1.0;
  if (input.forestConfirmed && input.forestType && rule.forestType.length > 0) {
    const fit = forestFit(rule.forestType, input.forestType);
    if (fit.score === 0) {
      return {
        score: 0,
        reasons: [`forest mismatch: need ${rule.forestType.join('|')}, got ${input.forestType}`],
        hardFail: true,
      };
    }
    forestScore = fit.score;
    reasons.push(fit.reason);
  } else if (!input.forestConfirmed) {
    reasons.push('forest not confirmed — skip');
  }

  let score = forestScore;

  // SOFT: relief (тільки якщо flag enabled і є дані)
  if (ctx.config.relief_enabled && ctx.reliefType && rule.reliefType.length > 0) {
    if (intersects(rule.reliefType, [ctx.reliefType])) {
      reasons.push(`relief match: ${ctx.reliefType}`);
    } else {
      score *= 0.7;
      reasons.push(`relief soft-miss: ${ctx.reliefType}`);
    }
  }

  // SOFT: stand age
  if (!ctx.standAgeUnknown && ctx.standAge !== null &&
      (rule.standAgeMin !== null || rule.standAgeMax !== null)) {
    const min = rule.standAgeMin ?? 0;
    const max = rule.standAgeMax ?? 999;
    if (ctx.standAge < min || ctx.standAge > max) {
      score *= 0.5;
      reasons.push(`stand age ${ctx.standAge}y outside [${min},${max}]`);
    } else {
      reasons.push(`stand age ${ctx.standAge}y in [${min},${max}]`);
    }
  }

  // PASSTHROUGH: habitat, altitude (немає джерела в input)
  if (rule.habitatType.length > 0) reasons.push('habitat: passthrough (no input)');
  if (rule.altitudeMin !== null || rule.altitudeMax !== null) reasons.push('altitude: passthrough (no input)');

  return { score, reasons, hardFail: false };
}

// ─── matchWeather ────────────────────────────────────────────
export function matchWeather(rule: SpeciesRule, weather: WeatherData): MatcherResult {
  const reasons: string[] = [];

  if (weather.source === 'unavailable') {
    return { score: 1.0, reasons: ['weather unavailable — passthrough'], hardFail: false };
  }

  const t = weather.tempAvg7d;

  // HARD: fruiting temp range
  if (rule.fruitingTempMin !== null && t < rule.fruitingTempMin) {
    return { score: 0, reasons: [`temp ${t} < min ${rule.fruitingTempMin}`], hardFail: true };
  }
  if (rule.fruitingTempMax !== null && t > rule.fruitingTempMax) {
    return { score: 0, reasons: [`temp ${t} > max ${rule.fruitingTempMax}`], hardFail: true };
  }

  let score = 0.6;
  reasons.push(`temp ${t} within fruiting range`);

  // BONUS: peak temp
  if (rule.fruitingTempPeakMin !== null && rule.fruitingTempPeakMax !== null &&
      t >= rule.fruitingTempPeakMin && t <= rule.fruitingTempPeakMax) {
    score += 0.2;
    reasons.push(`in peak temp [${rule.fruitingTempPeakMin},${rule.fruitingTempPeakMax}]`);
  }

  // Humidity
  if (rule.humidityMin !== null) {
    if (weather.humidity < rule.humidityMin) {
      score -= 0.1;
      reasons.push(`humidity ${weather.humidity} < ${rule.humidityMin}`);
    } else {
      score += 0.05;
      reasons.push('humidity ok');
    }
  }

  // Rain 3d
  if (rule.rain3dMin !== null) {
    if (weather.rain3d < rule.rain3dMin) {
      score -= 0.15;
      reasons.push(`rain3d ${weather.rain3d} < ${rule.rain3dMin}`);
    } else {
      score += 0.05;
      reasons.push('rain3d ok');
    }
  }

  // Drought (hard-ish penalties)
  if (rule.droughtDaysMin !== null && weather.droughtDays >= rule.droughtDaysMin) {
    if (rule.droughtThenRain && weather.rain1d >= 5) {
      score += 0.15;
      reasons.push('drought → rain trigger');
    } else {
      score -= 0.15;
      reasons.push(`drought ${weather.droughtDays}d ≥ ${rule.droughtDaysMin} no trigger`);
    }
  }

  // Days after rain
  if (rule.daysAfterRainMin !== null || rule.daysAfterRainMax !== null) {
    const dar = weather.daysAfterRain;
    const min = rule.daysAfterRainMin ?? 0;
    const max = rule.daysAfterRainMax ?? 999;
    if (dar >= min && dar <= max) {
      score += 0.05;
      reasons.push(`daysAfterRain ${dar} in [${min},${max}]`);
    } else {
      score -= 0.1;
      reasons.push(`daysAfterRain ${dar} outside [${min},${max}]`);
    }
  }

  // Shock
  if (rule.shockRequired && weather.tempMin < 5) {
    score += 0.1;
    reasons.push('shock required (tempMin<5)');
  }

  score = Math.max(0, Math.min(1, score));
  return { score, reasons, hardFail: false };
}

// ─── matchSeason ─────────────────────────────────────────────
export function matchSeason(rule: SpeciesRule, ctx: ForecastContext): MatcherResult {
  const reasons: string[] = [];
  const wave = ctx.wave;
  const mmdd = toMmdd(ctx.input.date);

  // HARD: wave boolean
  const waveKey = WAVE_KEY[wave];
  const allowed = rule[waveKey] as boolean;
  if (allowed === false) {
    return { score: 0, reasons: [`wave "${wave}" not allowed (${waveKey}=false)`], hardFail: true };
  }
  reasons.push(`wave "${wave}" allowed`);

  // HARD: season MM-DD range
  if (rule.seasonStart && rule.seasonEnd) {
    if (!isInSeason(mmdd, rule.seasonStart, rule.seasonEnd)) {
      return {
        score: 0,
        reasons: [`${mmdd} outside season [${rule.seasonStart}..${rule.seasonEnd}]`],
        hardFail: true,
      };
    }
    reasons.push(`${mmdd} in season`);
  }

  let score = 0.5;

  // BONUS: peak wave
  if (rule.peakWaves.length > 0 && rule.peakWaves.includes(wave)) {
    score += 0.3;
    reasons.push(`peak wave: ${wave}`);
  }

  // BONUS: peak month
  if (rule.peakMonths.length > 0) {
    const month = ctx.input.date.getUTCMonth() + 1;
    if (rule.peakMonths.includes(month)) {
      score += 0.2;
      reasons.push(`peak month: ${month}`);
    }
  }

  score = Math.max(0, Math.min(1, score));
  return { score, reasons, hardFail: false };
}

// ─── matchSoil ───────────────────────────────────────────────
// Не класичний матчер, а МНОЖНИК до base score (0..1)
export function matchSoil(rule: SpeciesRule, weather: WeatherData): MatcherResult {
  if (weather.source === 'unavailable') {
    return { score: 1.0, reasons: ['weather unavailable — soil passthrough'], hardFail: false };
  }

  const state = weather.soilState;
  const reasons: string[] = [];
  let multiplier = 1.0;

  if (state === 'waterlogged') {
    const penalty = rule.waterloggedPenalty ?? 0.5;
    multiplier = 1 - penalty;
    reasons.push(`waterlogged → ×${multiplier.toFixed(2)} (penalty ${penalty})`);
  } else if (state === 'dry') {
    multiplier = 0.7;
    reasons.push('dry → ×0.7');
  } else if (state === 'wet') {
    reasons.push('wet → ×1.0');
  } else {
    reasons.push('normal → ×1.0');
  }

  return { score: multiplier, reasons, hardFail: false };
}
