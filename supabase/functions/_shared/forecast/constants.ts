// ============================================================================
// Forecast Engine — Constants (§11.3, §18.1)
// ============================================================================

import type { Wave } from "./types.ts";

/** GDD-пороги для хвиль (§11.3) */
export const GDD_THRESHOLDS: Record<Wave, number> = {
  spring: 150,
  summer1: 450,
  summer2: 900,
  autumn: 1500,
  late: 2100,
};

/** Порядок хвиль */
export const WAVE_ORDER: Wave[] = ["spring", "summer1", "summer2", "autumn", "late"];

// ============================================================================
// Сезонність (§18.1)
// ============================================================================

/**
 * Чи дата MM-DD в сезоні [start, end].
 * Підтримує сезони через рік (наприклад, 10-01 → 02-28).
 * @param mmdd формат 'MM-DD'
 */
export function isInSeason(
  mmdd: string,
  seasonStart: string,
  seasonEnd: string
): boolean {
  const d = toComparable(mmdd);
  const s = toComparable(seasonStart);
  const e = toComparable(seasonEnd);

  if (s <= e) {
    return d >= s && d <= e;         // звичайний сезон
  }
  return d >= s || d <= e;           // через рік (12-01 → 02-28)
}

/** '09-11' → 911 для коректного порівняння (сортований формат) */
function toComparable(mmdd: string): number {
  const m = mmdd.slice(0, 2);
  const d = mmdd.slice(3, 5);
  return Number(`${m}${d}`);
}

/** Поточний MM-DD для дати (UTC) */
export function toMmdd(date: Date): string {
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${m}-${d}`;
}
