// ============================================================================
// Forecast Engine — Wave detection (§11.3)
// ============================================================================

import type { Wave } from "./types.ts";
import { WAVE_ORDER } from "./constants.ts";

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
 *
 * FIX 8.7 (2026-10-12): GDD-корекція тимчасово вимкнена.
 *
 * Причина: computeGDD (weather.ts) дає 37-денне КОВЗНЕ вікно
 * (past_days=30 + forecast_days=7). Воно НЕ монотонне по сезону:
 * у листопаді GDD менше, ніж у жовтні. GDD_THRESHOLDS має
 * КУМУЛЯТИВНУ шкалу з 1 січня. Порівняння некоректне —
 * autumn:1500 ніколи не досягається з ковзним вікном, тому
 * жовтень деградував у summer2.
 *
 * Кумулятивний GDD → ticket V2: docs/8.7_gdd_fix.md.
 * До впровадження — довіряємо calendar wave.
 * Сигнатура (date, lat, gdd) збережена для сумісності з ContextBuilder.
 */
export function detectWave(
  date: Date,
  lat: number,
  gdd: number | null
): Wave {
  // gdd on purpose unused until cumulative GDD (ticket V2)
  void gdd;

  // Крок 1: latitude offset (50.45 — центральна Україна, південь — додатні дні)
  const latOffsetDays = Math.round((50.45 - lat) * 2.5);
  const adjustedDate = addDays(date, latOffsetDays);

  // Крок 2: календарна хвиля — єдине джерело істини до V2
  return calendarWave(adjustedDate);
}
