// Група 8.3 — Matchers: geo / weather / season / soil
// Контракт: { score: 0..1, reasons: string[], hardFail: boolean }
import type { SpeciesRule, ForecastContext, WeatherData, Wave } from './types.ts';
import { isInSeason, toMmdd } from './constants.ts';

export interface MatcherResult {
  score: number;
  reasons: string[];
  hardFail: boolean;
}

const WAVE_KEY: Record<Wave, 'waveSpring' | 'waveSummer1' | 'waveSummer2' | 'waveAutumn' | 'waveLate'> = {
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

// ─── matchGeo ────────────────────────────────────────────────
export function matchGeo(rule: SpeciesRule, ctx: ForecastContext): MatcherResult {
  const reasons: string[] = [];
  const input = ctx.input;

  // HARD: forest type (тільки якщо підтверджено і є обмеження)
  if (input.forestConfirmed && input.forestType && rule.forestType.length > 0) {
    if (!intersects(rule.forestType, [input.forestType])) {
      return {
        score: 0,
        reasons: [`forest mismatch: need ${rule.forestType.join('|')}, got ${input.forestType}`],
        hardFail: true,
      };
    }
    reasons.push(`forest match: ${input.forestType}`);
  } else if (!input.forestConfirmed) {
    reasons.push('forest not confirmed — skip');
  }

  let score = 1.0;

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
