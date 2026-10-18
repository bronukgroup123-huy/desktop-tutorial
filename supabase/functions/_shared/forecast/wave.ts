// ============================================================================
// Forecast Engine — Wave detection (§11.3)
// ============================================================================

import type { Wave } from "./types.ts";
import { WAVE_ORDER, GDD_THRESHOLDS } from "./constants.ts";

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
 * Визначити хвилю за §11.3 плану v6.0 (CT-11 — кумулятивний GDD):
 * 1. Latitude offset — північні області відстають
 * 2. Calendar wave — базова хвиля за місяцем
 * 3. GDD correction — кумулятивний GDD з таблиці gdd_state порівнюється
 *    з GDD_THRESHOLDS для уточнення хвилі.
 *
 * Якщо cumulative_gdd == 0 (дані ще не обчислено) — повертаємо calendar wave
 * (graceful degradation).
 */
export function detectWave(
  date: Date,
  lat: number,
  cumulativeGdd: number
): Wave {
  // Крок 1: latitude offset (50.45 — центральна Україна, південь — додатні дні)
  const latOffsetDays = Math.round((50.45 - lat) * 2.5);
  const adjustedDate = addDays(date, latOffsetDays);

  // Крок 2: календарна хвиля — базова
  let wave: Wave = calendarWave(adjustedDate);

  // Крок 3: GDD correction — кумулятивний GDD порівнюємо з порогами
  if (cumulativeGdd > 0) {
    const gddWave = waveFromGdd(cumulativeGdd);
    if (gddWave !== null) {
      wave = gddWave;
    }
  }

  return wave;
}

/**
 * Визначити хвилю за кумулятивним GDD і порогами GDD_THRESHOLDS.
 * Повертає null, якщо GDD не достатній для жодної хвилі (тоді залишаємо calendar).
 */
function waveFromGdd(cumulativeGdd: number): Wave | null {
  const thresholds = GDD_THRESHOLDS;
  const waves: Wave[] = ["spring", "summer1", "summer2", "autumn", "late"];

  // Знаходимо найвищу хвилю, чей поріг <= cumulativeGdd
  let result: Wave | null = null;
  for (const w of waves) {
    if (cumulativeGdd >= thresholds[w]) {
      result = w;
    } else {
      break;
    }
  }
  return result;
}
