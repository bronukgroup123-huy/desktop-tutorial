// ============================================================================
// Forecast Engine — Calibration (plan v6.0 §14)
//
// Калібрування точності прогнозу по верифікованих picks:
//   precision(species) = count(actualFound=true) / total
//   цільова точність    = CALIBRATION_TARGET (0.5)
//   tolerance          = ±CALIBRATION_TOLERANCE (0.1)
//   precision нижче цілі − tolerance → weight −0.05 за цикл
//   precision вище цілі + tolerance → weight +0.05 за цикл
//   інакше — у нормі, skip
//
// Логи з predictedLevel='no_data' пропускаються (прогнозу не було).
// Чиста логіка: без supabase-js, без I/O.
// ============================================================================

import type { ProbabilityLevel } from "./types.ts";

/** Один верифікований pick для калібрування */
export interface CalibrationInput {
  species: string;
  predictedLevel: ProbabilityLevel; // 'no_data' | 'low' | 'medium' | 'high' | 'peak'
  actualFound: boolean;
  date: string; // ISO — для групування по віку
}

/** Пропозиція коригування ваги виду */
export interface CalibrationAdjustment {
  species: string;
  param: "weight";
  delta: number; // ±0.05 за цикл
  reason: string;
  newValue?: number; // якщо відома поточна вага
}

/** Цільова precision для калібрування */
export const CALIBRATION_TARGET = 0.5;

/** Допустиме відхилення від цілі (у нормі — без змін) */
export const CALIBRATION_TOLERANCE = 0.1;

/** Максимальна зміна ваги за один цикл */
export const CALIBRATION_MAX_DELTA = 0.05;

/**
 * Порахувати adjustments по логах калібрування.
 *
 * Логіка per species:
 *   - фільтрація: логи з predictedLevel='no_data' виключаються
 *   - precision = count(actualFound=true) / total
 *   - precision < TARGET − TOLERANCE → delta = −MAX_DELTA (переоцінка)
 *   - precision > TARGET + TOLERANCE → delta = +MAX_DELTA (недооцінка)
 *   - інакше — skip
 *
 * Порядок adjustments — за першою появою species у logs (стабільна ітерація Map).
 */
export function calibrate(logs: CalibrationInput[]): CalibrationAdjustment[] {
  const groups = new Map<string, { total: number; found: number }>();

  for (const log of logs) {
    // 'no_data' не має прогнозу — не бере участь у precision
    if (log.predictedLevel === "no_data") continue;

    let group = groups.get(log.species);
    if (!group) {
      group = { total: 0, found: 0 };
      groups.set(log.species, group);
    }
    group.total += 1;
    if (log.actualFound) group.found += 1;
  }

  const adjustments: CalibrationAdjustment[] = [];

  for (const [species, group] of groups) {
    if (group.total === 0) continue;

    const precision = group.found / group.total;
    const lower = CALIBRATION_TARGET - CALIBRATION_TOLERANCE;
    const upper = CALIBRATION_TARGET + CALIBRATION_TOLERANCE;

    if (precision < lower) {
      adjustments.push({
        species,
        param: "weight",
        delta: -CALIBRATION_MAX_DELTA,
        reason:
          `precision ${precision.toFixed(2)} < target ${CALIBRATION_TARGET} - tolerance ${CALIBRATION_TOLERANCE} ` +
          `(${group.found}/${group.total} found) — знизити вагу`,
      });
    } else if (precision > upper) {
      adjustments.push({
        species,
        param: "weight",
        delta: CALIBRATION_MAX_DELTA,
        reason:
          `precision ${precision.toFixed(2)} > target ${CALIBRATION_TARGET} + tolerance ${CALIBRATION_TOLERANCE} ` +
          `(${group.found}/${group.total} found) — підвищити вагу`,
      });
    }
    // у нормі [lower..upper] — skip
  }

  return adjustments;
}
