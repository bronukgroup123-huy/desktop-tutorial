// ============================================================================
// Forecast Engine — Wave detection (§11.3)
// ============================================================================

import type { Wave } from "./types.ts";
import { GDD_THRESHOLDS, WAVE_ORDER } from "./constants.ts";

/**
 * Додати N днів до дати.
 */
export function addDays(date: Date, days: number): Date {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}

/**
 * Календарна хвиля — за місяцем (без GDD).
 */
export function calendarWave(date: Date): Wave {
  const m = date.getUTCMonth() + 1;
  if (m >= 4 && m <= 5) return "spring";
  if (m === 6) return "summer1";
  if (m === 7 || m === 8) return "summer2";
  if (m === 9 || m === 10) return "autumn";
  return "late";
}

/**
 * Попередня хвиля у порядку WAVE_ORDER.
 */
export function previousWave(w: Wave): Wave {
  const i = WAVE_ORDER.indexOf(w);
  return WAVE_ORDER[Math.max(0, i - 1)];
}

/**
 * Визначити хвилю за §11.3 плану v6.0:
 * 1. Latitude offset — північні області відстають
 * 2. Calendar wave — базова хвиля за місяцем
 * 3. GDD adjustment — якщо GDD < порогу, беремо попередню хвилю
 *
 * F-7: GDD + latitude offset.
 */
export function detectWave(
  date: Date,
  lat: number,
  gdd: number | null
): Wave {
  // Крок 1: latitude offset (50.45 — центральна Україна, південь — додатні дні)
  const latOffsetDays = Math.round((50.45 - lat) * 2.5);
  const adjustedDate = addDays(date, latOffsetDays);

  // Крок 2: календарна хвиля
  const calWave = calendarWave(adjustedDate);

  // Крок 3: GDD (якщо доступний)
  if (gdd === null) return calWave;

  const threshold = GDD_THRESHOLDS[calWave];
  if (threshold !== undefined && gdd < threshold) {
    return previousWave(calWave);
  }
  return calWave;
}
