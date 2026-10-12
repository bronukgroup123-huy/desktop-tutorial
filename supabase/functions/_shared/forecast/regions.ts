// ============================================================================
// Forecast Engine — Region helper (group 8.6a)
//
// Типізована обгортка над RPC point_in_region (мigration 00011).
// Використовується RegionGuard (8.6b): hard-fail, якщо точка поза
// домашнім регіоном.
// Не тягне supabase-js — структурний ForecastDbClient як у context.ts.
// ============================================================================

import type { ForecastDbClient } from "./context.ts";

/**
 * Перевіряє, чи точка в межах регіону.
 *
 * Graceful: помилка RPG, null у відповіді або regionId=null → false
 * (не блокувати прогноз — RegionGuard сам вирішить, що робити).
 */
export async function pointInRegion(
  db: ForecastDbClient,
  lat: number,
  lng: number,
  regionId: number | null
): Promise<boolean> {
  if (regionId === null) return false; // без homeRegionId — немає що перевіряти

  const { data, error } = await db.rpc("point_in_region", {
    lat,
    lng,
    region_id: regionId,
  });

  if (error) return false; // graceful — RPC-збій не валить прогноз
  return data === true;
}
